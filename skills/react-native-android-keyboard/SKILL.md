---
name: react-native-android-keyboard
description: Keep primary buttons, pinned footers and focused fields above the soft keyboard in React Native on edge to edge Android, and verify it on a device. Covers the keyboard's top edge versus the reported height, numeric keyboards, pinned footers in sheets, scrolling a focused field into view, keyboardShouldPersistTaps, reduced motion, and measuring a node that an animation moves. Load when a button or field is hidden by the keyboard, or when adding a form, sheet or footer.
---

# React Native Android keyboard

## When to use this
- A primary button or Save sits under the keyboard on Android, and iOS is fine.
- A field low in a long form is hidden when the keyboard opens.
- A sheet with a pinned footer does not lift, or lifts too far.
- A tap on a button closes the keyboard and does nothing else.
- Editing a field that was opened from a modal does not bring up the keyboard.

## Rules
1. **On edge to edge Android, position from the keyboard's top edge, not its height.** The reported height leaves out the navigation bar inset, so lifting by it leaves the button partly hidden. Why: measured on a 1080 by 2220 emulator with edge to edge on, lifting the footer by the reported height left the primary button's bottom about 12 dp under the keyboard, the size of the navigation bar.
2. **Measure the button's bottom in window coordinates.** Compare it with the keyboard's `screenY`. Why: the two numbers are in the same coordinate space, so the gap holds for any keyboard.
3. **Re fit on every show event, and on the button's layout.** The show event also fires when the keyboard changes height, for example when a suggestion strip appears. Why: a fixed value from the first show goes stale.
4. **Return to the rest padding on hide.** Why: a footer that keeps its lift leaves a gap under the screen.
5. **Use the platform's avoiding view on iOS, and the measurement on Android.** Why: the two platforms report different things, and one approach on both leaves one of them wrong.
6. **Scroll a focused field into view yourself when the view does not shrink.** Why: on a plain screen on an edge to edge window the scroll view keeps its height, so the platform never scrolls the field.
7. **Let taps through to buttons while the keyboard is open.** Use `keyboardShouldPersistTaps="handled"` on screens with a pinned button. Why: with the default, the first tap only closes the keyboard and the button does not fire.
8. **Scroll without animation when the user asks for reduced motion.** Why: the same rule as every other motion in the app.
9. **Never measure a node that a transform moves. Put the entrance animation inside the measured node, so the measured node itself stays still.** Why: `measureInWindow` includes transforms. A button wrapper that sat inside a translate animation was measured while the animation ran, and it was never measured again after the animation settled. It sat about 4 dp off, on the one screen that focused its input at once.

## How to do it

### 1. Pinned footer on Android
Compute the padding that lifts the footer so its button bottom sits a fixed gap above the keyboard's top edge.

```ts
export function footerPadding(a: { footerBottom: number; keyboardTop: number; rest: number; gap?: number }): number {
  const lifted = a.footerBottom - (a.keyboardTop - (a.gap ?? 12));
  return Math.max(a.rest, Math.round(lifted * 2) / 2);
}
```

In the hook, subscribe to `keyboardDidShow` and `keyboardDidHide` (Android only). On show, store `e.endCoordinates.screenY` and call `refit`. `refit` calls `measureInWindow` on the footer, works out the button's bottom from its height and current padding, and sets the padding. On hide, store null and return to rest. Spread the `ref` and `onLayout` onto a plain wrapper View around the button, not onto the button.

`footerPadding` is pure, so test it with numbers. Test the hook with a fake node whose `measureInWindow` reports a fixed box.

