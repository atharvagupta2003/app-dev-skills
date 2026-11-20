---
name: jest-react-native-testing
description: Unit and component tests for an Expo and React Native app with Jest, jest-expo and React Native Testing Library. Covers mocking native modules in one setup file, testing screen states as explicit state machines, copy tests that ban characters and promises, leaked timers and query cache garbage collection timers that keep Jest from exiting (a defaults wrapper for test clients, and how to bisect to the leaking suite), accessibility helpers, and pinning existing behaviour before changing shared code. Load when writing or fixing a component test, a copy test, or when Jest will not exit.
---

# Jest and React Native Testing Library

## When to use this
- Writing a test for a screen, component, hook or copy string.
- Adding a native module, or a test that needs one mocked.
- Jest hangs, or prints "did not exit one second after the test run".
- Changing a shared component, hook or navigation handler that many screens use.

## Rules
1. **Mock native modules once, in the setup file, not in each test.** Haptics, fonts, safe area, storage, network info and maps go in the setup file. A test mocks only what it needs for its own case.
   Why: a native module with no JavaScript implementation crashes every suite that imports it. One shared mock keeps the suites consistent.
2. **Test a screen by the states it can be in, one test per state.** Write the states as a list (for example waiting, linked, frozen, closed), render each with a mocked data hook, and assert what the screen shows and which actions it offers.
   Why: a screen with several states hides bugs in the transitions. A test per state catches a screen that shows the wrong state after a change.
3. **Find elements by `testID` or by an accessible label, not by layout.** Give every control a `testID` and an `accessibilityLabel`.
   Why: layout changes break position-based tests, and a label is what a screen reader and an end to end flow both use.
4. **Write copy tests that ban what must never ship.** Check every user-facing string for banned characters (dashes, emoji), banned words, percent style scores, digits where they are not allowed, and phrases that promise features that are not built.
   Why: copy is reviewed by a person once. A test keeps the ban in force for every later edit, across every screen.
5. **Make every test clean up after itself, then clear the caches it made, and wrap the cache's defaults so no query can opt out.** Use one `afterEach` that unmounts rendered trees first, then clears the test query clients. Each client's default query and mutation options are wrapped to force `retry: false` and `gcTime: Infinity`.
   Why: unmounting after a cache is cleared schedules garbage collection timers on queries no cache holds any more, so the order matters. A clear alone is not enough. A fetch still in flight schedules its own timer after the clear, and a query's own `gcTime` beats a client default. One query asked for 110 minutes, and that timer kept a CI run alive. The mechanism is in [react-query-in-react-native](../react-query-in-react-native/SKILL.md).
6. **Never call a force exit to finish a run.** Find the suite or the timer that keeps the process alive, and fix it.
   Why: a force exit hides a real leak. CI runs without it, so a leak fails the build.
7. **Before changing shared code, pin what it does now with a test.** Write tests for the current behaviour of the shared component, hook or handler, then make the change, then see which pinned behaviour moved.
   Why: a fix for one screen changed a global behaviour for every user in one project. Tests written after the change describe the new behaviour and miss the damage.
8. **Test that a hook's cleanup runs.** Unmount the hook and assert its timers and listeners are gone.
   Why: a timer left by a hook keeps the worker alive, and nothing else in the test fails.

## How to do it

The setup file pattern (the native mocks are the ones this project needed):

```ts
// jest.setup.ts
jest.mock('expo-haptics', () => ({
  selectionAsync: jest.fn(),
  impactAsync: jest.fn(),
  notificationAsync: jest.fn(),
  ImpactFeedbackStyle: { Light: 'light', Medium: 'medium', Heavy: 'heavy' },
}));
jest.mock('react-native-safe-area-context', () => require('react-native-safe-area-context/jest/mock').default);
jest.mock('@react-native-async-storage/async-storage', () => require('@react-native-async-storage/async-storage/jest/async-storage-mock'));
// A native map has no JavaScript implementation: render it as a plain view.
jest.mock('react-native-maps', () => {
  const { View } = jest.requireActual<typeof import('react-native')>('react-native');
  return { __esModule: true, default: View };
});
```

A second setup file (`setupFilesAfterEnv`) owns the cleanup:

