# Changelog

## 0.2.1 (2026-10-24, Preview)

- Keep the last Google reading in memory when a refresh is skipped by the one-minute floor. Revalidate it when the next request is permitted.

## 0.2.0 (2026-10-24, Preview)

- Add Gemini Code Assist quotas from local Gemini CLI OAuth sign-ins.
- Add Antigravity quota reports through the installed CLI, including grouped weekly allowances.
- Use Google provider icons and expose each CLI from the provider menu.
- Show an overflow count when more providers are active beside the notch.
- Verify Google identity before attribution, avoid persistent Google quota caches, and bound CLI execution with process cleanup.
- Add eight checks for Google quota parsing, migration, identity, discovery, CLI version gates, timeout, output limits, and detached child cleanup.

Gemini and Antigravity require live-account validation. Account switching stays in the respective Google CLI. Downloads remain unnotarized previews.

## 0.1.0 (2026-10-24, Preview)

- Read Codex, Claude, and Z.ai / BigModel subscription usage from local sign-ins.
- Display remaining allowance, reset times, credit balances, and explicitly reported weekly spend.
- Place readouts beside the actual MacBook camera cutout, in the menu bar, or both.
- Switch saved local accounts while preserving outgoing credentials.
- Add private Keychain storage, stale-data handling, and rate-limit cooldowns.
- Include a sample-data mode, native screenshots, and macOS verification/packaging workflows.
- Offer clone-and-run installation and universal Apple Silicon/Intel DMG and ZIP downloads.

Known limits: ZCode desktop and Claude Desktop manage their own sign-ins; keychain-only Codex accounts are not supported; Z.ai live integration requires a connected key; distributed binaries are not yet notarized.
