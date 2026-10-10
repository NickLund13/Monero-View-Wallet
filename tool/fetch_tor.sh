#!/bin/sh
# Downloads the Tor Project's own tor program for the app's built-in Tor and
# checks every file against a pinned SHA-256. Run from the repo root:
#   sh tool/fetch_tor.sh
# In Git Bash on Windows it fetches tor.exe into windows/tor/, from where the
# Windows build puts it next to the app.
# On Linux (CI and cloud sessions) it fetches the Linux tor and the three
# libraries it loads into the same folder, for the tests only.
# On a Mac it fetches tor.xcframework into ios/: the same tor built as a
# library for iPhone, which the iPhone build links into the app.
set -eu

# Tor Expert Bundle 15.0.24, which holds tor 0.4.9.13, from the Tor Project's
# archive (dist.torproject.org only keeps the newest version). The checksums
# were pinned on 2026-10-09 after checking each archive's signature
# (<archive>.asc next to it) by the Tor Browser Developers signing key,
# EF6E 286D DA85 EA2A 4BA7 DE68 4E2C 6E87 9329 8290.
BASE=https://archive.torproject.org/tor-package-archive/torbrowser/15.0.24
WIN_ARCHIVE=tor-expert-bundle-windows-x86_64-15.0.24.tar.gz
WIN_ARCHIVE_SHA256=e9dc6ccc93cd6afa507193f4de284d6424233ff5102155cd2c94b259e8a22b65
WIN_TOR_SHA256=90bbdcafd586feea608a5e9b7d3959f4ee194f7770755cfde8fab240e9773ad1
LINUX_ARCHIVE=tor-expert-bundle-linux-x86_64-15.0.24.tar.gz
LINUX_ARCHIVE_SHA256=8e012ec6815d7899cb64011582e2dade88e74119c6661068a2a3252de0ccd7f2
LINUX_TOR_SHA256=74f5a47bfe0fc7f7c3ec2fe6c772ec6e52d4a9e9e9c95c7f274f5330e02a8813
LINUX_CRYPTO_SHA256=6ed9fc77689324da28567478e0ed226f4f450f71b47852088e9b0b9220eb0404
LINUX_SSL_SHA256=e95f55c73b63a4e25db7b9c74abdd35c42829ca1dc68f2fb17ae71c4d841381c
LINUX_EVENT_SHA256=b51ca562ec232785856c454ce4f3621d957f39d0db87919e237590b0331544ff

# For iPhone: Tor.framework 409.13.1 by the Guardian Project's iCepa team (the
# library Onion Browser uses), which builds the same tor 0.4.9.13 with
# OpenSSL 3.6.4, libevent 2.1.13 and liblzma 5.8.4 as static libraries. The
# checksum is the one Tor.framework's own Tor.podspec checks for this release.
IOS_URL=https://github.com/iCepa/Tor.framework/releases/download/v409.13.1/tor.xcframework.zip
IOS_SHA256=851174402abc8655273264f6b877a625648e52e6f9dd490b35e7cb94c2c924c6

out=windows/tor
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# macOS has shasum but not always sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
  ok() { echo "$1  $2" | sha256sum -c - >/dev/null 2>&1; }
else
  ok() { echo "$1  $2" | shasum -a 256 -c - >/dev/null 2>&1; }
fi

# fetch <archive> <archive sha256> <path inside archive> <file sha256>
fetch() {
  file=$out/$(basename "$3")
  ok "$4" "$file" && return
  archive=$tmp/$1
  if [ ! -f "$archive" ]; then # each archive is downloaded once per run
    echo "Downloading $1 for $(basename "$3")..."
    curl -fsSL --retry 3 -o "$archive" "$BASE/$1"
    ok "$2" "$archive" || { echo "checksum mismatch: $1" >&2; exit 1; }
  fi
  mkdir -p "$out"
  tar -xzOf "$archive" "$3" > "$file"
  ok "$4" "$file" || { rm -f "$file"; echo "checksum mismatch: $file" >&2; exit 1; }
}

case "$(uname -s)" in
  Darwin)
    out=ios/tor.xcframework
    # Remembers which archive it was unpacked from, so it is fetched once.
    if [ "$(cat "$out/.archive-sha256" 2>/dev/null)" != "$IOS_SHA256" ]; then
      echo "Downloading tor.xcframework..."
      curl -fsSL --retry 3 -o "$tmp/tor.zip" "$IOS_URL"
      ok "$IOS_SHA256" "$tmp/tor.zip" || { echo "checksum mismatch: tor.xcframework.zip" >&2; exit 1; }
      unzip -q "$tmp/tor.zip" -d "$tmp/unzipped"
      rm -rf "$out"
      mv "$tmp/unzipped/tor.xcframework" "$out"
      echo "$IOS_SHA256" > "$out/.archive-sha256"
    fi
    ;;
  Linux)
    fetch "$LINUX_ARCHIVE" "$LINUX_ARCHIVE_SHA256" tor/tor "$LINUX_TOR_SHA256"
    fetch "$LINUX_ARCHIVE" "$LINUX_ARCHIVE_SHA256" tor/libcrypto.so.3 "$LINUX_CRYPTO_SHA256"
    fetch "$LINUX_ARCHIVE" "$LINUX_ARCHIVE_SHA256" tor/libssl.so.3 "$LINUX_SSL_SHA256"
    fetch "$LINUX_ARCHIVE" "$LINUX_ARCHIVE_SHA256" tor/libevent-2.1.so.7 "$LINUX_EVENT_SHA256"
    chmod +x "$out/tor"
    ;;
  *)
    fetch "$WIN_ARCHIVE" "$WIN_ARCHIVE_SHA256" tor/tor.exe "$WIN_TOR_SHA256"
    ;;
esac

echo "Tor is ready in $out"
