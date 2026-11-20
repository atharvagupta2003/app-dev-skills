---
name: expo-router-route-gate
description: Build a fail closed route gate for an Expo Router app, driven by the signed in user's place or mode. Covers classifying route segments, a test that reads every navigation target from the source and checks it against the gate, resetting the stack after flows, safe Back with no history, avoiding redirect loops, and step counters that count only the steps shown. Load when adding a top level route, adding a second mode or place for users, or when Back or redirects behave oddly on a device.
---

# Expo Router route gate

## When to use this
- The app has more than one kind of signed in user (for example, setup, a main mode and a second mode) and each sees different screens.
- You add a top level route or a new `navigate`, `push` or `href` call.
- Hardware Back walks back into a finished flow, or Back does nothing after a deep link.
- A redirect sends a user to a screen that sends them back again.

## Rules
1. **Put every route in exactly one class.** Public, dev only, onboarding, signed in only, each place's routes, routes both places share, and unknown. Why: a route nobody classified is either sent home for everyone or open to everyone.
2. **Fail closed.** An unknown segment goes to the safe place (home or sign in). Why: a missed route should show as a redirect in the test, not as a screen a user should not see.
3. **Test every navigation target against the gate.** Read the targets out of the source files and ask the real gate, for the place each file is meant for. Why: a segment missing from the gate made a whole feature unreachable on a device while unit tests of the screen passed.
4. **Never redirect while loading.** Wait for the auth state and the user's place before deciding. Why: a redirect on an unknown place sends a user to the wrong home for a moment, and that flicker looks like data loss.
5. **Use replace for moves between places, and push only for drill downs.** Why: a stack that keeps every step of a finished flow lets Back walk through screens the user should not revisit.
9. **After a finished flow or a sign in, dismiss the whole stack, then replace.** Use the reset helper in "How to do it". Why: without it, hardware Back after sign in was swallowed for several presses.
6. **Give Back a target when there is no history.** A deep link, a notification or a restored process has nothing to go back to. Why: without a target Back does nothing, or leaves the app.
7. **Do not change Back for other groups.** A special Back rule applies only to the group it was written for, and every other group keeps the system default. Why: a Back rule that applies to everyone changes behaviour that already works for the other groups.
8. **A closed state screen must not send Back to the screen that redirects to it.** Why: the closed screen redirects to home, home redirects to the closed screen, and Back loops between them.
10. **Derive an onboarding resume point from the answers, not from a stored step index.** Find the first step on the member's path that has no answer. Why: a path choice moved earlier, so the order changed under a saved index, and a member with an old saved position could resume in the wrong place.
11. **Keep the old order's keys readable, and let every saved position resolve.** Map each old key to a current step explicitly, and fall back to the derived resume point for anything unknown. Why: a saved position from before the reorder must still land somewhere sensible. Unknown keys fail closed, as in rule 2.
12. **Save an onboarding step only on its explicit action, such as Continue.** Never save a default when the step is shown. Why: a step that saved its default on arrival recorded answers the member never gave.
13. **Make the server refuse completion when an answer is missing on the path that needs it.** A question that became optional on one path is still required when that path needs it. Why: the client's order is not the only check. See [supabase-rls-and-function-access](../supabase-rls-and-function-access/SKILL.md), rule 9, for the no-else rule on the server.
14. **Count progress over the steps the member will be shown, given current answers.** Why: a total that counted steps shown only sometimes made the last step read "3 of 4". (Proposed from one project's notes. Not yet verified by a fix there.)
15. **Mark a step as passed over only when the navigation function passes over it in this session.** Do not infer "skipped" from "answered and not shown". Why: a label that inferred skipped steps from saved answers read "2 of 4" in a normal run and "1 of 3" for the same step after a relaunch.

## How to do it

### 1. Classify segments
```ts
export type SegmentKind = 'public' | 'dev' | 'onboarding' | 'signed_in' | 'member' | 'shared' | 'either';

export function classifySegment(segment: string): SegmentKind | null {
  if (PUBLIC.includes(segment)) return 'public';        // welcome, sign-in, verify
  if (DEV.includes(segment)) return 'dev';              // only in development builds
  if (ONBOARDING.includes(segment)) return 'onboarding';
  if (SIGNED_IN.includes(segment)) return 'signed_in';  // support, terms
  if (MEMBER.includes(segment)) return 'member';        // the first mode's tabs and screens
  if (SHARED_SPACE.includes(segment)) return 'shared';  // the second mode's folder
  if (EITHER.includes(segment)) return 'either';        // settings, account deletion, store
  return null;                                          // unknown: the gate sends it home
}
```

Put the group folder name (for example `(tabs)`) in the list too, since the first segment can be the group.

### 2. One pure decision function
```ts
export function routeFor({ segment, authStatus, place }: GateInput, dev = __DEV__): string | null {
  if (authStatus === 'loading') return null;
  const kind = segment === null ? null : classifySegment(segment);
  if (authStatus === 'out') return kind === 'public' || (dev && kind === 'dev') ? null : '/welcome';
  if (segment === null) return place === null ? null : homeFor(place);
  if (kind === 'public') return '/';
  if (place === null) return null;
  if (kind === 'dev' || kind === 'signed_in') return null;
  switch (place) {
    case 'onboarding': return kind === 'onboarding' ? null : '/onboarding';
    case 'primary':    return kind === 'member' || kind === 'either' || kind === 'onboarding' ? null : '/home';
    case 'shared':     return kind === 'shared' || kind === 'either' ? null : '/shared';
  }
}
```

Keep the function pure. Pass the place in from the stored user data, never read it from the screen.

### 3. The navigation target test
Walk the screen files, pull out every string literal given to `push`, `replace`, `navigate`, `resetTo` and every `href`, and check each static path against `routeFor` for the place the file serves.

```ts
const CALL = /\b(?:push|replace|navigate|resetTo)\(\s*(['"`])((?:\\.|(?!\1)[^\\])*)\1/g;

