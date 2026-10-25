# Sub Tracker

AI subscription usage at your Mac's notch or in the menu bar.

[Download](https://github.com/Sagar-CK/sub-tracker/releases) · [Build from source](#build-from-source) · [Provider setup](docs/ACCOUNTS.md)

<p align="center">
  <img src="docs/images/usage-dark.png" alt="Dark usage panel with demo accounts" width="46%">
  <img src="docs/images/usage-light.png" alt="Light usage panel with demo accounts" width="46%">
</p>

- Remaining allowance, reset times, credits, and reported weekly spend.
- Local account discovery. Only verified accounts appear.
- Compact percentages that cycle or stay pinned to one provider.
- Local account switching for Codex, Claude Code, and configured Z.ai keys.
- Native SwiftUI and AppKit. No backend, analytics, or runtime dependencies.

## Install

Requires **macOS 14+**. Universal downloads support Apple Silicon and Intel.

1. Download the DMG from [Releases](https://github.com/Sagar-CK/sub-tracker/releases).
2. Drag **Sub Tracker** into **Applications** and open it.
3. Sign in through your provider's client, or use **Settings → Add account**.

Downloads are **ad-hoc signed, not Apple-notarized**. If macOS blocks a preview, build from source or follow [Apple's guidance for trusted apps](https://support.apple.com/en-us/102445). SHA-256 checksums accompany each release.

To update, quit the app and replace it. Your account data stays on your Mac.

## Use

| Action | Control |
| --- | --- |
| Show all accounts | Hover over the notch for 300 ms or click it |
| Keep the panel open | Click the notch |
| Close the panel | Move away, or click outside / press Escape if pinned |
| Choose placement | Settings → Placement: Notch, Menu bar, or Both |
| Choose the compact reading | Settings → Notch display: Cycle or a provider |

Cycle changes providers every four seconds. The percentage is the active account's lowest remaining allowance. Stale and unknown readings stay hidden. Macs without a notch use the menu bar. Reduce Motion is supported.

## Providers

| Validation | Providers |
| --- | --- |
| Checked with live accounts | Codex / ChatGPT, Claude Code, Cursor |
| Fixture-tested, needs live validation | Z.ai / BigModel, Gemini, Antigravity, GitHub Copilot, Kimi, MiniMax, Kiro, OpenCode Go |
| Not displayed yet | Devin / Windsurf: cache parsing exists, but live authentication is not verified |

This is an early preview. Provider endpoints can change. Some plans do not expose a remaining allowance.

[Provider setup and limitations](docs/ACCOUNTS.md) covers supported sign-ins, regions, and switching. Claude Desktop and ZCode manage their own sign-ins. Monthly bills and estimated costs are not shown.

## Build from source

Requires **Swift 6** from Xcode or Command Line Tools. Run `xcode-select --install` if needed.

```sh
git clone https://github.com/Sagar-CK/sub-tracker.git
cd sub-tracker
./scripts/install.sh
```

Installs `~/Applications/Sub Tracker.app` without administrator access.

```sh
swift run SubTracker --demo --window   # Sample data, no provider requests
./scripts/check.sh                     # Checks, build, and signature verification
./scripts/package.sh --universal       # App, DMG, ZIP, and checksums in dist/
```

See [Contributing](CONTRIBUTING.md) and [Releasing](docs/RELEASING.md).

## Privacy and license

Credentials remain local in provider files or macOS Keychain. Usage requests go directly to providers. Antigravity uses its installed CLI. The app does not require Screen Recording or Accessibility access.

[Security and data handling](SECURITY.md) · [MIT license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)

Notch interaction is inspired by [Boring Notch](https://github.com/TheBoredTeam/boring.notch). Sub Tracker is independent of the supported providers.
