# Contributing

Use macOS 14+ and Swift 6. Keep changes focused and avoid new dependencies unless needed.

## Run and check

```sh
swift run NotchSub --demo --window
swift run NotchSub --demo --settings
./scripts/check.sh
```

Demo mode uses synthetic accounts and makes no provider requests or credential changes.

Before opening a pull request:

- Run the checks. Add synthetic fixtures for discovery, usage, or switching changes.
- Check light and dark appearance, Settings, and both placement modes.
- Include demo screenshots for UI changes.
- Describe the problem, resulting behavior, and validation.

## Code and copy

- Use two-space Swift indentation. Format with `swift format format --in-place --recursive Sources Tests Package.swift`.
- Keep labels short. Avoid taglines, repeated labels, secondary descriptions, and em dashes.
- Preserve unknown usage. Do not infer money, quota limits, or paid plans.
- Keep credential-bearing requests on the HTTPS allowlist and reject redirects.
- Never log credentials, headers, authentication files, or provider response bodies.
- Keep discovery read-only. Document which client an account switch changes.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/NotchSubCore` | Accounts, provider requests, parsing, storage, switching |
| `Sources/NotchSubApp` | SwiftUI views, AppKit windows, refresh state |
| `Tests/NotchSubCoreTests` | Checks using temporary homes and synthetic credentials |
| `scripts` | Build, install, validation, packaging |
| `docs` | Provider setup, release instructions, demo images |

Use [private vulnerability reporting](https://github.com/Sagar-CK/notch-sub/security/advisories/new) for security issues. Never attach real sign-ins or account screenshots to public reports.

Contributions use the [MIT license](LICENSE). Provider marks retain their own ownership notices.
