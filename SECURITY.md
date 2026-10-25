# Security

Sub Tracker handles local provider sign-ins. Report credential disclosure, account mix-ups, unexpected writes, or unsafe network destinations privately.

Use [GitHub's private vulnerability reporting](https://github.com/Sagar-CK/sub-tracker/security/advisories/new) when it is enabled. If that route is unavailable, open an issue saying only that you need a private reporting channel; do not include the vulnerability, credentials, or personal account details in the public issue.

Include the app version, macOS version, affected provider, impact, and reproduction using synthetic data where possible. Do not send tokens, authentication files, browser profiles, or Keychain exports.

## Data boundaries

- Usage requests go directly to the allowlisted provider, with TLS validation and redirects disabled.
- Saved Claude and Z.ai credentials use macOS Keychain. Codex continues to use its existing local file-backed sign-ins.
- App-owned account metadata, usage cache, and authentication backups are local. Private files use mode `0600`; newly created data directories use `0700`.
- There is no analytics, upload service, or browser-cookie extraction.
- Diagnostics omit account identities and credentials. Public screenshots use demo data.

The app runs outside the App Sandbox so it can read local CLI configuration. It does not isolate those files from other software running as the same macOS user. Account switching uses optimistic file checks and atomic replacements, but provider clients do not share its lock. Restart running clients after switching to avoid stale sign-ins and competing token writers.

## Supported versions

Security fixes target the latest source revision and latest tagged release. Version 0.1 is an early release; provider usage APIs can change without notice.

## Distribution

Local builds, CI artifacts, and preview downloads are ad-hoc signed, not Apple-notarized. A notarized binary release requires a maintainer's Developer ID signing and notarization setup. Preview downloads include SHA-256 checksums and are built from the tagged public source in GitHub Actions. Do not disable Gatekeeper or remove quarantine as a substitute for verifying an unfamiliar download.
