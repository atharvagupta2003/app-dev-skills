#!/usr/bin/env bash
# Records the side by side demo: Claude Code in a terminal (VHS) and the sample
# app on an Android emulator (adb screenrecord), taken in one continuous run.
# Claude is asked to test the screen like a real user, finds the problem itself, fixes it
# and checks the fix. This script performs no device actions during the recording.
#
#   docs/record-demo.sh capture    run the real session, write raw clips to $WORK
#   docs/record-demo.sh compose    stack the clips and write docs/demo.gif
#
# Needs: vhs, ffmpeg, gifsicle, adb, python3, the claude CLI signed in, an Android
# emulator already booted with Expo Go, and an Expo SDK app in $DEMO_APP served by
# `npx expo start`, open in the foreground (docs/demo-app has its App.tsx and notes).
set -euo pipefail
trap 'echo "failed at line $LINENO" >&2' ERR

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
WORK="${WORK:-/tmp/demo-work}"
export DEMO_APP="${DEMO_APP:-/tmp/notes-app}"
EXPO_URL="${EXPO_URL:?set EXPO_URL, for example exp://192.168.1.10:8081}"
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"

adbq() { adb shell "$@" </dev/null; }
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
keyboard_shown() { adbq dumpsys input_method | grep -q 'mInputShown=true'; }

demo_mode() {
  adbq settings put global sysui_demo_allowed 1
  local b='am broadcast -a com.android.systemui.demo -e command'
  adbq $b enter >/dev/null
  adbq $b clock -e hhmm 1000 >/dev/null
  adbq $b notifications -e visible false >/dev/null
  adbq $b network -e wifi show -e level 4 >/dev/null
  adbq $b battery -e level 100 -e plugged false >/dev/null
}
demo_mode_off() { adbq am broadcast -a com.android.systemui.demo -e command exit >/dev/null || true; }

capture() {
  rm -rf "$WORK"; mkdir -p "$WORK/marks"
  export DEMO_MARKS="$WORK/marks" DEMO_ENV="$HERE/demo-env.sh" DEMO_SETTINGS="$WORK/settings.json"
  sed "s#__PLUGIN_REAL__#$REPO#g" "$HERE/demo-settings.json" > "$DEMO_SETTINGS"
  ln -sfn "$REPO" /tmp/app-dev-skills
  export PLUGIN_DIR=/tmp/app-dev-skills EMPTY_MCP="$WORK/empty-mcp.json"
  echo '{"mcpServers":{}}' > "$EMPTY_MCP"
  for v in $(env | grep -E '^(CLAUDE|ANTHROPIC)' | cut -d= -f1); do unset "$v"; done

  # Known starting state for the sample project.
  cp "$HERE/demo-app/App.tsx" "$HERE/demo-app/CLAUDE.md" "$DEMO_APP/"
  git -C "$DEMO_APP" add -A
  git -C "$DEMO_APP" -c user.name=demo -c user.email=demo@example.com commit -qm "demo base" || true
  git -C "$DEMO_APP" reset -q --hard HEAD
  git -C "$DEMO_APP" clean -fdq
  sleep 3

  local ok=0
  for _ in 1 2 3; do
    adbq am force-stop host.exp.exponent
    adbq am start -a android.intent.action.VIEW -d "$EXPO_URL?__expo_disable_fab=1" host.exp.exponent >/dev/null
    sleep 14
    if adbq dumpsys window | grep mCurrentFocus | grep -q host.exp.exponent; then ok=1; break; fi
  done
  [ "$ok" = 1 ] || { echo "sample app is not in the foreground" >&2; exit 1; }
  demo_mode
  if keyboard_shown; then adbq input keyevent 4; sleep 1; fi

  (cd "$WORK" && vhs "$HERE/demo.tape" >"$WORK/vhs.log" 2>&1) &
  VHS_PID=$!
  while [ ! -s "$WORK/marks/start" ]; do sleep 0.2; done
  S="$(cat "$WORK/marks/start")"
  wait_until() { perl -MTime::HiRes=sleep,time -e '$d=$ARGV[0]-time; sleep($d) if $d>0' "$(python3 -c "print($S+$1)")"; }

  # Start the device clip a few seconds before the terminal clip shows anything.
  wait_until 9
  adbq rm -f /sdcard/demo.mp4
  adb shell screenrecord --time-limit 180 --size 720x1480 --bit-rate 8000000 /sdcard/demo.mp4 </dev/null &
  DEV_PID=$!
  now > "$WORK/marks/dev_started"

  # No device actions from this script: every tap, text entry and screenshot is Claude's.
  # Claude Wait for its turn to finish (Stop hook), then hold the final frame.
  for _ in $(seq 1 700); do [ -s "$WORK/marks/stop" ] && break; sleep 0.5; done
  sleep 7
  echo "end $(now)" >> "$WORK/events.log"
  adbq pkill -2 screenrecord || true
  wait "$DEV_PID" 2>/dev/null || true
  sleep 2
  adb pull /sdcard/demo.mp4 "$WORK/device.mp4" >/dev/null
  wait "$VHS_PID" || true
  demo_mode_off
  git -C "$DEMO_APP" diff > "$WORK/fix.diff" || true
  echo "capture done in $WORK"
}

