---
name: android-emulator-real-user-testing
description: Driving a release build of an Expo or React Native app on an Android emulator with adb, as a real user would. Covers reading the screen as text with uiautomator, tapping by bounds, testing two accounts on one device or two emulators, signing in test accounts without an inbox, checking the crash buffer, comparing database state before and after with read only queries, leaving the device in a known state, and a checks table that records pass, fail or not run with evidence. Load before a real user pass, or when a feature needs a device check that unit tests cannot give.
---

# Android emulator real user testing

## When to use this
- A feature is built and its unit and database tests pass, but nobody has used it on a device.
- A change touches sign in, navigation, the keyboard, uploads, or anything with two people on it.
- Before a build goes to testers.
- You need to say honestly which checks ran on a device and which did not.

## Rules
1. **Test a release build, not the development server, for the final pass.** Install the build the way a tester would, and upgrade over an older build when the change allows it.
   Why: the development client (Expo Go) has its own launcher, so some start up behaviour cannot appear there. The project's release APK passes were the ones that counted for upgrade installs and cold starts.
2. **Read the screen as text first. Take a screenshot only when text is not enough.** Dump the accessibility tree, find the element by its text or id, and tap its centre from its bounds.
   Why: a text dump is small, exact and searchable. A screenshot costs more and cannot be searched for a label.
3. **Tap by bounds, and skip elements with zero size.** A view with zero width or height, or with zero opacity, is not on screen and is not in the test tree.
   Why: tapping a stale position hits whatever is underneath, and that looks like a bug in the app.
4. **Test two accounts on two devices when the feature has two people in it.** Run two emulators at once so that live updates and pushes can be seen on both sides. If you only have one emulator, sign out and in between steps, and write down that live delivery was not seen.
   Why: a feature that updates the other person needs both views open. One device cannot show that.
5. **Sign in test accounts without an inbox by making a one time code through the auth admin API.** Keep the service key in a shell variable for the session, read it from a prompt or a secret store, and never write it into a file, a flow, a log or a commit.
   Why: test accounts on a hosted project have no inbox to read. The key is powerful, so it must live only in the process that uses it.
6. **Check the crash buffer after each flow.** A flow can pass while the app crashes in the background.
   Why: a crash that happens after the last assertion never fails a text check.
7. **Compare database state before and after each step with read only queries.** Run `select` statements in a read only transaction. Never write to the hosted database from a device pass.
   Why: the screen can show success while the row is wrong. The database is the proof.
