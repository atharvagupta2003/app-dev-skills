---
name: offline-outbox-and-sync
description: Queue a mobile app's writes on the device and send them later safely. Covers an outbox with idempotency keys, debounced and batched flushes, exponential backoff, treating a server rate limit as a wait until its stated reset, dropping permanently invalid items, merging late server state without overwriting unsent work or moving the user mid step, and time zones for daily limits. Load when a write can fail offline, when the server caps writes per day, or when a launch merges server state with local state.
---

# Offline outbox and sync

## When to use this
- A user can answer, edit or send while offline, or while the network is slow.
- The server has a daily or per minute cap on a kind of write.
- The server's state can arrive after the user has already acted on the local copy.
- A retry loop reports errors to the user, or sends the same write every minute.

## Rules
1. **Give every send intent one idempotency key, and keep it across retries.** Drop it only on success or on a refusal the server will never accept. Why: a retry after a lost response must not create a second record.
2. **Keep one queued value per question or field.** A newer value replaces the queued one. Why: sending every keystroke wastes the cap and the battery.
3. **Debounce the flush, and batch by screen.** Hold the background flush while a screen collects several answers, then send them as one call. Why: a server that counts calls against a cap rewards one call per screen.
4. **Send in dependency order.** Send the thing that changes what others mean first. Why: sending answers before a change of mode can file them under the wrong place, and the server may drop them.
5. **Back off exponentially, with a cap.** Why: a fixed retry every few seconds drains the battery and hammers a server that is already struggling.
6. **A rate limit is a wait until the server's reset time, not a retry.** Read the reset time the server sends, add a small margin, and hold the queue until then. Report nothing to the user; the cap is a fact, not a fault. Why: retrying every minute against a daily cap does nothing but log errors.
7. **Never assume the server's day is UTC.** Use the time the server gives. The fallback is only a guess. Why: a daily cap that resets at local midnight in a named zone reset hours away from the guessed UTC midnight.
8. **Drop what the server will never accept, and only that.** A 4xx that is not retryable, or a named invalid item, leaves the queue. Keep 401 and 403, which may clear after a sign in. Why: a poison item blocks every item behind it forever.
9. **Keep the unsent local value over the server's older one.** Why: the server's copy is older than what the user just did.
10. **A late server answer must never move the user.** Apply it to the data only, and only when doing so cannot lose local work. Why: a screen that changes under a user's finger is worse than an old value.

## How to do it

### 1. The queue
```ts
type Outbox = {
  answers: Record<string, Answer>;   // question id to the latest value
  step: { key: string; version: string } | null;
  attempts: number;                  // consecutive failed flushes
  nextAttemptAt: number;             // epoch ms; no flush before this
  limitedUntil: number;              // epoch ms; the server's daily cap holds writes
};

export const backoffMs = (attempts: number) => Math.min(60_000, 2_000 * 2 ** Math.max(0, attempts - 1));
```

Persist the queue per user, and rehydrate it before the first flush. Skip hydration in the store's options and call rehydrate yourself, so nothing is written under the wrong user.

### 2. Acknowledge only what did not change
When a request succeeds, remove each sent value from the queue only if the queued value is still the one that was sent. A value edited while the request was in flight stays queued.

```ts
ack: (sent) => {
  const answers = { ...get().answers };
  for (const [id, v] of Object.entries(sent.answers ?? {})) {
    if (JSON.stringify(answers[id]) === JSON.stringify(v)) delete answers[id];
  }
  set({ answers });
},
```

### 3. The flush
- One flush at a time. A call that arrives while one is in flight returns the same promise.
- Order: profile basics, then the mode, then the answers with their step, then anything that depends on the answers.
- Refuse to start when offline, and set an offline status instead of an error.
- Read `nextAttemptAt` before sending. If it is in the future, schedule a retry for that moment.
- Triggers: a debounced enqueue (about 800 ms), the app returning to the foreground, the network coming back, and a screen releasing its hold.

