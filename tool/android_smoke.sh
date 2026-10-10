#!/bin/sh
# Runs the smoke test (tool/android_smoke.dart, built as an APK) on a running
# Android emulator and checks what it reports, for the Android build workflow
# (.github/workflows/android-build.yml):
#   sh tool/android_smoke.sh <apk>
# The emulator has no Google apps or services, so this also shows the app
# needs none.
set -eu

apk=$1
package=com.example.monero_view_wallet

adb install -r "$apk"
adb logcat -c
adb shell am start -W -n "$package/.MainActivity"

# The smoke test's report so far, from the emulator's log.
report() {
  adb logcat -d -s flutter:I | sed -n 's/.*android_smoke: //p'
}

# Waits up to 3 minutes for the first frame, the smoke test's last line.
for _ in $(seq 90); do
  case "$(report)" in *'first frame:'*) break ;; esac
  sleep 2
done

# Android makes a new activity in the same process now and then (after a
# theme change, say). The app's Dart code must not start again then, as it
# would with a new Flutter engine: MainActivity.kt keeps the one it has.
failed=
pid=$(adb shell pidof "$package" || true)
adb shell am start -W --activity-clear-task -n "$package/.MainActivity"
sleep 5
if [ -z "$pid" ] || [ "$(adb shell pidof "$package" || true)" != "$pid" ]; then
  echo "::error::The app didn't keep running in the same process."
  failed=1
fi
if ! adb shell dumpsys activity activities |
  grep -q "ResumedActivity.*$package/.MainActivity"; then
  echo "::error::The app isn't showing after its activity was made anew."
  failed=1
fi

# The camera, allowed now as a person allows it at the first scan: the smoke
# test then shows Scan wallet QR, and the camera must be on while it shows
# and off again once it has gone.
adb shell pm grant "$package" android.permission.CAMERA
# How many of the emulator's cameras the app has open now: for each open
# camera, Android's camera service names the package that opened it. Newer
# Androids also keep the last session of a camera that has closed, after the
# line saying it is closed.
camera_clients() {
  adb shell dumpsys media.camera | tr -d '\r' | awk -v package="$package" '
    /Device [^ ]+ is (open|closed)/ {
      for (i = 1; i < NF; i++) if ($i == "Device") device = $(i + 1)
      if ($0 ~ /is closed/) closed[device] = 1
      opened = ($0 ~ /is open/)
      next
    }
    opened && /Client package:/ { if ($NF == package) mine[device] = 1; opened = 0 }
    END { n = 0; for (d in mine) if (!(d in closed)) n++; print n }'
}
camera_state() {
  adb shell dumpsys media.camera |
    grep -E 'is open|is closed|Client package' || true
}
# Waits up to 4 minutes for a line of the smoke test's report.
reported() {
  for _ in $(seq 120); do
    case "$(report)" in *"$1"*) return 0 ;; esac
    sleep 2
  done
  return 1
}
if reported 'camera view: shown'; then
  on=
  for _ in $(seq 20); do
    if [ "$(camera_clients)" -gt 0 ]; then on=1 && break; fi
    sleep 1
  done
  if [ -z "$on" ]; then
    echo "::error::The camera didn't turn on for Scan wallet QR."
    camera_state
    failed=1
  fi
fi
if reported 'camera view: gone'; then
  off=
  for _ in $(seq 20); do
    if [ "$(camera_clients)" -eq 0 ]; then off=1 && break; fi
    sleep 1
  done
  if [ -z "$off" ]; then
    echo "::error::The camera stayed on after Scan wallet QR went."
    camera_state
    failed=1
  fi
fi

report=$(report)
echo "$report"

expected=$(printf '%s\n' 'wallet library: ok' 'folder: ok' 'keystore: ok' \
  'saved wallet: ok' 'tor: ok' 'camera: ok' 'first frame: ok' \
  'camera view: shown' 'camera view: gone')
if [ "$(echo "$report" | grep -v '^file: \|^tor library: ')" != "$expected" ]; then
  echo "::error::The smoke test failed on the Android emulator."
  adb logcat -d -v brief -s flutter:I ActivityTaskManager:I || true
  adb logcat -d -t 200 '*:W' || true
  failed=1
fi

# Android must not back the app up: android:allowBackup="false" leaves
# ALLOW_BACKUP out of the package's flags.
flags=$(adb shell dumpsys package "$package" | grep -m1 ' flags=\[' || true)
echo "Package flags:$flags"
case "$flags" in
  *ALLOW_BACKUP*)
    echo "::error::Android may back the app up."
    failed=1
    ;;
esac

adb shell am force-stop "$package" || true
[ -z "$failed" ]
