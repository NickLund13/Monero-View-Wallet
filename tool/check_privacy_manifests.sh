#!/bin/sh
# Checks Apple's privacy manifests against the built iPhone app. Apple asks a
# reason for some APIs (its "required reason APIs"). Each executable in the
# app that calls one must declare it in the manifest of its own bundle: the
# app's for the Runner executable, each framework's for that framework. App
# Store Connect rejects an upload that misses one (ITMS-91053). Each manifest
# must also say the app tracks nobody and collects nothing.
#
# Runs on a Mac after `flutter build ipa` (the iOS build workflow):
#   sh tool/check_privacy_manifests.sh build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
set -eu

app=$1
fail=0

# Prints the categories of the required reason APIs that $1 calls, one per
# line. The symbols are Apple's list for each category:
# https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
# Fails if it can't read $1, so an unreadable executable never passes as one
# that calls none.
used_categories() {
  symbols=$(nm -u "$1") || return 1
  names=$(strings -a "$1") || return 1
  {
    printf '%s\n' "$symbols" | awk '{ print $NF }' | while read -r symbol; do
      case $symbol in
        _stat | _fstat | _fstatat | _lstat | _getattrlistbulk | \
          _NSFileCreationDate | _NSFileModificationDate | \
          _NSURLContentModificationDateKey | _NSURLCreationDateKey)
          echo FileTimestamp ;;
        _getattrlist | _fgetattrlist | _getattrlistat)
          echo FileTimestamp
          echo DiskSpace ;;
        _statfs | _statvfs | _fstatfs | _fstatvfs | \
          _NSFileSystemFreeSize | _NSFileSystemSize | _NSURLVolume*Capacity*Key)
          echo DiskSpace ;;
        _mach_absolute_time) echo SystemBootTime ;;
        '_OBJC_CLASS_$_NSUserDefaults' | _CFPreferences*) echo UserDefaults ;;
      esac
    done
    # Objective-C methods are called by name, so look for the names.
    if echo "$names" | grep -qx systemUptime; then echo SystemBootTime; fi
    if echo "$names" | grep -qx activeInputModes; then echo ActiveKeyboards; fi
  } | sort -u
}

# check <executable> <its bundle's manifest>
check() {
  name=${1#"$app"/}
  if ! used=$(used_categories "$1"); then
    echo "::error::$name couldn't be read to find the APIs it calls."
    fail=1
    return
  fi
  if [ ! -f "$2" ]; then
    if [ -n "$used" ]; then
      echo "::error::$name calls APIs Apple asks reasons for ($(echo $used)), but its bundle has no privacy manifest."
      fail=1
    else
      echo "$name: no required reason APIs, no manifest needed"
    fi
    return
  fi
  if ! plutil -lint -s "$2"; then
    echo "::error::${2#"$app"/} isn't a valid property list."
    fail=1
    return
  fi
  if [ "$(plutil -extract NSPrivacyTracking raw -o - "$2")" != false ] ||
    [ "$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$2")" != '[]' ]; then
    echo "::error::${2#"$app"/} must say the app tracks nobody and collects nothing."
    fail=1
  fi
  declared=$(plutil -extract NSPrivacyAccessedAPITypes json -o - "$2" |
    jq -r '.[] | select(.NSPrivacyAccessedAPITypeReasons | length > 0) | .NSPrivacyAccessedAPIType' |
    sed 's/^NSPrivacyAccessedAPICategory//' | sort -u)
  echo "$name: calls [$(echo $used)], declares [$(echo $declared)]"
  for category in $used; do
    if ! echo "$declared" | grep -qx "$category"; then
      echo "::error::$name calls $category APIs, which ${2#"$app"/} doesn't declare with a reason."
      fail=1
    fi
  done
}

check "$app/Runner" "$app/PrivacyInfo.xcprivacy"
for framework in "$app"/Frameworks/*.framework; do
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist")
  check "$framework/$executable" "$framework/PrivacyInfo.xcprivacy"
done

exit "$fail"
