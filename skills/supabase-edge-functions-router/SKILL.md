---
name: supabase-edge-functions-router
description: How to structure Supabase Edge Functions so every request is authenticated, validated and mapped to a clean response. Covers one router per function with an action allow list, identity from the token only, per mode action lists that fail closed, mapping domain error codes to 4xx and lock conflicts to a retryable 409, database backed rate limits and the address spoofing trap, never calling a vendor API from the client, and local testing quirks. Load when adding or changing an Edge Function or its client calls.
---

# Supabase Edge Functions router

## When to use this
- You are adding an Edge Function, an action to an existing one, or a new error code.
- A function accepts any input that a client or an attacker could guess or repeat.
- A new user mode or feature flag must not reach an action by accident.
- A client sees a 500 for something that should be a clear refusal.

## Rules
1. **One router per function, one action per name.** The router does, in order: method check, verify the token, read the body, look up the action in a fixed table, check the member's state and mode, validate the input, call the action, map errors, and log one line. Actions never reimplement these steps. Several domains in one function is fine when they share the same auth and limits; split a function when a domain needs a different deploy or a different service.
2. **Take identity only from the verified token.** The user id comes from `auth.getUser()` on the bearer token. Any id in the body is ignored or refused. The client is never trusted to say who it is.
3. **Use a per-action allow list for each user mode.** An action that is not named in the list serves the default mode only. A new mode is refused everywhere until an action opts in. This is the fail closed default: forgetting an action leaves it closed, not open.
4. **Map every domain error to a clean 4xx, and treat an unknown code as a bug.** Domain rules raise a named error code inside the database. The router keeps a set of known codes, returns 422 for them, and returns 409 for conflicts. An unlisted code becomes a 500, which shows up in logs as a bug. Add the code to the set in the same change that raises it.
5. **Return a retryable 409 for lock conflicts.** A deadlock or a lock timeout from Postgres becomes `409 busy_retry`. The client resends the same request with the same idempotency key. (See [postgres-concurrency-and-limits](../postgres-concurrency-and-limits/SKILL.md).)
6. **Do not turn an auth outage into a 401.** If the auth service cannot answer (a timeout, a 429, a 5xx), return a 500 the app retries. A 401 makes the app ask whether the account still exists and sign the member out.
7. **Store rate limits in the database for anything a client can guess or repeat.** Sign-in codes, invite codes, exports and message sends need a count that survives a restart and a second instance. In-memory counters only stop loops from one warm instance.
8. **Never trust the first address in `x-forwarded-for`.** A client can send that header with any first value. The platform appends the address it saw at the end. Read `cf-connecting-ip` when the platform sets it, else the last `x-forwarded-for` entry, and treat a per-address limit as a second control behind the per-member limit in the database.
9. **Never call a third party API from the client.** The app calls one of your Edge Functions. The function holds the vendor key, checks the member's allowance, and calls the vendor. The key never ships in the app.
10. **Let suspended members reach only the actions that protect them.** Deleting the account, exporting data and appealing a decision stay available. Everything else answers 403 with the reason.

## How to do it
A router is built from one shared handler and one table of actions. Each action has a schema and a run function.

```ts
// notes/index.ts
import { createRouter } from '../_shared/handler.ts';
import { z } from 'zod';

const actions = {
  add_note: {
    schema: z.object({ spaceId: z.string().uuid(), body: z.string().min(1).max(500) }),
    run: async (ctx, input) => {
      const { data, error } = await ctx.admin.rpc('add_space_note', {
        p_space: input.spaceId, p_body: input.body, p_key: ctx.requestId,
      });
      if (error) throw error; // the router maps the SQL code
      return data;
    },
  },
};

Deno.serve(createRouter('notes', actions, {
  allowSuspended: [], // only the deletion and export actions go here
  modes: { add_note: ['personal', 'shared'] }, // an absent name means default mode only
}));
```

The router, in outline:

```ts
const body = await req.json();
const def = Object.hasOwn(actions, body.action) ? actions[body.action] : null;
if (!def) return fail(400, 'unknown_action');
const input = def.schema.parse(rest);            // invalid input: 400, field paths only
const data = await def.run({ userId, admin, requestId }, input);
return json(200, { ok: true, data });
```

`Object.hasOwn` matters: a plain lookup on an object finds `toString` and `constructor` too.

Set `verify_jwt` deliberately in the function config, and keep the auth check in the router as well, so a misconfigured gateway still fails closed.

## Gotchas
- **Symptom:** a new domain error shows the app a generic "something went wrong". **Cause:** the code was raised in SQL but not added to the router's known set, so it became a 500. **Fix:** add it to the set in the same change, and add a test that calls the action and expects 422 with that code.
- **Symptom:** a member is signed out after a short outage. **Cause:** the auth check returned 401 for a timeout. **Fix:** a timeout, 429 or 5xx from auth is a 500 the client retries.
- **Symptom:** a rate limit on sign-in codes is bypassed by changing a header. **Cause:** the limit read the first `x-forwarded-for` entry, which the client controls. **Fix:** read the platform's address and keep the database limit per member as the stated control.
- **Symptom:** a new mode suddenly reaches an action it should not. **Cause:** the action had no mode list and the default was too wide. **Fix:** the default is the default mode only, and a test calls each action in each mode.
- **Symptom:** the first function test run right after the local function server reloaded failed once, and the rerun passed. This happened several times. **Cause:** not established. (Hypothesis, unconfirmed: the function's isolate restarts while the client holds a connection.) **Fix:** rerun once from a clean start, and check the function logs. If it fails again, treat it as real.
- **Symptom:** the app holds a vendor key. **Cause:** a client call went straight to the vendor. **Fix:** move the call behind an Edge Function that reads the key from its environment.

## Checklist
- [ ] The action is in the table with a schema, and the schema rejects unknown fields.
- [ ] The user id comes from the token, never from the body.
- [ ] Modes are listed for each action that serves more than the default.
- [ ] Every new domain code is in the router's known set, and mapped to 422 or 409.
- [ ] Lock conflicts return `409 busy_retry`.
- [ ] Auth failures that are not a verdict on the token return 500.
- [ ] Guessable actions have a database rate limit.
- [ ] No vendor key or vendor call is in the client.

## Tests that prove it
- Every action over HTTP: no token (401), a bad body (400 with field paths only), an unknown action (400), a suspended member (403) and the happy path.
- Every domain code raised in SQL has a test that expects its mapped status. A code missing from the set fails the test.
- A mode test: each action is called in each mode, and an action not listed refuses with the mode code.
- An identity test: a body that names another user id still acts as the token's user.
- Full examples of the harness are in [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md).

## Related skills
- [supabase-rls-and-function-access](../supabase-rls-and-function-access/SKILL.md): what the function's database calls may do.
- [postgres-concurrency-and-limits](../postgres-concurrency-and-limits/SKILL.md): idempotency keys and busy responses.
- [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md): testing the router over HTTP.
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md): how a mode or feature is switched on for some members first.