8. **Use in app markers for timing, not screenshots.** Log a named marker from the app at a known point, then read the log for the time between two markers.
   Why: a screenshot cannot give a time. A marker can. (Not verified in this project's notes. Check it works in your build before relying on it.)
9. **Write each check as pass, fail or not run, with its evidence.** Evidence is the text dump line, the log line, or the query result. Never write "pass" without evidence.
   Why: the project's notes record Maestro flows that were "written, not run" because they needed the emulator. Those must not be counted as tested.
10. **Leave the device in a known state.** Clear the app's data or reset its test state at the start, and put back any flag or setting you changed.
    Why: a device that carries state from the last run makes the next run pass or fail for the wrong reason.

## How to do it

Setup, once per session:

```bash
adb devices                         # one line per emulator, must say "device"
adb logcat -c                       # clear the log so the crash check reads only this run
adb install -r build/app-release.apk
adb shell pm clear <app.package>    # known state: no session, no data
```

Read the screen and tap a label (the helper in `examples/tap_by_text.py` does the parsing):

```bash
adb shell uiautomator dump /sdcard/window.xml
adb pull /sdcard/window.xml ./window.xml   # then search it for the label and its bounds
adb shell input tap 540 1650               # the centre of the bounds you found
adb shell input text 'an example'          # type into the focused field
adb exec-out screencap -p > step-03.png    # only when a text check cannot answer the question
```

Deep links into a build that has them:

```bash
adb shell am start -a android.intent.action.VIEW -d "<scheme>://<path>"
```

Crash buffer after each flow:

```bash
adb logcat -b crash -d | tail -n 50        # empty is the expected result
```

Sign in a test account without an inbox. Generate a one time code through the admin API, using a key that is held only in the shell:

```bash
read -rs SERVICE_KEY && export SERVICE_KEY      # typed at a prompt, never written to a file
export API_URL="<the project's API URL>" TEST_EMAIL="<a test account's address>"
curl -s -X POST "$API_URL/auth/v1/admin/generate_link" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"magiclink\",\"email\":\"$TEST_EMAIL\"}" \
  | jq -r '.email_otp // .properties.email_otp'
unset SERVICE_KEY
```

The field that holds the code depends on the auth version, so check its shape once with a test account. Print only the code, never the key or the full response.

Read-only database check before and after a step, in a transaction that cannot write:

```sql
begin read only;
select mode, state, updated_at from public.memberships where member_id = '<member-id>';
rollback;
```

The checks table, written at the end of each pass (the rows are examples of the format):

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Sign in as member A from a blank state | pass | dump line "Home" after sign in; zero crash lines |
| 2 | Member B sees the change within 10 s | not run | no second emulator; live delivery not seen |
| 3 | Upload rejects a file over the limit | fail | dump shows no error text; query shows a stored row |
| 4 | Push arrives on the other device | not run | push delivery cannot be checked on this emulator; outbox row checked instead (pass) |

## Gotchas
- **Symptom:** the element is in the dump but the tap does nothing. (General.)
  **Cause:** the element is a container that does not handle presses, and its child holds the handler, or the tap landed on an overlay.
  **Fix:** tap the element that owns the handler, found by its id or label, and dump again after each tap to confirm the screen changed.
- **Symptom:** the dump shows the screen before the new one has rendered. (General.)
  **Cause:** the dump ran during an animation or a network wait.
  **Fix:** wait until a known label of the next screen appears, then read the state. Do not sleep for a fixed time.
- **Symptom:** a release build works on the emulator, then a tester reports a crash on the same version. (General.)
  **Cause:** a path that the emulator never took, such as a first sign in on a clean device, or a permission prompt.
  **Fix:** run the clean install path and the upgrade path, and keep the crash buffer check on each.
- **Symptom:** a flow passes after a previous run left the session in place.
  **Cause:** the device was not cleared at the start.
  **Fix:** `pm clear` first, and record it as the first check.
- **Symptom:** push tests seem to pass. (General.)
  **Cause:** the check looked at the app's own list, which can update without a push.
  **Fix:** check the outbox row that queued the push, mark delivery "not run", and say so in the report.
- **Symptom:** the UI dump says "could not get idle state", or shows a screen that is no longer there. (General.)
  **Cause:** the dump ran while the screen was still changing, so the hierarchy is stale.
  **Fix:** dump again. When the text and the screen disagree, trust a screenshot and record the mismatch.
- **Symptom:** a tap does nothing on the first try, on a slow emulator. (General.)
  **Cause:** the first tap did not register.
  **Fix:** dump after the tap. If the screen did not change, repeat the tap once, but only for a tap that is safe to repeat (no submit, no payment, no send). Record the retry in the evidence.
- **Symptom:** switching test accounts is slow, because sign out is hard to reach. (General.)
  **Cause:** the sign out control is off screen or behind a long menu.
  **Fix:** clear the app's data (`pm clear`), then sign in as the other account. Sign out itself is then not tested, so list it as "not run" in the checks table, with the reason.
- **Symptom:** an "isn't responding" dialog appears on the first launch after install. (General.)
  **Cause:** usually the emulator being slow on its first start, not a crash.
  **Fix:** tap Wait, then read the crash buffer before you call it a crash. Record the dialog and the buffer result.

## Checklist
- [ ] The build is a release build, installed the way testers install it.
- [ ] The device was cleared, and each flag changed for the test was put back.
- [ ] Each step reads text from a dump, and a screenshot is taken only where text cannot answer.
- [ ] Two accounts were tested on two devices, or the report says one device was used.
- [ ] The crash buffer is empty after each flow.
- [ ] The database was read before and after with read only queries.
- [ ] Each check is pass, fail or not run, with its evidence.
- [ ] Anything not run is listed in the report with the reason. If the device was cleared to switch accounts, sign out is listed as not run.
- [ ] A first launch "isn't responding" dialog was checked against the crash buffer before it was called a crash.

## Tests that prove it
- Run the same pass twice from a cleared device and get the same checks table.
- Introduce a known bug in a scratch build (for example a button that does nothing) and confirm the check fails.
- Confirm the key was not written anywhere: search the shell history and the working tree for the key value.

## Related skills
- [maestro-and-flow-tests](../maestro-and-flow-tests/SKILL.md) for repeatable flows that run on the same builds.
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md) for the device check at each step of a rollout.
- [independent-review-before-deploy](../independent-review-before-deploy/SKILL.md) for reviewing a device pass before a deploy.
