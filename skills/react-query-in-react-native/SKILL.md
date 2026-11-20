---
name: react-query-in-react-native
description: Use TanStack React Query in a React Native app. Covers a typed query key factory, a persisted per user cache and what to leave out, refetch on mount, wiring the online and focus managers to the device, invalidation after writes, setting data before navigation, and test client defaults wrapped so no query can keep a Jest run from exiting. Load when adding a query or mutation, persisting cache, or when Jest does not exit.
---

# React Query in React Native

## When to use this
- You add a query or mutation, or change a query key.
- You persist the query cache so a screen draws at launch.
- A screen shows stale data after a change, or refetches too often.
- `jest` finishes its tests and then hangs, or prints that it did not exit.

## Rules
1. **Build every key from one typed factory.** Each key is a function that returns an `as const` tuple, and a prefix function covers every key under one feature. Why: invalidation by prefix needs one place that knows the shape.
2. **Put anything that changes the data in the key.** A source switch, a plan, or the user id belongs in the key. Why: then a switch refetches, and one user's data never answers another user's query.
3. **Persist only a short allow list, per user.** Save what the first screen draws, filtered on write and on restore. Why: a full cache holds data the user may have lost access to.
4. **Keep the original read time on restored entries.** Why: the library then treats them as stale, and fetches them on mount, while still drawing them at once.
5. **Use `refetchOnMount: 'always'` on screens that must show the server's latest state.** Why: the default refetches on mount only when the data is stale, so a screen that must show the server's latest state asks on every mount (the sources use it on the screens where a change elsewhere must show at once).
6. **Wire the online and focus managers to the device once, at the root.** Why: without them the library cannot tell that the phone came back online or returned to the foreground.
7. **Invalidate by prefix after every write that changes a feature.** Why: one write often changes several screens.
8. **In tests, wrap the client defaults so every query and mutation gets `retry: false` and `gcTime: Infinity`, whatever it asks for. Clear every client after each test.** Why: a query's own `gcTime` or `retry` beats the client default, so a plain `gcTime: Infinity` on the client is not enough. One query asked for 110 minutes and kept Jest alive for that long. Clearing is not enough either, because a fetch still in flight schedules its own garbage collection timer after the clear. A retry also schedules timers (1 and 2 seconds in one project). See the wrapper in [jest-react-native-testing](../jest-react-native-testing/SKILL.md).

## How to do it

### 1. Key factory
```ts
export const queryKeys = {
  profile: (userId: string) => ['profile', userId] as const,
  feedAll: () => ['feed'] as const,                          // prefix for invalidation
  feed: (userId: string, source: 'live' | 'fixture') => ['feed', userId, source] as const,
  thread: (userId: string, threadId: string) => ['thread', userId, threadId] as const,
};
```

Invalidate with the prefix: `queryClient.invalidateQueries({ queryKey: queryKeys.feedAll() })`.

### 2. The device wiring
```ts
import { AppState } from 'react-native';
import NetInfo from '@react-native-community/netinfo';
import { focusManager, onlineManager, QueryClient } from '@tanstack/react-query';

export const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 30_000 } } });

onlineManager.setEventListener((setOnline) => NetInfo.addEventListener((s) => setOnline(!!s.isConnected)));
focusManager.setEventListener((handleFocus) => {
  const sub = AppState.addEventListener('change', (s) => handleFocus(s === 'active'));
  return () => sub.remove();
});
```

### 3. The persisted cache
Subscribe to the cache. On a successful update for an allowed key, schedule one write for the signed in user, debounced by about a second. On launch, read the user's entries and call `setQueryData(key, data, { updatedAt: savedAt })`. Skip any key that already has data. See `expo-app-start-performance` for the full pattern and what to clear on sign out.

### 4. Set data before navigating
When a write returns the new state, write it into the cache first, then navigate. The destination then draws the new value on its first frame instead of the old one. The rule is about ordering; the sources do not show a separate case where this was needed.