const staticPath = (literal: string) => literal.split('${')[0]!.split('?')[0]!;

it('finds a real set of targets', () => {
  expect(collect(dirFiles('shared')).length).toBeGreaterThan(30); // an empty extraction passes silently
});

it('every target in shared screens is allowed for the shared place', () => {
  for (const t of collect(dirFiles('shared'))) {
    expect({ ...t, ok: allowed(t.path, 'shared') }).toEqual({ ...t, ok: true });
  }
});

it('every top level route is classified', () => {
  for (const name of routeFileNames()) expect(classifySegment(name)).not.toBeNull();
});
```

The three guards matter. The first stops a broken regex from making the test pass with nothing checked. The second is the one that catches a new route. The third catches a new file in the route folder.

### 4. Reset after a finished flow
Dismiss the whole stack, then replace with the destination. Use it after a flow ends and after sign in. Fall back to a plain replace when there is nothing to dismiss.

```ts
import { useRouter, type Href } from 'expo-router';

export function useResetTo() {
  const router = useRouter();
  return (path: Href) => {
    if (router.canDismiss()) router.dismissAll();
    router.replace(path);
  };
}
```

## Gotchas
- **A missing route segment made a whole feature unreachable.** The segment was missing from the gate's allow list, so on a device the feature's entry sent the user home. Every unit test passed, because they exercised the button and the screen separately. Cause: the classification list is separate from the file system and from the navigation calls. Fix: the navigation target test, which reads each `push`, `replace` and `href` from the source and checks it against the gate, plus the classification test, which fails on a new file.
- **Template paths are only checked by their static part.** `/item/${id}` is checked as `/item`. Dynamic children are not checked beyond their first segment. This is a known limit, not a fixed one.
- **The test reads source text.** It finds a call written as `push('/x')`, but not a path built in a variable. Keep navigation literals in the screen, or add the variable's values to the test.
- **Back loops between home and a closed-state screen.** A home screen and a "closed" state screen redirected to each other on Back, until the closed screen was excluded from the Back handler. Cause: Back with history returned to the redirecting screen, and the gate sent the user there again. Fix: exclude the closed screen from the handler, so it keeps the system Back.
- **A global Back handler changed Back for every user.** A handler added for one group made home tabs stop leaving the app, for every user. An independent review caught it before release. Cause: the handler was not limited to its group. Fix: the handler returns false (system default) for every other group and for any screen in the keep list. Pin the original behaviour with tests before you change a shared handler.
- **Saved onboarding positions landed in the wrong step after a reorder.** The path choice moved earlier, so one path could skip questions. Cause: the saved resume position was a stored index, and the step order changed under it. Fix: derive the resume point from the answers, map the old order's keys explicitly, and test a saved position from each old order (rules 10 and 11).
- **Onboarding recorded answers the member never gave.** A step saved its default on arrival. Cause: the save ran when the step was shown, not when the member pressed Continue. Fix: save only on the explicit action (rule 12). A test should check that a step shown and left without Continue writes nothing.
- **A font size change restarts the activity on Android.** The JavaScript side stays alive, but the screens remount from the root, and the root would send the user home. Fix: remember the last path in memory for the same user and home, and restore it once. A cold start has no memory and goes home.
- **A step counter read a different total after a relaunch.** The same step read "2 of 4" in a normal run and "1 of 3" after a relaunch. Cause: "skipped" was inferred from saved answers (answered, not shown this session), so a relaunch changed the count. Fix: rule 15. The label counts only the steps that the navigation function passed over this session, and the total follows rule 14.
- **A total counted steps that are only sometimes shown.** The last step read "3 of 4". Cause: the total included a conditional step that this member's answers hid. Fix (proposed, not yet verified): count only the steps that will be shown given current answers (rule 14). A test should set answers that hide a step, and check that the last step reads its own total.

## Checklist
- [ ] Every top level file under `app/` has a class.
- [ ] Each new `push`, `replace`, `navigate` and `href` was added to the test's sources.
- [ ] The gate fails closed: unknown means home, not open.
- [ ] No redirect happens while auth or place is loading.
- [ ] Finished flows use `replace`, so Back does not return into them.
- [ ] Every screen reached by a deep link has a Back fallback.
- [ ] The closed-state screen keeps system Back and does not bounce.
- [ ] Back behaviour is checked for each group on a device.
- [ ] Step counters count only steps shown given current answers, and a relaunch shows the same counts.

## Tests that prove it
- The navigation target test above, for every place, plus the classification test.
- A table test of `routeFor` with one row per (auth, place, segment) combination that matters, including `loading` and `null`.
- A test that an unknown segment is sent home for a signed in user and to sign in for a signed out one.
- A test for the Back helper: with history it calls back; with no history it replaces with the fallback.
- A test that the hardware Back handler returns false for every group it does not own.
- For step counters: a table test of the label for each answer set, including one that hides a conditional step, and one that shows the step again after a relaunch with the same answers. Both must read the same.
- For onboarding: a table test of the resume point for each saved position, including one from each old order, and a server test that refuses completion when an answer is missing on the path that needs it.

## Related skills
- `expo-app-start-performance`: the first screen decision is made after the start reads.
- `expo-local-android-builds`: check Back and redirects on a release build, not only in development.
