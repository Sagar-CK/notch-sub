#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift scripts/check-docs.swift
swift run NotchSubChecks
./scripts/build.sh
codesign --verify --deep --strict "dist/Notch Sub.app"
plutil -lint "dist/Notch Sub.app/Contents/Info.plist"
git diff --check
