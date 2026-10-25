#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
target="$HOME/Applications/Sub Tracker.app"
mkdir -p "$HOME/Applications"
if pgrep -x SubTracker >/dev/null; then pkill -x SubTracker; fi
staging="$HOME/Applications/.Sub Tracker.installing.app"
if [[ -e "$staging" ]]; then rm -rf "$staging"; fi
ditto "dist/Sub Tracker.app" "$staging"
codesign --verify --deep --strict "$staging"
previous="$HOME/Applications/.Sub Tracker.previous.app"
if [[ -e "$previous" ]]; then rm -rf "$previous"; fi
if [[ -e "$target" ]]; then mv "$target" "$previous"; fi
if ! mv "$staging" "$target"; then
  if [[ -e "$previous" ]]; then mv "$previous" "$target"; fi
  exit 1
fi
if [[ -e "$previous" ]]; then rm -rf "$previous"; fi
open "$target" --args --show
print "Installed $target"
