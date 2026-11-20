---
name: expo-local-android-builds
description: Build an Android release APK for an Expo app on your own machine when cloud build minutes run out, then install and check it before calling it ready. Covers the local EAS build, the JDK and Android SDK, which environment values reach the build and which do not, keeping secrets out of the terminal, building from a separate git worktree, same signing for upgrade installs, and launching the build and reading the crash log. Load when a cloud build fails or is out of quota, or before telling anyone a release build works.
---

# Expo local Android builds

## When to use this
- Cloud build minutes are used up, and you still need an installable Android build to test.
- A release build behaves differently from development, and you need to reproduce it.
- You want to test a build from a branch while your working tree holds other work.
- An install of a new build fails on a device or emulator that already has the app.

## Rules
1. **Install, launch and read the crash buffer before you say a build is ready.** Why: a local build crashed at launch with "API key not found", and an earlier release build crashed on launch while development did not. One build was reported as ready without this check, and the app closed on every open.
2. **Build the release variant, not the development one, for a release check.** Why: the release build runs code shrinking and keep rules that development does not.
3. **Pass build time values through the build's own environment, and check them.** Why: values the build reads at configuration time must be present in the shell that runs the build, or the app ships without them.
4. **Never print a secret while you load it.** Load it into the environment, check that it is set, and never echo it. Why: terminal output is logged, shared and pasted.
5. **Build from a separate worktree at the commit you want.** Why: a build that reads the working tree picks up half finished changes, and a checkout switch disturbs the work in progress.
6. **Sign the local build with the same key as the build it replaces.** Why: Android installs an upgrade only when the signature matches. A different key is a separate app, so the install is refused.
7. **Keep the same app id and version rules across builds you want to upgrade.** Why: the same reason as rule 6, and version codes must not go backwards.

## How to do it

Cloud build minutes ran out, so release APKs were built on the developer machine with `eas build --local`. Each local build took about six minutes. The steps below are the ones that produced those APKs.

### 1. Prerequisites
- JDK 17, the version the local builds used. Check it against the Expo SDK's documentation for your project.
- The Android SDK with the platform and build tools the project targets, and `ANDROID_HOME` set.
- An emulator or a device with USB debugging, and `adb` on the path.
- The Expo and EAS command line tools, and the project's dependencies installed in the worktree.

### 2. Worktree
```bash
git worktree add ../app-build-<short-sha> <commit>
cd ../app-build-<short-sha>
ln -s /path/to/main-checkout/node_modules node_modules   # reuse the installed dependencies
```

Remove the worktree when the build is installed.

### 3. Environment
Local builds do not receive the server side build environment. A build without it crashes at launch (see the gotchas).
- Pull the non secret values with `eas env:pull`.
- Secret values, such as a map SDK key, come from a local file that is gitignored. Load it into the shell without printing it:

```bash
set -a; . ./.build.env; set +a          # loads the values into this shell
for k in GOOGLE_MAPS_ANDROID_API_KEY; do
  [ -n "${!k:-}" ] && echo "$k: set" || echo "$k: MISSING"
done
```

Check each required name, and stop if one is missing. Do not run a command that prints the file or the environment.

### 4. Build
```bash
eas build --platform android --profile preview --local
```

Use the profile whose signing and environment you want. Confirm the profile name in your own `eas.json` first, since names vary by project. The output is an APK file in the directory the command reports.

### 5. Install over the old build
```bash
adb install -r path/to/build.apk
```

The `-r` flag replaces the app and keeps its data. The local build used the same remote signing credentials as the cloud build, so the APK installs over the cloud build. Upgrade installs keep the user's session, which is worth testing on its own.

### 6. Launch and read the crash log
```bash
adb shell monkey -p <application id> -c android.intent.category.LAUNCHER 1
adb logcat -d -b crash | tail -n 80
adb logcat -d -s AndroidRuntime:E ReactNativeJS:E | tail -n 80
```

Wait for the first screen before you read the log. Then do one real flow, such as signing in and opening a list. Only after that, report the build as ready.

## Gotchas
- **Launch crash in a release build only.** The first cloud preview builds crashed on launch in release, and development did not show it. Cause: the shrinking step (R8) stripped the database classes that a background work library needs at runtime. Fix: keep rules, added through the build properties plugin. Check the release build, not only development.
- **Local build crashes at launch with "API key not found".** The message came from the maps library. Cause: local builds do not receive the server side build environment, so the map key was missing. Fix: pull the non secret values with `eas env:pull`, and load the secret map key from the local file into the shell without printing it (step 3).
- **Install refused: conflicts with an existing package.** An older build with a different signature is still installed. Cause: Android refuses to replace an app with a different signing key. Fix: uninstall the old build (this deletes its local data), then install. Or sign the new build with the same key.
- **A release build behaves differently on screen.** The release emulator test found the keyboard covering the edit sheets, which needed a fix. Test forms, Back and keyboards on a release build.
- **Emulator is the test device.** Release tests in this project ran on an emulator (a Pixel 3a image on API 34). Say which device you tested on, and do not claim a physical device test you did not run.

## Checklist
- [ ] The build runs from a worktree at the chosen commit.
- [ ] Every required environment name is set, and no value was printed.
- [ ] The build is the release variant and uses the profile you meant.
- [ ] The APK path is from this build, not an old one.
- [ ] The APK installs over the previous build with `-r`, or the old one was removed on purpose.
- [ ] The app launches, the first screen draws, and one real flow works.
- [ ] The crash log is empty of `AndroidRuntime` errors after that flow.
- [ ] The report names the device, the build commit and the flows tested.

## Tests that prove it
- A release smoke test: launch, sign in or open the first screen, and check the crash log is clean.
- A check script that fails when a required environment name is missing, without printing its value.
- A test on the keyboard, Back and the first screen on the release build, not only in development.

## Related skills
- `react-native-android-keyboard`: the keyboard fault that only showed on a release build.
- `expo-router-route-gate`: check Back and redirects on the release build.
- `expo-app-start-performance`: a release build is the one to measure cold start on.