### 4. Each error class
```ts
try {
  await api.sendAnswers(batch);
  queue.ack(batch);
} catch (e) {
  if (isRateLimit(e)) {
    const told = Date.parse(e.extra.until);                    // the server's reset time
    queue.limitAnswersUntil(Number.isFinite(told) ? told + 60_000 : fallbackReset(now));
    scheduleRetryAt(queue.limitedUntil);                       // one retry, at the reset
  } else if (isInvalidItem(e)) {
    queue.dropAnswers(e.extra.questions);                      // named by the server
    reportError(e);
  } else if (isPermanent4xx(e)) {
    queue.drop(batch); reportError(e);
  } else {
    queue.fail(now);                                           // back off, no report for a network error
  }
}
```

### 5. Merging the server's state at launch
The server's copy and the saved copy are merged once, at launch. The unsent queue wins over the server, field by field. A late server answer (one that arrived after the app had already drawn from the saved copy) is applied only when all of these hold:
- the user finished setup, so the answer cannot change where they are;
- nothing is waiting in the queue;
- nothing the answer would replace has changed since the launch merge (compare by reference).

Otherwise drop it. The next read gets the server's view anyway.

## Gotchas
- **Every minute, the same error.** A daily cap refused each flush, and each refusal was logged as an error. Cause: the cap was treated as a fault, and the retry was a fixed timer. Fix: read the reset time from the refusal, hold the queue until then, and report nothing.
- **The fallback reset was in the wrong zone.** The client guessed the next UTC midnight, but the server's day turns at midnight in its own period zone. Fix: use the server's time whenever it is sent; the fallback only covers a refusal without one.
- **A late retry overwrote a newer edit.** A retry carrying an old idempotency key was applied after a newer edit, and replaced it. Found in review and reproduced. Cause: the retry was accepted as a new write. Rule: a retried write must never replace a newer value. The notes do not record the fix used in the project, so write and test one before you rely on it.
- **A poison answer blocks the queue.** A saved answer the server rejects, sent first, stops every later answer from ever sending. Fix: drop the items the server names, then send the rest.
- **A mode change drops answers of other modes.** Sending answers before the mode change refuses the whole batch. Fix: send the mode first, then the answers.
- **A question outside the user's mode refuses the whole batch.** Fix: drop the named questions, or, if none are named, the ones that belong to another mode, and send the rest.
- **One bad item refuses the batch.** Batch calls are all or nothing on the server. Keep batches small enough that one bad item does not hide a good one, and drop the named item.
- **Half finished answers.** A partly filled multi-choice answer fails validation. Keep it queued but do not send it, so it does not refuse the batch.
- **The same write from two screens.** Use one in flight action per target across screens, so a double tap does not send twice under two keys.

## Checklist
- [ ] Each send intent has an idempotency key that survives retries.
- [ ] Each question or field keeps one queued value.
- [ ] Flush order follows the data's dependencies.
- [ ] Backoff is exponential and capped.
- [ ] A rate limit waits for the server's reset time, with no error report.
- [ ] Non retryable 4xx items are dropped; 401 and 403 are kept.
- [ ] `ack` removes only values that did not change in flight.
- [ ] A late server answer never changes the user's place, and never overwrites a queued value.
- [ ] No day boundary is computed in UTC on the client when the server uses another zone.

## Tests that prove it
- A test with a fake clock: a rate limit with a reset time holds the queue until that time, sends nothing before it, and reports no error.
- A test with a refusal that has no reset time: the fallback is used, and a test that a supplied reset time wins over it.
- A test that a named invalid item is dropped and the rest of the batch goes.
- A test that `ack` keeps an answer edited during the request.
- A test that a late answer is not applied when the queue is not empty, and not applied when a value changed since the launch merge.
- A test that backoff doubles and stops at the cap.

## Related skills
- `expo-app-start-performance`: the launch order that runs the merge.
- `react-query-in-react-native`: invalidation after a successful flush.
- `expo-router-route-gate`: a flush must never move the user to another route.
