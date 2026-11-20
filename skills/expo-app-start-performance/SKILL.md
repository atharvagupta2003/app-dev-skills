---
name: expo-app-start-performance
description: Measure and speed up the cold start of an Expo or React Native app. Covers in app timing markers in the native log, showing saved data first and refreshing after, per user saved copies, parallel start requests, bounded waits, deferred work, and what to clear from the saved copy. Load when a launch feels slow, when adding a splash or a first screen, or when persisting data for the first paint.
---

# Expo app start performance

## When to use this
- The first screen waits on the network before it shows anything.
- You are adding a splash, a loading gate, or a first screen that reads several endpoints.
- You want a number for cold start on a real device, not a guess.
- You are saving data on the device so the home screen can draw before the server answers.

## Rules
1. **Measure with markers in the app, read them from the native log.** Log a stage name and milliseconds since the bundle started. Why: a screen recording shows when pixels changed, not when the content became usable.
2. **Turn the markers off in production builds.** Gate them on the app environment, and log nothing but a fixed tag, a stage name and a number. Why: a log line with an id, a name or a location is personal data in a log that others can read.
3. **Show saved data first, then refresh.** Draw the last known copy at once and let the normal fetch replace it. Why: the user sees content in the first frames, and the server stays the source of truth.
4. **Keep each saved entry's original read time.** Why: the query library then still treats the entry as stale and fetches it on mount. Stamping it with "now" hides old data as fresh.
5. **Save per user, and clear it with the user.** Key the copy by user id. Remove it on sign out, on a user switch and when a shared space ends. Why: a second person on the same device must never see the first person's home screen.
6. **Never save short lived signed links.** Why: a signed link that is saved and restored after it expires gives a broken image, and a link to a private file may outlive the access that allowed it.
7. **Start independent reads together.** Begin the server read, the local reads and the first screens' reads in the same tick. Why: waiting for one before starting the next adds the round trips up.
8. **Bound every wait.** Race the server read against a timer. Past the timer, use the local copy and apply the server answer when it arrives. Why: a slow network must not hold the splash.
9. **Shorten the wait for users who already finished setup.** They have a good local copy. Why: the long wait protects a first run, which needs the server's view.
10. **Move non essential work after the first paint.** Overlays, background helpers and rarely used modules come after the first content. Why: every module evaluated before the first frame delays it.

## How to do it

### 1. Timing markers
Put the timestamp in the first module the entry file imports, and let that module import nothing. An import that runs first would take the timestamp late.

```ts
// startup-timing.ts (the first import of index.ts)
const JS_START = Date.now();
export type Stage = 'js_start' | 'local_ready' | 'first_render' | 'server_ready';

function enabled(): boolean {
  const env = process.env.EXPO_PUBLIC_APP_ENV;
  if (env === 'development' || env === 'preview') return true;
  if (env === 'production') return false;
  return __DEV__;
}

const seen = new Set<Stage>();
export function markStage(stage: Stage): void {
  if (!enabled() || seen.has(stage)) return;
  seen.add(stage);
  console.log('APP_STAGE', JSON.stringify({ stage, ms: Date.now() - JS_START }));
}
```

Read them on a device with `adb logcat -s ReactNativeJS:I | grep APP_STAGE`. Log the first content screen once, with a flag that says whether it drew from the saved copy. That flag tells you whether the saved copy is doing its job.

### 2. Stages worth marking
- `js_start`: the bundle began to run.
- `local_ready`: saved copies and stores are loaded.
- `first_render`: the first content screen mounted.
- `server_ready`: the server's view of the user arrived.
- `first content`: one line with `ms`, `screen` and `cached`.

### 3. Saved copy of the home reads
Keep a small allow list of query keys that may be saved. Filter on write and on restore. Write after a successful update, debounced by about a second, so a burst of updates costs one write.

```ts
export function shouldPersist(key: QueryKey): boolean {
  const [head] = key;
  if (head === 'stack') return key[3] === 'live';
  if (head === 'signed-url') return key[2] !== 'private-album'; // short lived links never
  return false;
}
```

