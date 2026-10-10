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

# Waits up to 3 minutes for the first frame, the smoke test's last line.
report=
for _ in $(seq 90); do
  report=$(adb logcat -d -s flutter:I | sed -n 's/.*android_smoke: //p')
  case "$report" in *'first frame:'*) break ;; esac
  sleep 2
done
echo "$report"

failed=
expected=$(printf '%s\n' 'wallet library: ok' 'folder: ok' 'keystore: ok' \
  'saved wallet: ok' 'no tor: ok' 'first frame: ok')
if [ "$(echo "$report" | grep -v '^file: ')" != "$expected" ]; then
  echo "::error::The smoke test failed on the Android emulator."
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
