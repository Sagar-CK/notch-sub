#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "${1:-}" != "--skip-build" ]]; then ./scripts/build.sh; fi
app="$PWD/dist/Sub Tracker.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(uname -m)
archive="Sub-Tracker-${version}-macOS-${architecture}.zip"
cd dist
ditto -c -k --sequesterRsrc --keepParent "Sub Tracker.app" "$archive"
shasum -a 256 "$archive" > "${archive}.sha256"
print "Packaged $PWD/$archive"
