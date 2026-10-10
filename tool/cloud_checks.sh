#!/bin/sh
# Runs the pull request checks without GitHub Actions, on Linux: the secret and
# wallet file scan and the dependency scan of .github/workflows/security.yml,
# and the analyzer and offline tests of .github/workflows/app-tests.yml, with
# the same pinned, checksum-verified tools. It is for cloud sessions while
# GitHub Actions cannot start jobs (see CLAUDE.md). The Claude review is not
# part of it: a separate Claude session does that.
#
# Run from the repo root, on a clean checkout of the commit to check, with full
# history (the secret scan reads every commit, as in CI):
#   sh tool/cloud_checks.sh
# It prints one line per check and exits non-zero if any failed. The tools are
# kept in ~/.cache/mvw-checks (or $MVW_TOOLS), outside the repository.
#
# Two differences from CI, because cloud sessions cannot reach every host:
# - The dependency scan checks against OSV's downloadable database (the same
#   data, from storage.googleapis.com) instead of asking api.osv.dev.
# - If tool/fetch_tor.sh can't download tor (archive.torproject.org is
#   blocked), the one test that runs the real tor program skips itself, and
#   the summary says so with fetch_tor.sh's last line. CI would fail instead,
#   so CLAUDE.md makes a change to the app's Tor wait for CI then. A checksum
#   mismatch fails the check, as in CI.
set -eu

# The same versions and checksums as .github/workflows/security.yml and
# .github/actions/flutter-setup/action.yml; the script stops if they differ.
GITLEAKS_VERSION=8.30.1
GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
OSV_VERSION=2.6.0
OSV_SHA256=ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108
FLUTTER_VERSION=3.47.6
FLUTTER_SHA256=f1631b9c2c8b3529323db412b0d1beacf4a748f8783b0d7cf599a8fd5f461675

die() {
  echo "cloud_checks: $*" >&2
  exit 1
}

for pin in "VERSION: $GITLEAKS_VERSION" "$GITLEAKS_SHA256" "VERSION: $OSV_VERSION" "$OSV_SHA256"; do
  grep -qF "$pin" .github/workflows/security.yml || die "$pin is not what security.yml pins; update this script to match."
done
for pin in "VERSION: $FLUTTER_VERSION" "$FLUTTER_SHA256"; do
  grep -qF "$pin" .github/actions/flutter-setup/action.yml || die "$pin is not what flutter-setup pins; update this script to match."
done
[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || die "runs on x86_64 Linux only, like the CI jobs."
[ -z "$(git status --porcelain)" ] || die "uncommitted or untracked files: commit or remove them first, so the checks match the commit."
[ "$(git rev-parse --is-shallow-repository)" = false ] || die "shallow clone: run git fetch --unshallow first, so the secret scan reads every commit."

tools=${MVW_TOOLS:-$HOME/.cache/mvw-checks}
mkdir -p "$tools"

# fetch URL SHA256 FILE: downloads URL to FILE only if it matches SHA256.
fetch() {
  curl -fsSLo "$3.part" "$1"
  echo "$2  $3.part" | sha256sum -c - >/dev/null || {
    rm -f "$3.part"
    die "checksum mismatch for $1"
  }
  mv "$3.part" "$3"
}

gitleaks_dir=$tools/gitleaks-$GITLEAKS_VERSION
if [ ! -x "$gitleaks_dir/gitleaks" ]; then
  mkdir -p "$gitleaks_dir"
  fetch "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    "$GITLEAKS_SHA256" "$tools/gitleaks.tar.gz"
  tar -xzf "$tools/gitleaks.tar.gz" -C "$gitleaks_dir" gitleaks
  rm "$tools/gitleaks.tar.gz"
fi

osv=$tools/osv-scanner-$OSV_VERSION
if [ ! -x "$osv" ]; then
  fetch "https://github.com/google/osv-scanner/releases/download/v$OSV_VERSION/osv-scanner_linux_amd64" "$OSV_SHA256" "$osv"
  chmod +x "$osv"
fi

flutter_dir=$tools/flutter-$FLUTTER_VERSION
if [ ! -x "$flutter_dir/flutter/bin/flutter" ]; then
  rm -rf "$flutter_dir"
  mkdir -p "$flutter_dir"
  fetch "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$FLUTTER_VERSION-stable.tar.xz" \
    "$FLUTTER_SHA256" "$tools/flutter.tar.xz"
  # --no-same-owner: as root, tar would keep the archive's owner, and git then
  # refuses the SDK's own repository.
  tar -xJf "$tools/flutter.tar.xz" -C "$flutter_dir" --no-same-owner
  rm "$tools/flutter.tar.xz"
fi

# As in CI: CI is set, and the node tests skip themselves for lack of a node.
export CI=true
unset MVW_STAGENET_NODE MVW_STAGENET_FAUCET MVW_CHECK_PUBLIC_NODES || true
export PATH="$gitleaks_dir:$flutter_dir/flutter/bin:$PATH"

results=
failed=0
check() {
  name=$1
  shift
  note=
  echo "== $name"
  if "$@"; then
    results="$results
pass  $name$note"
  else
    results="$results
FAIL  $name$note"
    failed=1
  fi
}

secrets() {
  sh .githooks/pre-commit
}

dependencies() {
  OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY=$tools/osv-db \
    "$osv" scan source --offline-vulnerabilities --download-offline-databases \
    --recursive --allow-no-lockfiles .
}

app() {
  flutter config --no-analytics >/dev/null &&
    dart --disable-analytics &&
    flutter pub get --enforce-lockfile &&
    sh tool/fetch_monero_c.sh || return 1
  # A download that fails (the usual 403 in the cloud) skips the tor test,
  # and the summary gives the reason. A checksum mismatch fails the check:
  # the file may have been tampered with, which CI would not let through.
  if tor_log=$(sh tool/fetch_tor.sh 2>&1); then
    printf '%s\n' "$tor_log"
  else
    printf '%s\n' "$tor_log"
    case $tor_log in
    *"checksum mismatch"*)
      note=" (tool/fetch_tor.sh found a checksum mismatch, see above)"
      return 1
      ;;
    esac
    note=" (tool/fetch_tor.sh failed: $(printf '%s\n' "$tor_log" | tail -n 1); the test that runs tor was skipped)"
  fi
  flutter analyze &&
    LD_LIBRARY_PATH="$PWD/windows/monero_c" flutter test
}

check "Secrets and wallet files" secrets
check "Dependency vulnerabilities" dependencies
check "Analyze and test" app

echo
echo "Checks of $(git rev-parse --short=7 HEAD):$results"
exit "$failed"
