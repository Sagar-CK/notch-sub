#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift scripts/check-docs.swift
swift run SubTrackerChecks
./scripts/build.sh
codesign --verify --deep --strict "dist/Sub Tracker.app"
plutil -lint "dist/Sub Tracker.app/Contents/Info.plist"
git diff --check