```ts
import { setUpTests } from 'react-native-reanimated';
import { cleanup } from '@testing-library/react-native';
import { clearTestQueryClients } from '@/testing/queryClient';

setUpTests();

afterEach(async () => {
  await cleanup();          // unmount first, so observers leave before queries are cleared
  clearTestQueryClients();  // then clear every client the test made
});
```

A query client for tests whose queries never keep a garbage collection timer. The wrapper matters: a client default alone is overridden by any query that sets its own `gcTime` or `retry`.

```ts
// src/testing/queryClient.ts
// Sketch: check the overload types against your TanStack Query version with tsc.
import { QueryClient } from '@tanstack/react-query';

const made = new Set<QueryClient>();

// Every query and mutation gets retry false and gcTime Infinity, whatever it asks for.
// A gcTime of 0 is kept, because it asks for collection at once.
const forced = (gcTime: number | undefined) => (gcTime === 0 ? 0 : Infinity);

export function applyTestDefaults(qc: QueryClient): QueryClient {
  const baseQuery = qc.defaultQueryOptions.bind(qc);
  const baseMutation = qc.defaultMutationOptions.bind(qc);
  qc.defaultQueryOptions = (options) => {
    const o = baseQuery(options);
    return { ...o, retry: false, gcTime: forced(o.gcTime) };
  };
  qc.defaultMutationOptions = (options) => {
    const o = baseMutation(options);
    return { ...o, retry: false, gcTime: forced(o.gcTime) };
  };
  return qc;
}

export function testQueryClient(): QueryClient {
  const qc = applyTestDefaults(new QueryClient());
  made.add(qc);
  return qc;
}

export function clearTestQueryClients(): void {
  for (const qc of made) qc.clear();
  made.clear();
}
```

The app's shared client is a module singleton. When a test file imports it, wrap it once in that file's setup, so its queries get the same forced defaults:

```ts
import { queryClient } from '@/lib/queryClient';
import { applyTestDefaults } from '@/testing/queryClient';

applyTestDefaults(queryClient);
```

In the same `afterEach`, clear the singleton too, after `cleanup()`, with `queryClient.clear()`.

A state test, with the data hook mocked and reset between cases:

```tsx
let mockState: 'waiting' | 'linked' | 'frozen' | 'closed' | undefined;
jest.mock('@/space/useSpace', () => ({
  useSpace: () => ({ data: mockState ? { state: mockState, me: { first_name: 'Test' } } : undefined }),
}));

beforeEach(() => { mockState = undefined; });

it.each([
  ['waiting', 'space-invite-code'],
  ['linked', 'space-actions'],
  ['frozen', 'space-paused-notice'],
])('shows the %s state', (state, marker) => {
  mockState = state as typeof mockState;
  render(<SpaceScreen />);
  expect(screen.getByTestId(marker)).toBeOnTheScreen();
});
```

A copy test that reads every string and checks the rules:

```ts
const FORBIDDEN = /\b(lorem|ipsum|placeholder)\b/i;   // your own banned words go here
const DASH = /[‐-―−-]/;   // hyphen, dash family, minus
const EMOJI = /\p{Extended_Pictographic}/u;

it('has no dashes, forbidden words or emoji', () => {
  for (const s of allUserStrings()) {
    expect(s).not.toMatch(DASH);
    expect(s).not.toMatch(FORBIDDEN);
    expect(s).not.toMatch(EMOJI);
  }
});
```

Pass a rule that needs the files themselves (for example a legal page must not state a retention period) by reading the files from disk with `fs` and checking the text.

Accessibility helper: fail when a control has no name, or a switch has no checked state:

```ts
export function expectAccessibleControls(): void {
  const controls = findAllHosts(screen).filter(
    (n) => typeof n.props.onClick === 'function' || TAPPABLE_ROLES.has(String(n.props.accessibilityRole)),
  );
  const unnamed = controls.filter((n) => !String(n.props.accessibilityLabel ?? '').trim());
  if (unnamed.length) throw new Error(`Controls without an accessible name: ${unnamed.map((n) => n.props.testID).join(', ')}`);
}
```

Bisecting a hang. Run each suite on its own with a timeout. A suite that does not exit within the limit owns the timer:

```bash
for f in $(find src -name '*.test.ts*'); do
  timeout 60 npx jest --ci "$f" >/dev/null 2>&1 || echo "NOT CLEAN: $f"
done
```

