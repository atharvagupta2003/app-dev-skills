---
name: deno-edge-function-testing
description: Testing Supabase Edge Functions written in Deno over real HTTP. Covers testing every action and error code, identity taken from the session and never the body, rate limits, real parallel races (two users redeeming one code, both sides leaving at once, parallel sends against a limit), restoring any setting a test changed, and refusing to run against a hosted project when a test deletes or purges. Load when writing or reviewing an Edge Function test or a function action.
---

# Deno Edge Function testing

## When to use this
- Adding or changing an action in an Edge Function.
- Adding a rule with a limit, a cap or a daily allowance.
- Writing a rule that two people can trigger at the same time.
- Writing a test that deletes accounts, purges data or runs a background job step.

## Rules
1. **Test every action and every error code over HTTP, as a real signed in user.** Call the function the way the app does, with a real token.
   Why: direct calls to the database skip the function's checks, so a bug in the function passes the database tests.
2. **Take the acting identity from the session token, never from the request body.** Write a test that sends another member's id in the body and expects the action to act on the caller only, or refuse.
   Why: the body is the client's own input. The function must not trust it.
3. **Test the limits, then reset the limit state before each limit test.** Call the reset helper first, and do not let a whole suite from one machine reach a per address limit by accident. Set up data with SQL when the setup would hit a limit.
   Why: a limit reached by setup steps makes later tests fail for a reason that has nothing to do with them.
4. **Test races with real parallel requests, not with sequential calls.** Use `Promise.all` over separate HTTP calls, then assert exactly one outcome. Examples: two users redeem one code and exactly one wins; both sides leave at once and the end state is one clean state; five parallel sends against a limit of three land exactly three and charge exactly three.
   Why: a sequential test always passes. The races are where the cap and the locks are tested.
5. **Assert that no parallel call returns a server error.** Every response in a race must be 2xx or a clean 4xx such as a busy retry.
   Why: a race that produces a 500 means a lock or a constraint was not handled, even when the final data looks right.
6. **Restore any setting the test changed to the value it read, not to a default.** Read the current value first, change it inside `try`, and put back the value that was read in `finally`.
   Why: a default is a guess about what the value was. A team may have set it by hand, and a test that writes a default over it changes something it did not own.
7. **Refuse to run a test that deletes, purges or creates accounts against anything but the local stack.** Check the host in the test helper module, at import time, and throw.
   Why: these tests create and delete data. A review of one project caught a purge test that would have run against a hosted database. The shared helper now refuses any host except local addresses.
8. **Use an idempotency key for every write, and test that a replay returns the same result.** The key goes in the body and the test sends the same key twice.
   Why: a retried request from a flaky network must not charge twice or create two rows.

## How to do it

A helper that calls a function over HTTP as a given user:

```ts
// supabase/functions/tests/helpers.ts (sketch)
const URL_ = Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:54321';

export function assertLocal(url: string): void {
  const host = new URL(url).hostname;
  if (host !== '127.0.0.1' && host !== 'localhost') {
    throw new Error(`Refusing to run: these tests delete and purge data, and only run against the local stack, not ${host}.`);
  }
}
assertLocal(URL_); // runs when the module loads, before any test

export async function call(fn: string, token: string | null, body: unknown) {
  const res = await fetch(`${URL_}/functions/v1/${fn}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}
