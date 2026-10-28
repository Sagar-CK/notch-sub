#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
target="$HOME/Applications/Notch Sub.app"
mkdir -p "$HOME/Applications"
for process in NotchSub SubTracker; do
  if pgrep -x "$process" >/dev/null; then pkill -x "$process"; fi
done
staging="$HOME/Applications/.Notch Sub.installing.app"
if [[ -e "$staging" ]]; then rm -rf "$staging"; fi
ditto "dist/Notch Sub.app" "$staging"
codesign --verify --deep --strict "$staging"
previous="$HOME/Applications/.Notch Sub.previous.app"
if [[ -e "$previous" ]]; then rm -rf "$previous"; fi
if [[ -e "$target" ]]; then mv "$target" "$previous"; fi
if ! mv "$staging" "$target"; then
  if [[ -e "$previous" ]]; then mv "$previous" "$target"; fi
  exit 1
fi
if [[ -e "$previous" ]]; then rm -rf "$previous"; fi
# Sub Tracker was renamed. Notch Sub moves its accounts and settings over on launch.
legacy="$HOME/Applications/Sub Tracker.app"
if [[ -e "$legacy" ]]; then rm -rf "$legacy"; fi
open "$target" --args --show
print "Installed $target"