### 2. Reveal a focused field
On `keyboardDidShow`, wait a short settle time (about 60 ms in this project; the keyboard's own avoiding view resizes a moment after it shows). Then:
1. Ask the text input state for the focused field.
2. Measure it relative to the scroll view's inner view, and check it against the visible band. Scroll if it is outside the band.
3. If the band says it is fine (the view did not shrink), measure the field in window coordinates and compare its bottom with the keyboard's top edge. Scroll only when it is under the keyboard.

```ts
export function keyboardRevealOffset(a: { fieldTop: number; fieldBottom: number; scrollY: number; keyboardTop: number }): number | null {
  if (a.keyboardTop <= 0) return null;
  const over = a.fieldBottom + 16 - a.keyboardTop;
  if (over <= 0) return null;
  const room = Math.max(0, a.fieldTop - 16); // never scroll a tall field past its own top
  return a.scrollY + Math.min(over, room);
}
```

Read the keyboard top with a fallback: if `screenY` is zero, use the window height less the keyboard height.

### 3. Taps while the keyboard is open
- Screens with a pinned button: `keyboardShouldPersistTaps="handled"`.
- A sheet that holds a text field and buttons: `keyboardShouldPersistTaps="always"`. The sheet's comment says the default `never` lets the first touch be captured by the keyboard dismissal.
- Read-only lists: leave the default.

### 4. Focus from a modal
Do not use `autoFocus` on an input inside a modal. The cursor shows but the keyboard does not open. Focus the input by ref after the step that shows it has mounted, with a short delay (350 ms in this project).

## Gotchas
- **Save hidden under the keyboard on Android only.** On a release build a text sheet hid its Save and Cancel buttons when the keyboard came up. Cause: the lift used the reported height, which leaves out the navigation bar inset on edge to edge windows. Fix: the screen-based measurement above. Verified on a release build on an emulator: the field, counter, Save and Cancel were visible at the default and at a large font size.
- **Numeric keyboard.** Positioning from the keyboard's top edge (`endCoordinates.screenY`) and the button's measured bottom fixed the lift for both the text keyboard and the numeric keyboard. Verified on the 1080 by 2220 emulator: the gap between the button's bottom and the keyboard's top was 12 dp on both screens.
- **The field stays under the keyboard in a tall form.** A plain scroll view does not shrink, so the platform never scrolls. Fix: the reveal above, which scrolls only the amount needed and never past the field's own top.
- **An error line runs under the button at a large font size.** With the keyboard up at font scale 1.3, the error text sat under the Continue button. Fix: the body of that screen scrolls, so the error can be reached.
- **First tap only closes the keyboard (reasoning, check on your app).** A button in a sheet may do nothing on the first tap. The likely cause is the default `keyboardShouldPersistTaps` of `never`. Fix: `always` or `handled` on that scroll view, as the sheet component does.
- **A button sits about 4 dp off on one screen only.** Cause: the wrapper that the footer measured was inside an entrance animation with a translate transform. The screen focused its input at once, so the keyboard arrived mid animation. The measurement included the transform, and nothing measured again after the spring settled. Fix: move the animation inside the measured node, so the measured node never moves. Verified on a device three times, by comparing the button's bounds from the UI dump with the keyboard frame.
- **Footer padding stays after the keyboard hides (hypothesis).** If the hide event is not handled, the lift stays. Fix: store null and reset to rest on hide, as the hook does.

## Checklist
- [ ] Each form with a pinned button uses the footer hook on Android.
- [ ] Each scroll view with inputs and buttons sets `keyboardShouldPersistTaps` on purpose.
- [ ] No `autoFocus` inside a modal.
- [ ] The reveal hook is on every form longer than one screen.
- [ ] Reduced motion turns off animated scrolling.
- [ ] The node that is measured for the lift has no transform animation on it or above it.
- [ ] On a device, the primary button's bottom is above the keyboard's top, at the default and the largest font size.

## Tests that prove it
- Pure tests of `footerPadding` and `keyboardRevealOffset` with numbers either side of each edge, and with a tall field.
- A hook test that a show event lifts the footer and a hide event resets it.
- A test that the reveal hook scrolls a field that is under the keyboard and does nothing for one that is clear.
- For a screen that animates in and focuses at once: a device check on that screen, repeated three times, comparing the button's bounds with the keyboard frame after the animation has settled.
- A device check, used for the text and numeric keyboards: with the keyboard open, compare the button's bounds from an `adb shell uiautomator dump` with the top of the input method window (the keyboard's top edge, from `adb shell dumpsys window`). The button's bottom must be above the keyboard's top. On the verified emulator the gap was 12 dp on both keyboards.

## Related skills
- `expo-local-android-builds`: the keyboard only failed on a release build, so check it there.
- `expo-router-route-gate`: sheets that close on Back need the same care.