```

Each function's tests group by behaviour, one `Deno.test` per rule:

```ts
Deno.test('items: a member cannot act on another member through the body', async () => {
  const a = await makeUser('a');
  const b = await makeUser('b');
  try {
    const r = await call('items', a.token, { action: 'rename', item_id: 'x', owner_id: b.id, name: 'new' });
    assertEquals(r.status, 404); // the item is not the caller's, and the body id was ignored
  } finally {
    await cleanup([a, b]);
  }
});
```

A race with real parallel connections:

```ts
Deno.test('race: two members redeem one code at once, one wins', async () => {
  const owner = await makeUser('owner');
  const x = await makeUser('x');
  const y = await makeUser('y');
  try {
    const code = await createCode(owner);
    const replies = await Promise.all([
      call('codes', x.token, { action: 'redeem', code, idempotency_key: crypto.randomUUID() }),
      call('codes', y.token, { action: 'redeem', code, idempotency_key: crypto.randomUUID() }),
    ]);
    replies.forEach((r) => assert(r.status < 500, `no 500: ${r.status}`));
    assertEquals(replies.filter((r) => r.status === 200).length, 1);
  } finally {
    await cleanup([owner, x, y]);
  }
});
```

A setting the test changes, restored from what was read:

```ts
async function withFlag(fn: () => Promise<void>) {
  const [before] = await sql(`select enabled from public.feature_settings`);
  await sql(`update public.feature_settings set enabled = true`);
  try {
    await fn();
  } finally {
    await sql(`update public.feature_settings set enabled = ${before.enabled}`);
  }
}
```

## Gotchas
- **Symptom:** a later database test counts zero rows, or a sweep test fails, but only on a local database that has run the HTTP tests.
  **Cause:** HTTP level tests commit their rows, so the database is not empty for the next test. (Recorded once in the project.)
  **Fix:** scope the database assertions to their own fixtures and loop sweeps until empty (see [pgtap-database-testing](../pgtap-database-testing/SKILL.md), rules 11 and 12). Reset the local database before a trusted full run.
- **Symptom:** a race test passes every time even though a bug exists.
  **Cause:** the requests ran one after another, so the lock was never contended.
  **Fix:** build the requests first, then start them together with `Promise.all`. Check the response count matches the request count.
- **Symptom:** a limit test passes alone and fails in the full run.
  **Cause:** earlier tests used up the per address or per member limit, and the state was never reset.
  **Fix:** call the limit reset helper at the start of the limit test. Use SQL to set up data that would otherwise go through the limited path.
- **Symptom:** a per address limit could be spoofed by a client-sent forwarding header (caught in review).
  **Cause:** the limit read a forwarding header the client can write. The review fix reads the platform's own connecting-address header, or the last entry the edge proxy appends, and keeps the database caps as the stated control.
  **Fix:** key per address limits on the platform's header, and keep a per member database cap as the hard limit.
- **Symptom:** a concurrent action returns a 409 and the test counts it as a failure.
  **Cause:** the function answers "busy, retry" when a lock is held, which is a correct answer.
  **Fix:** treat that code as clean in race tests, and retry it once with the same idempotency key in the client. A test should assert the code, not only "not 200".
- **Symptom:** a purge test would have run against a hosted project (caught in review, not in a run).
  **Cause:** the test helper took its URL from an environment variable, and nothing checked it.
  **Fix:** the `assertLocal` guard at module load, as above. Keep it in the shared helper so each new test file gets it.

## Checklist
- [ ] Every action has a test for success and for each error code it can return.
- [ ] A body-supplied id for another user is ignored or refused.
- [ ] Each limit has a test at the limit, one over, and after the window resets.
- [ ] Each race test uses `Promise.all` over real requests and asserts exactly one, or exactly the cap, succeeds.
- [ ] No race response is a 5xx.
- [ ] Every setting a test changes is restored from the value it read, in `finally`.
- [ ] The helper refuses non local hosts at load time, and any test that deletes or purges uses it.

## Tests that prove it
- Remove the `assertLocal` call in a scratch copy and confirm the purge test would target the given host. Restore the guard.
- Run the race test ten times in a row. A correct lock passes every time.
- Break a limit on purpose (raise the cap) and confirm the limit test fails.

## Related skills
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md) for the database rules these functions rely on.
- [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md) for where these tests run.
- [independent-review-before-deploy](../independent-review-before-deploy/SKILL.md) for review of functions that auto deploy.
