# Accounts and data

## Accounts

- **Codex:** Discovers `~/.codex/auth.json`, `~/.codex/accounts/*.auth.json`, the native registry, and `~/.codex-swap/accounts/*.auth.json`. Deduplicates by workspace and user. Reads live usage and credits. The arrow switches the file-based CLI sign-in; restart running clients to reload it. Keychain-only Codex credentials are not currently supported.
- **Claude:** Detects the Claude Code account and reads five-hour, weekly, and model-specific allowances. Uses the existing macOS credential or `.credentials.json`. Save each sign-in from the Claude menu to enable switching; saved credentials stay in Keychain. Switching updates Claude Code's OAuth credential and account metadata, preserving unrelated settings and MCP credentials. Claude Desktop/browser sign-ins are separate.
- **Z.ai / BigModel:** Detects keys in Claude Code's `settings.json` when its base URL is an allowlisted Z.ai endpoint, or `ZAI_API_KEY` in the app's environment. Connect a Coding Plan key privately in Settings. Switching saved keys updates an **existing** Z.ai configuration in Claude Code. ZCode desktop's own login must be changed in ZCode; this app does not read its private browser storage. If ZCode is installed without a readable key, a Connect row appears.

Only detected or explicitly connected providers appear. Installed apps alone are not evidence of a paid subscription. A plan name reflects the provider's reported plan, not billing verification.

Bars show remaining allowance for each provider window, including Codex plans whose primary window is weekly. Credits stay labeled credits. Weekly dollar spend appears only if the provider supplies an explicitly weekly monetary amount, currency, and units; the Codex/Claude responses tested locally do not. Monthly extra usage is never relabeled as weekly spend.

## Refresh and switching

Usage refreshes every five minutes and after wake. Manual refresh has a one-minute per-account floor; HTTP 429 adds a 15-minute cooldown. Cached/expired readings are marked. A passed reset time never silently becomes 100% available. HTTP 401/403 requires the provider's own sign-in. The app does not rotate OAuth refresh tokens in the background.

Switching verifies the target with the provider, preserves refreshed outgoing credentials, uses private backups and atomic file replacement, and rejects changed files or symlinks. Codex registry and legacy swap state stay aligned. This changes local sign-in files, not running agent sessions. Restart those clients afterward; their token writers do not share this app's lock.

**Add account** / **Sign in to another account** preserves the current account first, then opens the official CLI login in Terminal. No login is triggered automatically.


## Local data

Direct HTTPS requests go only to `chatgpt.com`, `api.anthropic.com`, `api.z.ai`, or `open.bigmodel.cn`. Credential-bearing requests reject redirects. No analytics, backend, proxy, or browser-cookie extraction. Secrets never appear in arguments or logs. Metadata, usage, and backups live under `~/Library/Application Support/SubTracker` with private file permissions; saved Claude/Z.ai secrets use macOS Keychain. Authentication backups contain secrets and must remain private.

To remove: quit, disable Open at login, and remove `~/Applications/Sub Tracker.app`. Remove the support directory and Keychain items under `com.sagar.subtracker.accounts` to discard saved data. Removing the app does not sign out providers.


## References and assets

- [Codex backend client](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client.rs), [Codex account protocol](https://learn.chatgpt.com/docs/app-server)
- [Claude usage documentation](https://code.claude.com/docs/en/statusline). The first-party OAuth usage endpoint is not a stable public API and can change.
- [Z.ai official usage plugin](https://github.com/zai-org/zai-coding-plugins/blob/main/plugins/glm-plan-usage/skills/usage-query-skill/scripts/query-usage.mjs), [ZCode usage](https://zcode.z.ai/en/docs/usage-stats), [CodexBar's quota format reference](https://github.com/steipete/CodexBar/blob/main/docs/zai.md)
- Provider marks: [Lobe Icons](https://github.com/lobehub/lobe-icons), `@lobehub/icons-static-svg` 1.98.0. MIT license included in Resources. Marks belong to their respective owners; no affiliation implied.
- Visual direction: [Reason](https://reasonmachines.ai) and [Devin](https://devin.ai).
