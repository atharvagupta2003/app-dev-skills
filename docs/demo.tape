# Terminal half of the demo. Run through docs/record-demo.sh, which sets the
# environment variables used by demo-env.sh and drives the emulator half.
Output "terminal.mp4"
Set Shell "bash"
Set FontSize 17
Set Width 900
Set Height 820
Set Padding 16
Set Framerate 20
Set TypingSpeed 28ms
Set Theme "Catppuccin Mocha"

# Hidden setup: accept the folder trust prompt so the clip starts on a ready input box.
Hide
Type "source $DEMO_ENV && cd $DEMO_APP && clear && mark" Enter
Sleep 1s
Type "claude" Enter
Sleep 5s
Down
Enter
Sleep 8s
Show

Sleep 2.5s
Type "Test the new note screen on the emulator like a real user and fix anything that gets in the way. Use any skills that help. The app is already open there."
Sleep 800ms
Enter
# The clip is trimmed to the real end of the session when composing, so this only
# needs to outlast it.
Sleep 170s
