# Accounts and data

Providers appear only after an authenticated usage check succeeds in the current session. Installed apps, saved names, old credentials, and caches alone do not make accounts visible. Failed checks hide them until validation succeeds again.

Usage is not proof of billing. Plan names come from providers. Unknown limits stay unknown, credits remain credits, and weekly spend appears only when explicitly reported. Monthly bills and estimated costs are not shown.

## Provider setup

### Codex / ChatGPT

- Reads `~/.codex/auth.json`, native account registries, `~/.codex/accounts/*.auth.json`, and legacy `~/.codex-swap/accounts/*.auth.json`.
- Deduplicates by workspace and user. Switching changes the file-backed CLI sign-in. Keychain-only accounts are unsupported.

### Claude Code

- Uses the existing macOS credential or `.credentials.json`. Reports five-hour, weekly, and model-specific allowances.
- Save accounts from the Claude menu to switch later. Saved credentials use Keychain. Switching preserves unrelated settings and MCP credentials. Claude Desktop and browser sessions are separate.

### Z.ai / BigModel

- Reads configured Z.ai keys from Claude Code or `ZAI_API_KEY`. Settings accepts Coding Plan keys.
- Switching updates an existing Z.ai configuration in Claude Code. ZCode's own sign-in stays in ZCode. Installed ZCode alone does not add an account.

### Gemini

- Uses Gemini CLI OAuth from `~/.gemini/oauth_creds.json` or its `gemini-cli-oauth` Keychain item. `GEMINI_CLI_HOME` overrides the home directory.
- Supports eligible Code Assist accounts. API-key mode, Vertex mode, and encrypted fallback storage are unsupported. Sign-in and token refresh stay in Gemini CLI.
- `GOOGLE_CLOUD_PROJECT` or `GOOGLE_CLOUD_PROJECT_ID` can supply a project. Google's individual coding plans moved to [Antigravity](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals).

### Antigravity

- Requires a signed-in `agy` CLI, version 1.1.11+. Searches PATH, local bin directories, and Homebrew. `ANTIGRAVITY_CLI_PATH` accepts an absolute executable path.
- Runs the read-only JSON `/usage` report without a model prompt. The report does not identify a plan or account, so the app does not infer one or offer switching.

### GitHub Copilot

- Reads Copilot-specific `hosts.json` / `apps.json`, public GitHub entries in `~/.copilot/config.json`, the `copilot-cli` Keychain service, or `COPILOT_GITHUB_TOKEN`.
- Does not reuse `gh`, `GH_TOKEN`, `GITHUB_TOKEN`, or enterprise-host credentials. Shows reported quotas, unlimited pools, or credits without inventing missing limits.

### Cursor

- Reads the editor's `cursorAuth/accessToken` from `state.vscdb`, or `~/.config/cursor/auth.json` when no editor token exists.
- Verifies the token's account identity. Does not read browser cookies or silently fall back to another account after rejection. Model pools and weekly pools remain separate.

### Kimi

- Supports global `api.kimi.ai` and China `api.kimi.com` subscriptions. Reads region-scoped files under `~/.kimi-code/credentials`, configured provider keys, or `KIMI_CODE_API_KEY` with `KIMI_CODE_BASE_URL`.
- Respects `KIMI_CODE_HOME`. Settings accepts regional keys. Unknown endpoint overrides disable OAuth-file discovery. The app does not refresh OAuth tokens.

### MiniMax

- Reads Coding Plan keys from OpenCode, Claude Code, `MINIMAX_CODING_API_KEY`, or `MINIMAX_CN_API_KEY`. Settings supports both regions.
- `MINIMAX_API_KEY` requires a coding-key prefix. Standard `sk-api-` keys are excluded. Displays only reported allowances and credits.

### Devin / Windsurf

- Cache parsing exists, but cached plan data cannot verify a current sign-in. These entries stay hidden.
- Live web quotas and browser sessions are not imported.

### Kiro

- Reads CLI sign-ins from `~/Library/Application Support/kiro-cli/data.sqlite3` or `KIRO_DATA_DIR`. Supports US East and Frankfurt endpoints.
- Reports plan, trial, and enabled overage credits. Ambiguous bonus limits stay unknown. IDE-only sign-ins are unsupported.

### OpenCode Go

- Reads `opencode-go` from `~/.local/share/opencode/auth.json`, `OPENCODE_API_KEY`, or a key connected in Settings.
- Shows reported five-hour, weekly, and monthly usage. Locally estimated model costs are not subscription spend.

## Connection behavior

- Supported CLI paths respect `XDG_CONFIG_HOME` and `XDG_DATA_HOME`.
- Finder-launched apps may not inherit shell environment variables. Use Settings for persistent key connections.
- Connecting a key does not change another coding app's active key.
- Providers that omit account identity may show duplicates when several keys access one subscription.
- **Add account** opens a key form or the provider's sign-in. No login starts automatically.

## Refresh and switching

| Behavior | Rule |
| --- | --- |
| Refresh | Every five minutes, after wake, and when opened |
| Manual refresh | At least one minute between attempts per account |
| Rate limiting | HTTP 429 adds a 15-minute cooldown |
| Rejected sign-in | HTTP 401/403 requires the provider's own login |
| Passed reset time | Marked expired, never assumed to be 100% available |
| Google readings | Revalidated and kept in memory only |

Switching verifies the target, preserves outgoing credentials, creates private backups, and rejects changed files or symlinks. It updates local files, not running sessions. Restart affected clients afterward. Additional providers manage switching in their own clients.

Antigravity owns its token refresh and network configuration. Its subprocess uses a private temporary directory, browser-login blockers, disabled updates, a 1 MiB output cap, and a 45-second deadline. Cleanup targets its process group and marked descendants. Detached children that discard the marker cannot be identified. Independently running CLI sessions are not selected.

## Local data

| Data | Storage |
| --- | --- |
| Metadata, usage cache, authentication backups | `~/Library/Application Support/SubTracker` |
| Saved Claude accounts and connected keys | Keychain service `com.sagar.subtracker.accounts` |
| Existing client sign-ins | Their original provider files |

Authentication backups contain secrets. Keep them private. Direct requests use an HTTPS allowlist and reject redirects. The Antigravity CLI has its own network and MCP configuration. See [Security](../SECURITY.md).

To uninstall: disable Open at login, quit the app, and remove it from Applications. Optionally remove the support directory and its Keychain items to discard saved data. Uninstalling does not sign out providers.

## References

- [Codex client](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client.rs), [Claude usage](https://code.claude.com/docs/en/statusline), [Z.ai usage plugin](https://github.com/zai-org/zai-coding-plugins)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Antigravity usage reports](https://antigravity.google/docs/cli/headless/)
- [Copilot authentication](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli), [Cursor limits](https://prod.cursor.com/help/models-and-usage/usage-limits)
- [Kimi quota parser](https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/managed-usage.ts), [MiniMax usage](https://platform.minimax.io/docs/m-plan/faq)
- [Kiro billing](https://kiro.dev/docs/billing/), [OpenCode Go](https://dev.opencode.ai/v2/docs/console/go)
- [CodexBar](https://github.com/steipete/CodexBar) supplied additional format references. Private provider endpoints are not stable public APIs.
