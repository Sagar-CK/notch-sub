# Security

Report credential disclosure, account mix-ups, unexpected writes, or unsafe network requests through [private vulnerability reporting](https://github.com/Sagar-CK/notch-sub/security/advisories/new).

Include the app version, macOS version, provider, impact, and steps using synthetic data. Do not send credentials, browser profiles, or Keychain exports. If private reporting is unavailable, open a public issue requesting a private channel without describing the vulnerability.

## Data boundaries

- Direct usage requests use an HTTPS allowlist, TLS validation, and no redirects.
- Saved Claude accounts and connected keys use macOS Keychain. Codex uses its existing sign-in files.
- App-owned metadata, caches, and authentication backups stay local. Private files use `0600`; new data directories use `0700`.
- Editor databases are read-only. Discovery does not create missing SQLite sidecars or read browser profiles.
- Regional keys remain on their configured host. Copilot does not reuse broad GitHub CLI tokens.
- Antigravity runs its installed CLI with a timeout, bounded output, browser-login blockers, disabled updates, and owned-process cleanup. The CLI retains its own authentication, network, and MCP configuration and may refresh its credentials.
- Google readings are not persisted. Diagnostics omit account identities and credentials.
- No analytics, backend, or upload service. Shared screenshots use demo data.

The app runs outside the App Sandbox to read local CLI configuration. It cannot isolate those files from other software running as the same user. Switching uses atomic replacements and checks for concurrent changes, but provider clients do not share its lock. Restart those clients after switching.

## Versions and downloads

Security fixes target the latest source revision and tagged release. Provider APIs may change without notice.

Preview downloads are ad-hoc signed, not Apple-notarized. GitHub Actions builds them from public tags and includes SHA-256 checksums. Signing credentials are never included in source or pull-request CI.

See [account storage and removal](docs/ACCOUNTS.md#local-data) and [release instructions](docs/RELEASING.md).