# Seconds into the terminal clip at which Claude Code received the prompt: the wait,
# the typing and the pause before Enter in demo.tape.
enter_time() {
  python3 -I - "$HERE/demo.tape" <<'PY'
import re, sys
n = 0
for line in open(sys.argv[1]):
    m = re.match(r'Type "(Test the new note[^"]*)"', line)
    if m: n = len(m.group(1))
print(round(2.5 + n * 0.028 + 0.8, 2))
PY
}

# The device clip only has frames where the screen changed, so each pane is made a
# constant 20 fps stream BEFORE trimming. Trimming the raw clip drops the frame that is
# on screen at the cut point and shifts the whole phone pane.
# Speed segments, as start:end:speed in terminal clip seconds. The same ranges apply to
# both panes, so they stay in sync. A gap between segments is a cut, also on both panes.
# Default: real time until two seconds after the prompt and for the last 8 seconds,
# SPEED in between.
compose() {
  local T="$WORK/terminal.mp4" V="$WORK/device.mp4"
  local ENTER_T="${ENTER_T:-$(enter_time)}" SPEED="${SPEED:-1.8}" HOLD="${HOLD:-5}"
  ffmpeg -loglevel error -y -i "$V" -vf "fps=20,crop=720:300:0:1100,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=$WORK/yavg.txt" -f null -
  local onset
  onset="$(python3 -I - "$WORK/yavg.txt" <<'PY'
import re, sys
t = prev = None
for line in open(sys.argv[1]):
    m = re.search(r"pts_time:([\d.]+)", line)
    if m: t = float(m.group(1))
    m = re.search(r"YAVG=([\d.]+)", line)
    if m:
        v = float(m.group(1))
        if prev is not None and v - prev > 60: print(t); break
        prev = v
PY
)"
  # VHS renders its video a little faster than wall time (frames are captured per tick, and
  # the video is encoded at a fixed rate), so terminal clip seconds are shorter than real
  # seconds. K is video seconds per real second, from the clip length against the tape.
  local TDUR TAIL_SLEEP K
  TDUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$T")"
  TAIL_SLEEP="$(awk '/^Sleep/{v=$2} END{sub("s","",v); print v}' "$HERE/demo.tape")"
  K="$(python3 -c "print($TDUR / ($ENTER_T + $TAIL_SLEEP))")"
  local DEVOFF END AUTOSEG
  read -r DEVOFF END AUTOSEG < <(python3 -I - "$WORK/marks/tools.log" "$(cat "$WORK/marks/dev_started")" "$onset" "$(cat "$WORK/marks/submit")" "$ENTER_T" "$(awk '$1=="end"{print $2}' "$WORK/events.log")" "$SPEED" "$K" <<'PY'
import sys
tools, dev_started, onset, submit, enter_t, end, speed, k = sys.argv[1], *map(float, sys.argv[2:])
# The device clip starts shortly after the screenrecord command was launched. The keyboard
# first appears about 0.15 s after the tap command returns, so pick the tap whose
# implied clip start is closest to the launch time.
taps = [float(l.split()[0]) for l in open(tools) if "input tap" in l]
dev_t0 = min((t + 0.15 - onset for t in taps), key=lambda c: abs(c - (dev_started + 0.4)))
# Terminal clip second T is real time submit + (T - enter_t) / k, and the device clip
# second for that real time is that minus dev_t0.
devoff = submit - dev_t0 - enter_t / k
end_t = enter_t + k * (end - submit)
a, b = enter_t + 2.0, end_t - 8.0
print(round(devoff, 3), round(end_t, 2),
      "0:%.2f:1 %.2f:%.2f:%s %.2f:%.2f:1" % (a, a, b, speed, b, end_t))
PY
)
  SEGMENTS="${SEGMENTS:-$AUTOSEG}"
  echo "terminal speed factor K=$K, device second = $DEVOFF + terminal second / K; story ends at $END s"
  echo "segments: $SEGMENTS"

  local fc="" tc="" dc="" i=0 s e sp
  for seg in $SEGMENTS; do
    IFS=: read -r s e sp <<<"$seg"
    fc+="[0:v]fps=20,trim=start=${s}:end=${e},setpts=(PTS-STARTPTS)/${sp},fps=${FPS:-10},scale=900:820[t$i];"
    fc+="[1:v]fps=20,trim=start=$(python3 -c "print($DEVOFF+$s/$K)"):end=$(python3 -c "print($DEVOFF+$e/$K)"),setpts=(PTS-STARTPTS)/($sp/$K),fps=${FPS:-10},scale=-2:820[d$i];"
    tc+="[t$i]"; dc+="[d$i]"; i=$((i+1))
  done
  fc+="${tc}concat=n=${i}:v=1:a=0,tpad=stop_mode=clone:stop_duration=${HOLD}[tv];${dc}concat=n=${i}:v=1:a=0,tpad=stop_mode=clone:stop_duration=${HOLD}[dv];"
  fc+="[tv]pad=iw+24:ih+48:24:24:color=0x1e1e2e[tp];[dv]pad=iw+48:ih+48:24:24:color=0x1e1e2e[dp];[tp][dp]hstack=inputs=2,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle"
  ffmpeg -loglevel error -y -i "$T" -i "$V" -filter_complex "$fc" "$WORK/demo-raw.gif"
  gifsicle -O3 --lossy=${LOSSY:-60} "$WORK/demo-raw.gif" -o "$REPO/docs/demo.gif"
  ls -la "$REPO/docs/demo.gif"
}

case "${1:-}" in
  capture) capture ;;
  compose) compose ;;
  *) echo "usage: $0 capture|compose"; exit 1 ;;
esac
