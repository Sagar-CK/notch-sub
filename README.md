# Sub Tracker

A macOS app for Codex, Claude, Z.ai, Gemini, and Antigravity usage.

[Download the app](https://github.com/Sagar-CK/sub-tracker/releases) · [Build from source](#build-from-source) · [Contribute](CONTRIBUTING.md)

<p align="center">
  <img src="docs/images/usage-dark.png" alt="Dark appearance with Codex, Claude, and Z.ai usage" width="46%">
  <img src="docs/images/usage-light.png" alt="Light appearance with the same sample accounts" width="46%">
</p>

Choose Notch, Menu bar, or Both in Settings. Macs without a notch use the menu bar.

## Download and install

1. Open [Releases](https://github.com/Sagar-CK/sub-tracker/releases) and download the **universal DMG**.
2. Open the DMG and drag **Sub Tracker** into **Applications**.
3. Open Sub Tracker from Applications. Local CLI sign-ins are detected; connect a Z.ai Coding Plan key in Settings if needed.

Requires **macOS 14+**. The same download runs on Apple Silicon and Intel Macs. A ZIP containing the app is also available. No Xcode or Swift installation is needed for the download.

The app is an **unnotarized preview**. If macOS blocks it, you can build from source below or follow [Apple's guidance for opening trusted downloaded apps](https://support.apple.com/en-us/102445). The project does not disable Gatekeeper or remove quarantine. Checksums are included with each release.

To update, quit the app and replace it in Applications. Your local account data stays in place.

## Build from source

Requires **macOS 14+** and a **Swift 6** toolchain (Xcode or Command Line Tools).

If the developer tools are not installed, run `xcode-select --install` first. Check `swift --version`; it must report Swift 6 or later.

```sh
git clone https://github.com/Sagar-CK/sub-tracker.git
cd sub-tracker
./scripts/install.sh
```

Installs `~/Applications/Sub Tracker.app` without administrator access. Accounts and data stay on your Mac.

Click the provider readouts beside your camera cutout or the menu bar icon. Use the sliders button for Settings. Click outside or press Escape to collapse the usage panel.

<p align="center">
  <img src="docs/images/settings.png" alt="Settings with Notch selected, launch at login, and account controls" width="680">
</p>

## Provider support

| Provider | Usage | Switching |
| --- | --- | --- |
| Codex / ChatGPT | File-backed local accounts, provider windows, credits | Codex local sign-in files |
| Claude Code | Five-hour, weekly, and model-specific allowances | Saved Claude Code OAuth accounts |
| Z.ai / BigModel | Coding Plan quota through a connected key | Existing Z.ai configuration in Claude Code |
| Gemini | Code Assist model quotas through Gemini CLI OAuth | Managed in Gemini CLI |
| Antigravity | Reported model-group allowances and reset times through `agy` 1.1.11+ | Managed in Antigravity CLI |

Claude Desktop and ZCode manage their own sign-ins. Keychain-only Codex accounts are not supported. Restart running clients after switching.

Google's individual AI Pro and Ultra coding access moved to [Antigravity](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals). Gemini support applies to eligible Code Assist accounts. Sign into `agy` first for Antigravity; an installed CLI alone does not establish a paid plan.

Usage shows provider allowances and credits. Weekly dollar spend appears only when a provider reports it. Monthly bills and estimated costs are not displayed.

See [account discovery and switching](docs/ACCOUNTS.md).

## Status

Version **0.2.1** is an early preview. Codex and Claude usage have been checked with live accounts. Z.ai, Gemini, and Antigravity have fixture checks but still need validation with live accounts. Provider endpoints can change.

Downloads and local builds are ad-hoc signed. Developer ID signing and Apple notarization are not configured yet.

## Export an installable app

```sh
./scripts/package.sh --universal
```

Creates an `.app`, `.dmg`, `.zip`, and `SHA256SUMS.txt` in `dist/` for Apple Silicon and Intel. Account data is excluded. Omit `--universal` to build only for your Mac's architecture.

## Development

Built with SwiftUI and AppKit, with no third-party runtime dependencies.

```sh
swift run SubTracker --demo --window
swift run SubTracker --demo --settings
swift run SubTracker --demo --google --window
./scripts/check.sh
./scripts/package.sh
```

`--demo` uses sample accounts and makes no provider requests or credential changes. The 24 dependency-free checks run with temporary homes and synthetic credentials. They cover quota parsing, discovery, account identity, safe switching, file permissions, CLI version gates, timeouts, and process cleanup.

CI checks Apple Silicon and Intel builds. Version tags publish universal preview downloads after those checks pass. See [CONTRIBUTING.md](CONTRIBUTING.md) and [release instructions](docs/RELEASING.md).

## Privacy

Direct provider requests use an explicit HTTPS allowlist. Antigravity usage runs through the installed CLI and its own network configuration. No analytics, backend, proxy, or browser-cookie extraction. Saved credentials and authentication backups remain local. The app does not need Screen Recording or Accessibility access.

Read [SECURITY.md](SECURITY.md) before reporting a sensitive issue. Never include real credentials or account screenshots in public issues.

## License

[MIT](LICENSE). Provider marks have their own [attribution and ownership notices](THIRD_PARTY_NOTICES.md). Sub Tracker is independent of OpenAI, Anthropic, Z.ai, and Google.
