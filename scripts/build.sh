#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
universal=false
case "${1:-}" in
  --universal) universal=true ;;
  --help|-h) print 'Usage: ./scripts/build.sh [--universal]'; exit 0 ;;
  '') ;;
  *) print -u2 "Unknown option: $1"; exit 1 ;;
esac
if [[ "$(uname -s)" != Darwin ]]; then
  print -u2 'Sub Tracker requires macOS 14 or later.'
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  print -u2 'Install Apple Command Line Tools with xcode-select --install, then run this again.'
  exit 1
fi
toolchain=$(xcrun swift --version)
if [[ ! "$toolchain" =~ 'Swift version ([0-9]+)' ]] || (( match[1] < 6 )); then
  print -u2 'Swift 6 or later is required. Update Command Line Tools or select an Xcode 16+ toolchain.'
  exit 1
fi
version="$(<VERSION)"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 'VERSION must contain a numeric major.minor.patch version.'
  exit 1
fi
binaries=()
if $universal; then
  for architecture in arm64 x86_64; do
    swift build -c release --product SubTracker --triple "${architecture}-apple-macosx14.0"
    binary_dir=$(swift build -c release --show-bin-path --triple "${architecture}-apple-macosx14.0")
    binaries+=("$binary_dir/SubTracker")
  done
else
  swift build -c release --product SubTracker
  binary_dir=$(swift build -c release --show-bin-path)
  binaries+=("$binary_dir/SubTracker")
fi
app="$PWD/dist/Sub Tracker.app"
if [[ -d "$app" ]]; then rm -rf "$app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if $universal; then
  xcrun lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/SubTracker"
  xcrun lipo "$app/Contents/MacOS/SubTracker" -verify_arch arm64 x86_64
else
  cp "${binaries[1]}" "$app/Contents/MacOS/SubTracker"
fi
for bundle in "$binary_dir"/*.bundle; do
  cp "$bundle"/* "$app/Contents/Resources/"
done
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Sub Tracker</string>
<key>CFBundleDisplayName</key><string>Sub Tracker</string>
<key>CFBundleIdentifier</key><string>com.sagar.subtracker</string>
<key>CFBundleExecutable</key><string>SubTracker</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" "$app/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp assets/AppIcon.icns "$app/Contents/Resources/"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
print "Built $app"