Then open the flagged file and look for `setTimeout`, `setInterval`, a query client that was not made with `testQueryClient`, a listener that is not removed, or an animation that is not cancelled on unmount.

A leak that only shows in CI can pass this loop. CI runs Jest in band on a 2 core runner, so one long timer keeps the whole run alive. Locally, the workers are killed at the end and the timer is hidden. Reproduce it with an in band run (for example `npx jest --ci --runInBand`) on a 2 core Linux container with the CI Node version. To find the timer, use a temporary census: wrap `setTimeout` in a setup file, log every timer of a minute or more with its stack, and remove the wrapper when done. Do not commit the census.

## Gotchas
- **Symptom:** Jest prints "Jest did not exit one second after the test run has completed" and the CI step hangs, while local runs pass.
  **Cause:** a query client's garbage collection timer, or a timer in a helper that was never cleared. A `gcTime: Infinity` on the client is not enough, because a query's own `gcTime` wins, and a fetch still in flight at cleanup schedules its timer after the clear.
  **Fix:** the defaults wrapper above on every test client and on the app's shared client in tests, the clear in `afterEach`, and a clear of the helper timer. Then give the CI test step its own timeout (see [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md)).
- **Symptom:** "worker failed to exit" or "did not exit" appears in some full runs and not others.
  **Cause:** the warning depends on which test file a worker runs last. A test that leaves a retry or a timer alive is harmless until it is last in its worker. In one project a data hook's retry timers did this, and the warning appeared in 4 of 8 full runs.
  **Fix:** find the timer as above. Run the full suite several times to see the warning rate, because one clean run proves little. See [react-query-in-react-native](../react-query-in-react-native/SKILL.md) for the retry case.
- **Symptom:** a Pressable renders blank, with no error and no warning.
  **Cause:** a function style (`style={({ pressed }) => ...}`) on `Pressable` silently drops the style and its children in this Expo and NativeWind setup.
  **Fix:** use an array style, or a touchable with explicit feedback. Test that the children render.
- **Symptom:** a test that finds a label by text fails even though the text is on screen.
  **Cause:** the touchable's accessibility role hides its child text from the test tree.
  **Fix:** put the label on the touchable itself, and use `accessible={false}` on wrappers that are only for layout.
- **Symptom:** a test passes alone and fails in the full run.
  **Cause:** a previous test left a mocked value, a store or a cache. The setup file does not reset a Zustand store or a mocked hook.
  **Fix:** reset stores and mock variables in `beforeEach`, as the state test above does.
- **Symptom:** a change to a shared handler broke a screen that was not touched.
  **Cause:** the handler is global, so one screen's fix changed every screen's behaviour.
  **Fix:** pin the current behaviour in tests first (rule 7), and scope a new behaviour to its screen.

## Checklist
- [ ] Native modules are mocked in the setup file, not in each test.
- [ ] Every screen state has its own case.
- [ ] Every control has a `testID` and an accessible label, and the accessibility helper passes.
- [ ] Copy tests run over every user string, and the forbidden list is current.
- [ ] `afterEach` unmounts first, then clears test query clients.
- [ ] Every test query client has its defaults wrapped, and the app's shared client is wrapped in tests that import it.
- [ ] Each suite exits on its own under a timeout, with no force exit, and the full suite exits in band.
- [ ] Shared code has pinned tests before any change.

## Tests that prove it
- Remove a hook's cleanup on purpose, and confirm its cleanup test fails.
- Add a dash to a copy string on purpose, and confirm the copy test fails.
- Run the full suite with `--ci` and no force flag, and confirm it exits by itself.
- A wrapper test: a query with its own 110 minute `gcTime` and `retry: 3` reads back `Infinity` and `false`, and `gcTime: 0` stays 0.
- A proof test for an exit leak: start a prefetch whose fetcher never resolves, let the test end, and run it in band. It must exit. Before the wrapper it reproduced the warning 3 of 3 times, and after it 0 of 5.

## Related skills
- [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md) for where Jest runs.
- [maestro-and-flow-tests](../maestro-and-flow-tests/SKILL.md) for the end to end checks that use the same labels.
- [independent-review-before-deploy](../independent-review-before-deploy/SKILL.md) for reviewing shared code changes.
