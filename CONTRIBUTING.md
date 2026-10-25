# Contributing

Sub Tracker is a small native macOS app. Keep changes focused and preserve the quiet UI: provider marks, account names, usage, and controls. Put explanations in tooltips or documentation.

## Run locally

Use macOS 14 or later with Swift 6 Command Line Tools or Xcode:

```sh
swift run SubTracker --demo --window
swift run SubTrackerChecks
./scripts/build.sh
```

Demo mode uses sample accounts. It makes no provider requests, reads no account cache, and cannot save or switch credentials. Normal mode discovers local credentials and calls provider usage APIs.

Before submitting:

1. Run `./scripts/check.sh`.
2. Check light and dark appearance, narrow windows, and Settings.
3. For account or usage changes, add a regression fixture under `Tests/SubTrackerCoreTests`. Use synthetic credentials and temporary homes only.
4. Describe the resulting behavior and how you checked it. Include demo screenshots for visible changes.

## Layout

- `Sources/SubTrackerCore`: discovery, parsing, network requests, Keychain storage, and account switching.
- `Sources/SubTrackerApp`: SwiftUI views, AppKit windows, refresh state, and notch placement.
- `Tests/SubTrackerCoreTests`: dependency-free executable checks, also runnable without XCTest.
- `scripts`: build, install, verification, and release packaging.
- `docs/images`: public product screenshots with sample accounts.

Format Swift with `xcrun swift-format format --in-place --recursive Sources Tests Package.swift`. Avoid new dependencies unless they solve a concrete need.

## Provider integrations

Keep credential-bearing requests on an explicit HTTPS allowlist and reject redirects. Never log headers, tokens, authentication files, or response bodies. Unknown usage must remain unknown. Credits, quota percentages, monthly usage, and weekly monetary spend are distinct values.

Preserve refreshed outgoing credentials before switching. Do not automatically migrate running sessions, rotate refresh tokens, or alter another app's settings during discovery. Document which client a switch affects.

Do not attach real account screenshots, API keys, `auth.json`, `.credentials.json`, Keychain exports, or app-support backups to issues or pull requests. See [SECURITY.md](SECURITY.md) for reporting sensitive problems.

Contributions are licensed under the project's [MIT license](LICENSE). Third-party provider marks retain their own ownership and license notices.
