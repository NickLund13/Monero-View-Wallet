#!/bin/sh
# Checks a release APK of the app, for the Android build workflow
# (.github/workflows/android-build.yml):
#   sh tool/check_android_apk.sh build/app/outputs/flutter-apk/app-release.apk
# Needs the Android SDK's build tools (ANDROID_HOME), unzip and readelf.
#
# - The wallet library is in the app for each kind of processor.
# - Its native libraries work on phones with 16 KB memory pages, which Google
#   Play asks of every app: aligned so in the APK and in their own headers.
# - The app asks for no permission but the internet, and Android may not back
#   it up or move its files to a new phone.
set -eu

apk=$1
tools=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n 1)
failed=

for abi in arm64-v8a armeabi-v7a x86_64; do
  for lib in libmonero_wallet2_api_c.so libflutter.so libapp.so; do
    if ! unzip -l "$apk" "lib/$abi/$lib" > /dev/null; then
      echo "::error::lib/$abi/$lib isn't in the app."
      failed=1
    fi
  done
done

# Stored uncompressed, at 16 KB boundaries in the APK.
if ! "$tools/zipalign" -c -P 16 4 "$apk"; then
  echo "::error::The APK isn't aligned for 16 KB pages."
  failed=1
fi
# Each 64-bit library's segments loaded at 16 KB boundaries or more.
libs=$(mktemp -d)
unzip -q "$apk" 'lib/arm64-v8a/*' 'lib/x86_64/*' -d "$libs"
for lib in "$libs"/lib/*/*.so; do
  for align in $(readelf -lW "$lib" | awk '$1 == "LOAD" { print $NF }'); do
    if [ $((align)) -lt 16384 ]; then
      echo "::error::${lib#"$libs"/} has a segment aligned to $align, below 16 KB."
      failed=1
    fi
  done
done
rm -rf "$libs"

# The permissions the app asks for. Android's support library adds one of its
# own, which only this app holds, so that its broadcasts stay inside the app.
permissions=$("$tools/aapt2" dump permissions "$apk" |
  sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" | sort)
echo "Permissions:"
echo "$permissions"
for permission in $permissions; do
  case "$permission" in
    android.permission.INTERNET) ;;
    com.example.monero_view_wallet.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) ;;
    *)
      echo "::error::The app asks for $permission."
      failed=1
      ;;
  esac
done

manifest=$("$tools/aapt2" dump xmltree --file AndroidManifest.xml "$apk")
if ! echo "$manifest" | grep -q 'A: http://schemas.android.com/apk/res/android:allowBackup(0x[0-9a-f]*)=false'; then
  echo "::error::The manifest doesn't turn backups off."
  failed=1
fi
if ! echo "$manifest" | grep -q 'android:dataExtractionRules'; then
  echo "::error::The manifest has no data extraction rules."
  failed=1
fi
[ -z "$failed" ] || echo "$manifest"

[ -z "$failed" ]
