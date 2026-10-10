#!/bin/sh
# Downloads the prebuilt monero_c wallet library and checks every file against
# a pinned SHA-256. Run from the repo root:
#   sh tool/fetch_monero_c.sh
# In Git Bash on Windows it fetches the Windows DLLs into windows/monero_c/ for
# the app and the tests.
# On Linux (CI and cloud sessions) it fetches the Linux library from the same
# bundle into the same folder, for the tests only: run them with
#   LD_LIBRARY_PATH="$PWD/windows/monero_c" flutter test
# On a Mac (and in the iOS build workflow) it fetches the iPhone and iOS
# simulator libraries into ios/monero_c/ and packs them as
# ios/MoneroWallet.xcframework, which the Xcode project embeds in the app.
set -eu

# monero_c v0.18.4.6-RC2 = commit 3bfb3856a838f2bf6b729501837bb0295dedf25d.
# The `monero` git ref in pubspec.yaml must stay on the same commit.
BUNDLE_URL=https://github.com/MrCyjaneK/monero_c/releases/download/v0.18.4.6-RC2/release-bundle.zip
BUNDLE_SHA256=94ae3d99f878d1e392b9c49d4c5431e4d0b7780c6177081df5369d05e68cea70
DLL_IN_BUNDLE=v0.18.4.6-RC2/x86_64-w64-mingw32/libmonero_wallet2_api_c.dll
DLL_SHA256=2ed601431b159c94ebf096842348800402ee3085f8a1872ca05d15fa0c65d18a
SO_IN_BUNDLE=v0.18.4.6-RC2/x86_64-linux-gnu/libmonero_wallet2_api_c.so
SO_SHA256=6afe4a953cb704e3bc607f3796b62328e41c20caa705f1adbef7052f7453e912
IOS_IN_BUNDLE=v0.18.4.6-RC2/aarch64-apple-ios/libmonero_wallet2_api_c.dylib
IOS_SHA256=5eb316bfbbeb3f29714387339b2cd6124260a5e86ad0e9dc09887266b897e38a
# Simulators on Apple silicon Macs. The bundle has no Intel simulator build, so
# the Xcode project leaves x86_64 out of simulator builds (ios/Flutter/*.xcconfig).
SIM_IN_BUNDLE=v0.18.4.6-RC2/aarch64-apple-ios-simulator/libmonero_wallet2_api_c.dylib
SIM_SHA256=b34e2497befe3b1b6d3a7671486565d04979ab97e903fcc81cb9cd804533d4b5

# The DLL links to the MinGW thread runtime (libwinpthread-1.dll), which the
# monero_c bundle leaves out. monero_c builds with GCC 15.2.0 and MinGW-w64
# 13.0.0 (UCRT), so take the runtime from the WinLibs build of that same pair.
WINLIBS_URL=https://github.com/brechtsanders/winlibs_mingw/releases/download/15.2.0posix-13.0.0-ucrt-r6/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r6.zip
WINLIBS_SHA256=9f3ee66dd11f1c40a85850976ab9a740469cd3bc43a234a2e9f91c04c92c4f57
PTHREAD_IN_WINLIBS=mingw64/bin/libwinpthread-1.dll
PTHREAD_SHA256=e7279cf189a0d4f056371a7054864315e3483f049c11f3c4e9f283010fd77530

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# macOS has shasum but not always sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
  ok() { echo "$1  $2" | sha256sum -c - >/dev/null 2>&1; }
else
  ok() { echo "$1  $2" | shasum -a 256 -c - >/dev/null 2>&1; }
fi

# fetch <zip url> <zip sha256> <path inside zip> <file sha256> <folder>
fetch() {
  file=$5/$(basename "$3")
  ok "$4" "$file" && return
  zip=$tmp/$(basename "$1")
  if [ ! -f "$zip" ]; then # each archive is downloaded once per run
    echo "Downloading $(basename "$1") for $(basename "$3")..."
    curl -fsSL --retry 3 -o "$zip" "$1"
    ok "$2" "$zip" || { echo "checksum mismatch: $1" >&2; exit 1; }
  fi
  mkdir -p "$5"
  unzip -q -j -o "$zip" "$3" -d "$5"
  ok "$4" "$file" || { rm -f "$file"; echo "checksum mismatch: $file" >&2; exit 1; }
}

