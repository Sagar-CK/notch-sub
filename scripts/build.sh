#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --product SubTracker
binary_dir=$(swift build -c release --show-bin-path)
app="$PWD/dist/Sub Tracker.app"
if [[ -d "$app" ]]; then rm -rf "$app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/SubTracker" "$app/Contents/MacOS/SubTracker"
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
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
print "Built $app"