### 5. Invalidate after a write
```ts
await api.updateProfile(input);
void queryClient.invalidateQueries({ queryKey: queryKeys.profile(userId) });
```

Invalidate the smallest prefix that covers what changed. Use the feature's `All` prefix only when several keys change.

## Gotchas
- **Jest does not exit after the tests pass, only in CI.** Cause: a fetch was still in flight when the test's clients were cleared. The clear cancels the fetch, but the fetch's cleanup then schedules a garbage collection timer on a query that no cache holds. The timer runs for the query's own `gcTime`: the five minute default, or 110 minutes for one cached value. A client default of `gcTime: Infinity` does not stop it, because the query's own option wins. Why only in CI: the CI runner has 2 cores, so Jest runs in band in one process, and one long timer keeps the whole run alive. Locally, several workers are killed at the end, so the timer is hidden. Fix: the defaults wrapper in the Jest skill, which sets `gcTime: Infinity` and `retry: false` on every query and mutation (a `gcTime` of 0 stays 0). Verified in CI.
- **A leak that per file runs do not show.** Running each file alone under a timeout (for example `timeout 60 npx jest path/to/file`) did not reproduce the CI only exit in this project. Use an in band run, on a 2 core Linux container with the CI Node version if you can. Then use a timer census: log every timer of a minute or more with its stack, and remove the census when done. In older CI logs, a delayed exit came exactly 300 seconds after one file, which pointed at the 5 minute default. Per file runs still help for hangs that do reproduce alone.
- **A test that makes its own client is not covered.** It skips the shared helper and brings the leak back. Use the helper everywhere, including the app's shared client when a test imports it.
- **"Worker failed to exit" appears in some runs only.** Cause: a data hook retried a deliberately failing request after 1 and 2 seconds. The retry timers outlived the test, so the warning showed only when that test finished last in its worker (4 of 8 full runs before the fix). Fix: the defaults wrapper forces `retry: false` and `gcTime: Infinity` (zero stays zero), regardless of hook options. A default on the client is not enough if a hook sets its own `retry`, so check the forced value with a test that renders a hook with its own retry and a failing request, and counts the calls. After the fix, 0 of 10 full runs showed the warning. See [honest-status-reporting](../honest-status-reporting/SKILL.md) for why 10 runs were needed.
- **A four second race timer in a push unregister call was not cleared.** It kept Jest alive even after the query leak was fixed. Clear every timer you start, in the function that started it.

## Checklist
- [ ] Every key comes from the factory, with user id and source where the data depends on them.
- [ ] Every write invalidates the prefix it changes.
- [ ] The persisted list is short, per user, and cleared on sign out and user switch.
- [ ] Online and focus managers are wired once, at the root.
- [ ] Each test client is made by the shared helper, with its defaults wrapped, and cleared after each test.
- [ ] The app's shared client is wrapped too, in tests that import it.
- [ ] Each test file exits on its own under a timeout, and the full suite exits in band as CI runs it.

## Tests that prove it
- A test of the key factory that each prefix matches its full keys.
- A test that a write invalidates the prefix and that the screen refetches.
- A test that a restored entry keeps its read time and is refetched on mount.
- A test that a signed link is never saved, and that a user switch leaves no entries behind.
- A wrapper test: a query that asks for a 110 minute `gcTime` and `retry: 3` gets `Infinity` and `false`, and a query that asks for `gcTime: 0` keeps 0.
- A proof test: start a prefetch whose fetcher never resolves, then let the test end. Run it in band with the CI Node version. Before the wrapper it reproduced the exit warning 3 of 3 times. After it, 0 of 5.
- A suite run with `--ci` that exits by itself, and a per file run under `timeout 60`.

## Related skills
- `expo-app-start-performance`: the launch order that uses the persisted copy.
- `offline-outbox-and-sync`: queued writes and how they merge with the server's answer.
- `media-upload-pipeline`: signed links and their cache.
