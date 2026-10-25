# Sub Tracker

Your AI accounts and remaining usage, one glance away.

A free, open-source macOS app for Codex, Claude, and Z.ai. It reads your own local sign-ins, shows allowances and reset times, and helps you switch accounts. Built with SwiftUI and AppKit, with no third-party runtime dependencies. MIT licensed.

[Download the app](https://github.com/Sagar-CK/sub-tracker/releases) · [Build from source](#build-from-source) · [Contribute](CONTRIBUTING.md)

<p align="center">
  <img src="docs/images/usage-dark.png" alt="Dark appearance with Codex, Claude, and Z.ai usage" width="46%">
  <img src="docs/images/usage-light.png" alt="Light appearance with the same sample accounts" width="46%">
</p>

*Sample accounts. Product images finished with CleanShot X.*

- **At your notch.** Compact readouts flank the actual camera cutout. Click to expand accounts beneath it. Macs without a notch use the menu bar.
- **Only your providers.** Detected and connected accounts appear with their current plan, remaining allowance, and reset times.
- **Local account switching.** Switch supported CLI sign-ins and keep saved Claude and Z.ai credentials in Keychain.
- **Your placement.** Choose Notch, Menu bar, or Both. Follow system light or dark appearance in the menu bar; notch mode stays dark.

No monthly bills or estimated dollar costs. Credits remain credits. Weekly dollar spend is shown only when a provider explicitly reports it; the Codex and Claude responses tested so far do not.

## Download and install

1. Open [Releases](https://github.com/Sagar-CK/sub-tracker/releases) and download the **universal DMG**.
2. Open the DMG and drag **Sub Tracker** into **Applications**.
3. Open Sub Tracker from Applications. Your local Codex and Claude Code sign-ins are detected; connect a Z.ai Coding Plan key in Settings if needed.

Requires **macOS 14+**. The same download runs on Apple Silicon and Intel Macs. A ZIP containing the app is also available. No Xcode or Swift installation is needed for the download.

The first release is an **unnotarized preview**. If macOS blocks it, you can build from source below or follow [Apple's guidance for opening trusted downloaded apps](https://support.apple.com/en-us/102445). The project does not disable Gatekeeper or remove quarantine. Checksums are included with each release.

To update, quit the app and replace it in Applications. Your local account data stays in place.

## Build from source

Requires **macOS 14+** and a **Swift 6** toolchain (Xcode or Command Line Tools).

If the developer tools are not installed, run `xcode-select --install` first. Check `swift --version`; it must report Swift 6 or later.

```sh
git clone https://github.com/Sagar-CK/sub-tracker.git
cd sub-tracker
./scripts/install.sh
```

This builds and installs `~/Applications/Sub Tracker.app` without administrator access. No hosted service or shared API key is required. Each installation uses that person's own provider sign-ins and stores its data on their Mac.

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

Installed apps alone do not prove a paid subscription. Claude Desktop and ZCode manage their own sign-ins. Keychain-only Codex accounts are not supported. Restart running clients after switching so they load the new sign-in.

See [account discovery, switching, and data storage](docs/ACCOUNTS.md) for exact behavior.

## Status

Version **0.1.0** is an early preview. Codex and Claude usage have been checked with live accounts. Z.ai has parsing checks but still needs validation with a live Coding Plan key. Provider endpoints can change.

Downloads and local builds are ad-hoc signed. Developer ID signing and Apple notarization are not configured yet.

## Export an installable app

```sh
./scripts/package.sh --universal
```

Creates a universal `.app`, a drag-to-Applications `.dmg`, a `.zip`, and `SHA256SUMS.txt` in `dist/`. These contain only the app and license notices, with installation instructions in the DMG. Your accounts, keys, cache, and preferences are never included. Omit `--universal` to build only for your Mac's architecture.

## Development

```sh
swift run SubTracker --demo --window
swift run SubTracker --demo --settings
./scripts/check.sh
./scripts/package.sh
```

`--demo` uses sample accounts and makes no provider requests or credential changes. The 16 dependency-free checks run with temporary homes and synthetic credentials. They cover usage parsing, stale data, discovery, account identity, safe switching, and file permissions.

CI builds and checks Apple Silicon and Intel targets on macOS. A version tag runs both checks before building and publishing the universal preview download. See [CONTRIBUTING.md](CONTRIBUTING.md), [release instructions](docs/RELEASING.md), and the [image workflow](docs/images/README.md).

## Privacy

Provider requests go directly to an explicit HTTPS allowlist. No analytics, backend, proxy, or browser-cookie extraction. Saved credentials and authentication backups remain local. The app does not need Screen Recording or Accessibility access.

Read [SECURITY.md](SECURITY.md) before reporting a sensitive issue. Never include real credentials or account screenshots in public issues.

## License

[MIT](LICENSE). Provider marks have their own [attribution and ownership notices](THIRD_PARTY_NOTICES.md). Sub Tracker is independent of OpenAI, Anthropic, and Z.ai.