Restore with `setQueryData(key, data, { updatedAt: savedAt })`. Skip a key if the cache already has data for it. Skip a signed link older than the time it is valid for. Wrap every read and write in try and catch: a damaged copy is just no copy.

### 4. Parallel start
```ts
const serverRead = queryClient.fetchQuery({ queryKey, queryFn: getOnboardingState, staleTime: 0 });
serverRead.catch(() => undefined); // a failure is handled where it is awaited
await Promise.all([stores.rehydrate(), outbox.rehydrate(), hydrateQueryCache(queryClient, userId)]);
markStage('local_ready');
```

Once the user's place is known, start the first screens' reads with `prefetchQuery`, without awaiting them. The screens ask again themselves if a prefetch fails.

### 5. Bounded wait
```ts
const late = new Promise<'late'>((resolve) => setTimeout(() => resolve('late'), waitMs));
const first = await Promise.race([serverRead, late]);
if (first === 'late') {
  void serverRead.then(applyLateAnswer).catch(() => undefined);
}
```

Clear the timer when the server wins. A timer left running keeps Jest from exiting, see `react-query-in-react-native`.

### 6. Measured results
Measured on an emulator with the markers above, on a release build. The server was far from the tester, about half a second per round trip.
- Screenshot timing was unreliable. The same app on the same emulator measured 7, 10 to 13 and 20 seconds across three tests. Polling overhead and an overloaded emulator caused the spread.
- The first render came about 0.45 s after the JavaScript started. First content came at 4.4 to 4.9 s, for a home screen that waited on two sequential server round trips.
- Saving that screen's data per user, and drawing it at once, brought first content to 0.28 s. The server refresh arrived 2.5 to 3 s later, in the background.
- The first launch after install still took 2.9 s, because nothing was saved yet.
- A home screen that kept a deliberate short wait for the server showed first content at 1.2 to 1.4 s.

## Gotchas
- **Two splash screens on a cold start.** The root layout drew one splash as a sibling of the navigator, and the index route drew a second. Each took half the height, so two figures stacked. Cause: two components each assumed they owned the whole screen. Fix: one absolute fill overlay in the root layout, and the index route only paints the background. A new JavaScript bundle was enough, no native rebuild.
- **Screenshot timing misleads.** Measured: the same app on the same emulator gave 7, 10 to 13 and 20 seconds across three tests. Cause: polling overhead and an overloaded emulator, not the app. Fix: read the `APP_STAGE` markers, and record the first three cold starts before and after each change.
- **Saved copy outlives the user.** A user switch that forgets to clear the copy shows the old user's home. Clear the previous user's memory first with persistence off, then set the new user. The launch code does this before any restore.
- **A space or account ends while the app is closed.** The saved copy still holds its data. Drop the saved entries on the next write, and also drop them at once when the end is known, so a relaunch cannot draw them.
- **Shimmer hides a blank photo.** A photo frame that draws nothing until its image loads looks broken. Show a quiet placeholder until the image's load event, and show the local file for a photo the user just took.

## Checklist
- [ ] Markers are off in production and log only a tag, a stage and a number.
- [ ] Each stage is logged once per launch.
- [ ] Saved entries keep their original read time.
- [ ] The saved copy is keyed by user id and removed on sign out, user switch and when a shared space ends.
- [ ] No signed link, album link or other short lived URL is saved.
- [ ] Independent reads start in the same tick.
- [ ] Every wait has a timer, and the timer is cleared when the answer wins.
- [ ] Three device cold starts are recorded before and after the change.

## Tests that prove it
- A unit test that the allow list saves the home keys and never a signed link of the private album.
- A test that restore keeps the original read time, so a stale entry is still refetched.
- A test that the restore skips an expired signed link.
- A test that the user switch clears the previous user's entries before the new user's are read.
- A test that the timed wait resolves as late and the late answer is applied only when it is safe.
- A test that the timer is cleared when the server answers first (otherwise Jest will not exit).

## Related skills
- `react-query-in-react-native`: the cache, the key factory and the test client.
- `offline-outbox-and-sync`: what happens to unsent writes at launch.
- `expo-router-route-gate`: where the first screen sends the user.
