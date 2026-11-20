---
name: maestro-and-flow-tests
description: Writing and running Maestro end to end flows for an Expo or React Native app. Covers flows built on seeded fixtures, stable test ids, element bounds and tap patterns that work on iOS and Android, elements hidden from the accessibility tree, shared helper flows with retries, and the rule that a flow written but not run must be reported as not run. Load when writing a Maestro flow, debugging one that cannot find an element, or reporting flow results.
---

# Maestro and flow tests

## When to use this
- Writing an end to end flow for a screen or a journey.
- A flow fails to find text or a button that is plainly on screen.
- A flow taps the wrong thing, or taps before the screen is ready.
- Reporting what a change's flows did, or did not, run.

## Rules
1. **Start every flow from a seeded fixture, not from whatever the last run left.** Use a dev-only deep link that seeds a known member, then sign in or land on the screen under test.
   Why: a flow that depends on earlier state passes or fails depending on the order it runs in. The project's sign-in helper retries the seed link because a restored session can redirect the first link.
2. **Select by stable test id first, then by accessible label, and by visible text last.** Give each control that a flow touches an id, and use `id:` in the flow.
   Why: text changes with copy edits, and a label that concatenates a card's children does not match the text you expect. The project's notes say to use ids for pressable cards.
3. **Assert the whole text, or use a pattern.** Maestro matches the entire string of an element's text.
   Why: `assertVisible: "Living room"` failed against the on-screen text "Living room, 4 things" in one project. Write the full text, or use a regular expression that allows the rest.
4. **Wrap any control that appears late or fades in with a retry, and wait on the next screen's element.** Do not rely on a fixed sleep, and do not rely on `waitForAnimationToEnd` alone.
   Why: a tap during a typing animation was lost in one project, and a waiting animation alone did not stop an overlay from covering a button.
5. **Tap by a point that is not covered.** When a banner or an overlay covers a button, dismiss the overlay first, then tap the button by its text or id.
   Why: a development banner covered the button's centre on an iPhone simulator, so a tap at the centre hit the banner.
6. **Put a text label on the touchable itself, and use `accessible={false}` on layout wrappers.** A touchable's child text is hidden from the tree in many setups.
   Why: a button's text was not found by Maestro until the label was set on the touchable.
7. **Do not rely on hidden elements.** A view with zero opacity, zero width or zero height is not in the accessibility tree and cannot be tapped or asserted.
   Why: a marker view with zero opacity was invisible to the iOS test runner, so a flow waiting on it never saw it.
8. **Report a flow written but not run as "not run".** Do not write "covered by Maestro" for a flow that was never executed on a device or simulator.
   Why: the project's notes list several flows as "written, not run (needs the emulator)". Those were not evidence of anything.

## How to do it

A flow for one screen, with a seeded member and a helper for a control that may fade in:

```yaml
# .maestro/space-leave.yaml
appId: <your.expo.app.id>
---
- runFlow: lib/sign-in.yaml
  env:
    EMAIL: "${TEST_MEMBER_EMAIL}"   # passed in from the shell, never written in the flow
- tapOn:
    id: "tab-space"
- runFlow:
    file: lib/pick-expect.yaml
    env:
      ID: "btn-space-settings"
      EXPECT: "screen-space-settings"
- scrollUntilVisible:
    element:
      id: "btn-leave-space"
    direction: DOWN
- runFlow:
    file: lib/pick-expect.yaml
    env:
      ID: "btn-leave-space"
      EXPECT: "screen-leave-confirm"
- tapOn:
    id: "btn-leave-confirm"
- extendedWaitUntil:
    visible:
      id: "screen-home"
    timeout: 20000
```

The helper that taps and waits for the next screen, retrying if the tap was lost:

```yaml
# .maestro/lib/pick-expect.yaml
appId: <your.expo.app.id>
---
- retry:
    maxRetries: 3
    commands:
      - extendedWaitUntil:
          visible:
            id: "${ID}"
          timeout: 120000
      - tapOn:
          id: "${ID}"
          waitToSettleTimeoutMs: 200
      - extendedWaitUntil:
          visible:
            id: "${EXPECT}"
          timeout: 120000
```

Platform specific deep links in one flow:

```yaml
- runFlow:
    when:
      platform: Android
    commands:
      - openLink: "exp://10.0.2.2:8090/--/dev?seed=fresh"
- runFlow:
    when:
      platform: iOS
    commands:
      - openLink: "exp://127.0.0.1:8090/--/dev?seed=fresh"
```

On iOS, a launch that is followed at once by element queries can crash the test runner on a cold boot. A short downward swipe right after launch avoided it in one project:

```yaml
- launchApp:
    clearState: false
- swipe:
    direction: DOWN
    duration: 100
```

Run the flows against a build that matches the screen you changed. Expo Go and a release build differ (see the Android skill), so say which one ran.

## Gotchas
- **Symptom:** a Pressable card does nothing, or the screen behind it is blank, with no error.
  **Cause:** a function style on `Pressable` (`style={({ pressed }) => ...}`) silently drops both the style and the children in this stack.
  **Fix:** use an array style. Check for a blank area before blaming the flow.
- **Symptom:** `assertVisible` fails on text you can see.
  **Cause:** the text is part of a longer accessible label, or the touchable hides its child text.
  **Fix:** assert the full label, or set the label on the touchable and use `id:`.
- **Symptom:** a tap at a button's centre hits something else, on iOS.
  **Cause:** a development banner overlaps the button's lower part.
  **Fix:** dismiss the banner by tapping its close area, or tap the button at a point above the banner, and check the screen changed.
- **Symptom:** a flow stops on a sign-in screen at random.
  **Cause:** the welcome line types out first, and a tap during the animation is lost, or a restored session redirects the first link.
  **Fix:** retry the tap until the field appears, and retry the seed link until its button appears.
- **Symptom:** a Maestro run needs a Java runtime and fails before any test starts.
  **Cause:** no JDK is set up for Maestro.
  **Fix:** install a JDK and set `JAVA_HOME` to it in the shell that runs Maestro. Point it at a path on your own machine.

## Checklist
- [ ] Each flow starts from a seeded member and a known screen.
- [ ] Each control the flow touches has a test id.
- [ ] Text assertions use the full string or a pattern.
- [ ] Late controls use a retry, and waits name the next screen's element.
- [ ] Nothing depends on a hidden, zero size or zero opacity element.
- [ ] The flow ran on a named build, and its result is written down.
- [ ] Any flow that was not run is listed as "not run", with the reason.

## Tests that prove it
- Run each flow twice in a row from a clean state. Both runs must pass.
- Break one test id on purpose and confirm the flow fails at that step, with the element named in the output.
- Run the flow on the platform you did not write it for, and record the result, even if it is a failure.

## Related skills
- [android-emulator-real-user-testing](../android-emulator-real-user-testing/SKILL.md) for driving a device by hand and recording checks.
- [jest-react-native-testing](../jest-react-native-testing/SKILL.md) for the labels and ids that flows depend on.
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md) for flows that run with a feature switched on for testers only.