# monero.dart opens the library on iOS as MoneroWallet.framework/MoneroWallet.
# So each build is wrapped in a framework of that name, with the install name
# that goes with it (the app links it through @rpath), and both go into one
# xcframework, from which Xcode takes the iPhone or the simulator build.
pack_xcframework() {
  set --
  for sdk in iphoneos iphonesimulator; do
    # The minimum iOS version each library was built for.
    case $sdk in
      iphoneos) platform=iPhoneOS min=12.0 ;;
      iphonesimulator) platform=iPhoneSimulator min=14.0 ;;
    esac
    fw=$tmp/$sdk/MoneroWallet.framework
    mkdir -p "$fw"
    cp "ios/monero_c/$sdk/libmonero_wallet2_api_c.dylib" "$fw/MoneroWallet"
    install_name_tool -id @rpath/MoneroWallet.framework/MoneroWallet "$fw/MoneroWallet"
    # The new install name voids the ad-hoc signature the simulator needs.
    # A signed build signs it again with the app's identity when it embeds it.
    codesign --force --sign - "$fw/MoneroWallet"
    cat > "$fw/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MoneroWallet</string>
  <key>CFBundleIdentifier</key>
  <string>com.github.mrcyjanek.monero-c</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MoneroWallet</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>0.18.4</string>
  <key>CFBundleVersion</key>
  <string>0.18.4</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>$platform</string>
  </array>
  <key>MinimumOSVersion</key>
  <string>$min</string>
</dict>
</plist>
EOF
    # Apple's privacy manifest for the library: each framework in an app that
    # calls an API Apple asks reasons for needs its own (the app's covers only
    # the app). The library tracks nobody and collects nothing. Its reasons:
    # - File timestamps (stat, fstat, lstat), C617.1: boost::filesystem and
    #   the wallet's logging look at the wallet's own files, in the app's
    #   container.
    # - System boot time (mach_absolute_time), 35F9.1: boost's steady clock
    #   times timeouts and waits inside the app.
    # - Disk space (statfs), E174.1: before the ring database grows, LMDB checks
    #   there is room for it, and refuses to grow it if there isn't.
    # The iOS build workflow checks these against the library's symbols
    # (tool/check_privacy_manifests.sh).
    cat > "$fw/PrivacyInfo.xcprivacy" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>C617.1</string>
      </array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>35F9.1</string>
      </array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>E174.1</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF
    set -- "$@" -framework "$fw"
  done
  rm -rf ios/MoneroWallet.xcframework
  xcodebuild -create-xcframework "$@" -output ios/MoneroWallet.xcframework >/dev/null
}

case "$(uname -s)" in
  Linux)
    out=windows/monero_c
    fetch "$BUNDLE_URL" "$BUNDLE_SHA256" "$SO_IN_BUNDLE" "$SO_SHA256" "$out"
    ;;
  Darwin)
    fetch "$BUNDLE_URL" "$BUNDLE_SHA256" "$IOS_IN_BUNDLE" "$IOS_SHA256" ios/monero_c/iphoneos
    fetch "$BUNDLE_URL" "$BUNDLE_SHA256" "$SIM_IN_BUNDLE" "$SIM_SHA256" ios/monero_c/iphonesimulator
    out=ios/MoneroWallet.xcframework
    pack_xcframework
    ;;
  *)
    out=windows/monero_c
    fetch "$BUNDLE_URL" "$BUNDLE_SHA256" "$DLL_IN_BUNDLE" "$DLL_SHA256" "$out"
    fetch "$WINLIBS_URL" "$WINLIBS_SHA256" "$PTHREAD_IN_WINLIBS" "$PTHREAD_SHA256" "$out"
    ;;
esac

echo "monero_c is ready in $out"
