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
# The emulator's screen lock while the lock is tried: a made-up PIN on a
# throwaway emulator.
pin=1234

adb install -r "$apk"
adb logcat -c
# The screen stays on, so the emulator doesn't lock itself once it has a PIN.
adb shell svc power stayon true
adb shell am start -W -n "$package/.MainActivity"

# The smoke test's report so far, from the emulator's log.
report() {
  adb logcat -d -s flutter:I | sed -n 's/.*android_smoke: //p'
}

# Waits up to 3 minutes for the first frame.
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

# Recents never shows a picture of the app. Android 13 and later leave it out
# when the app asks, which their dumpsys doesn't show; before that the app's
# window is a secure one. Its flags are on the line after mAttrs=.
if [ "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" -lt 33 ]; then
  attributes=$(adb shell dumpsys window windows |
    grep -A 40 "Window{[^}]*$package/[^}]*MainActivity}" |
    grep -m 1 -A 3 'mAttrs=' || true)
  case "$(echo "$attributes" | grep -m 1 ' fl=')" in
    *SECURE*) ;;
    *)
      echo "::error::Recents may show a picture of the app: its window isn't secure."
      echo "$attributes"
      failed=1
      ;;
  esac
fi

# The lock with a screen lock: once a PIN is set, the app asks for it with
# Android's own prompt, and the PIN typed there unlocks it.
adb shell locksettings set-pin "$pin"
for _ in $(seq 90); do
  case "$(report)" in *'screen lock: '*) break ;; esac
  sleep 2
done
for _ in $(seq 10); do
  sleep 3
  if report | grep '^screen lock: ' | grep -qv '^screen lock: asking$'; then
    break
  fi
  adb shell input text "$pin"
  adb shell input keyevent KEYCODE_ENTER
done
adb shell locksettings clear --old "$pin" || true

# Started again, the app deletes the copy of a key images file the first start
# left behind. It draws nothing then, so there is no first frame to wait for.
adb shell am force-stop "$package"
adb shell am start -n "$package/.MainActivity"
for _ in $(seq 30); do
  case "$(report)" in *'copy left behind: '*) break ;; esac
  sleep 2
done

report=$(report)
echo "$report"

expected=$(printf '%s\n' 'wallet library: ok' 'folder: ok' 'keystore: ok' \
  'saved wallet: ok' 'no tor: ok' 'key images file: ok' 'lock: ok' \
  'first frame: ok' 'screen lock: asking' 'screen lock: ok' \
  'copy left behind: ok')
if [ "$(echo "$report" | grep -v '^file: ')" != "$expected" ]; then
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
