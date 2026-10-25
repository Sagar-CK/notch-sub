# Changelog

## 0.3.1 (2026-10-24, Preview)

- Render provider sections and notch readouts only for accounts with successful authenticated usage checks.
- Hide expired, rejected, unverified, and cache-only accounts, including installed-app placeholders.
- Revalidate on each launch and restore hidden accounts after a successful refresh.
- Add four checks for conditional visibility, failed validation, identity changes, and installed apps without credentials.

## 0.3.0 (2026-10-24, Preview)

- Add GitHub Copilot, Cursor, Kimi, MiniMax, Kiro, and OpenCode Go usage integrations.
- Read Devin/Windsurf’s local quota cache with an explicit cached state.
- Discover supported local editor databases, CLI sign-ins, and provider-scoped keys without changing them.
- Add region-pinned key connections, real provider icons, and a compact Add account menu.
- Keep unlimited allowances and credits separate from percentage limits.
- Add 18 checks covering provider formats, missing values, read-only databases, region boundaries, and account changes.

Cursor was validated with a live account. Other new providers require live-account validation. Switching for these providers stays in their own client. Downloads remain unnotarized previews.

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
