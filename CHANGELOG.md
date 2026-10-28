# Changelog

## 0.5.0 · Preview

Sub Tracker is now Notch Sub:

- New app name, bundle identifier (`com.sagar.notchsub`), icon, and repository ([Sagar-CK/notch-sub](https://github.com/Sagar-CK/notch-sub)).
- On first launch, Sub Tracker's saved accounts, Keychain items, usage cache, and settings move over.
- Opens at login by default when run from Applications. Turn it off in Settings.
- `./scripts/install.sh` replaces `~/Applications/Sub Tracker.app`.

## 0.4.3 · Preview

Initial open-source baseline:

- Native notch and menu bar views with configurable placement.
- Compact usage that cycles or stays pinned to a provider.
- Verified local account discovery, remaining allowances, reset times, and credits.
- Local switching for Codex, Claude Code, and configured Z.ai keys.
- Provider integrations and limitations documented in [Accounts](docs/ACCOUNTS.md).
- Clone-and-run installation and universal DMG / ZIP downloads.
- Demo mode, synthetic checks, and Apple Silicon / Intel CI.

Downloads are ad-hoc signed, not Apple-notarized. Earlier preview notes remain on [GitHub Releases](https://github.com/Sagar-CK/notch-sub/releases).
