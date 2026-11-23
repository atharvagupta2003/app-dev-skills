# Jotly notes sample

This is an Expo app running in Expo Go on an Android emulator that is already open and showing the app. Metro is already running.

Rules for working here:

1. Change App.tsx with one Write call that holds the whole new file. Every save reloads the app on the phone, so a half finished edit breaks the screen.
2. To look at or use the phone, use only adb: `adb shell uiautomator dump`, `adb shell input tap`, `adb shell input text` and `adb shell screencap`. The screen is 1080 by 2220 pixels.
3. Stay inside the open app. Never press Home or Back, never swipe from a screen edge, and never launch, stop, install, clear or uninstall any app. The emulator holds other apps that must not be opened or changed.
4. Run each adb command as its own Bash call from the project folder, with no cd, no pipes, no chaining and no shell redirects. For a screenshot run `adb shell screencap -p /sdcard/shot.png`, then `adb pull /sdcard/shot.png shot.png`, then read shot.png with the Read tool.
5. Do not run npm, npx, expo or git commands.
