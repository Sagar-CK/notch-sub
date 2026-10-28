#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
skip_build=false
universal=false
for argument in "$@"; do
  case "$argument" in
    --skip-build) skip_build=true ;;
    --universal) universal=true ;;
    --help|-h) print 'Usage: ./scripts/package.sh [--universal] [--skip-build]'; exit 0 ;;
    *) print -u2 "Unknown option: $argument"; exit 1 ;;
  esac
done
if ! $skip_build; then
  if $universal; then ./scripts/build.sh --universal; else ./scripts/build.sh; fi
fi
app="$PWD/dist/Notch Sub.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
architectures=$(xcrun lipo -archs "$app/Contents/MacOS/NotchSub")
if [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]; then
  architecture=universal
elif $universal; then
  print -u2 'The existing app is not universal. Run ./scripts/package.sh --universal without --skip-build.'
  exit 1
else
  architecture="$architectures"
fi
name="Notch-Sub-${version}-macOS-${architecture}"
staging=$(mktemp -d "${TMPDIR:-/tmp}/notchsub-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Notch Sub.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Read Me.txt" <<'README'
Notch Sub

Drag Notch Sub.app into Applications, then open it from Applications.
Requires macOS 14 or later. Sign in to your AI provider's CLI first;
Notch Sub detects local accounts. Add subscription keys in Settings.

This preview is ad-hoc signed and is not Apple-notarized. macOS may
block the first launch. Build from the public source if you prefer,
or review Apple's guidance before allowing a downloaded app:
https://support.apple.com/en-us/102445

Source, instructions, and license:
https://github.com/Sagar-CK/notch-sub

To update, quit the old app before replacing it. Account data stays
on your Mac and is not included in this installer. Coming from
Sub Tracker? Quit and delete it. Accounts move over on first launch.

Notch Sub opens at login by default. Change this in Settings.
README
cd dist
ditto -c -k --sequesterRsrc --keepParent "Notch Sub.app" "${name}.zip"
hdiutil create -quiet -volname 'Notch Sub' -srcfolder "$staging" -format UDZO -fs HFS+ -ov "${name}.dmg"
hdiutil verify -quiet "${name}.dmg"
shasum -a 256 "${name}.zip" "${name}.dmg" > SHA256SUMS.txt
print "Packaged $PWD/${name}.dmg"
print "Packaged $PWD/${name}.zip"
