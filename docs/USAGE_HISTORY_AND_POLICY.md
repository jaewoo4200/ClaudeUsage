# Usage history, privacy, and provider policy

Last reviewed: 2026-07-10

This document describes what ClaudeUsage reads and stores, and records the current provider-policy assessment. It is a technical assessment, not legal advice.

## What the history feature stores

Usage history is **off by default**. When the user enables it, the app writes one local JSON file at:

```text
~/Library/Application Support/ClaudeUsage/usage-history.json
```

The file contains only timestamps, quota percentages, and daily token totals. It does not store prompts, responses, filenames, project names, account identifiers, cookies, or access tokens.

- Sampling interval: five minutes, plus immediate samples when a quota reset is detected
- Retention: 14 days
- Deletion: Settings > Mimo > Clear usage history
- Reinstallation: deleting the `.app` bundle does not remove `usage-history.json`; the Settings action is required to delete ClaudeUsage's retained samples
- Network: history data is never uploaded by ClaudeUsage

Clearing ClaudeUsage history does not delete Claude Code's `~/.claude/projects` files or any Codex/ChatGPT account data. Daily token totals are source-backed and may therefore reappear on the next refresh even after the local 14-day trend file is cleared.

Mimo uses the highest currently visible quota percentage as its immediate pressure level. When history is enabled, it also uses the last hour of percentage and token deltas. A quota reset can produce the refreshed state for up to 30 minutes.

OpenAI daily token buckets may not contain the current calendar day while a Codex task is still active. In that case Mimo continues to react to the live quota-percentage trend and adds token deltas later when the official bucket becomes available.

## Token data sources and limits

| Provider | Source | Scope | Important limitation |
|---|---|---|---|
| OpenAI | Documented Codex app-server `account/usage/read` | ChatGPT account token-activity daily buckets | Buckets can lag behind the current session; token totals and quota percentages are different metrics |
| Claude | Local `~/.claude/projects/**/*.jsonl` files | Claude Code activity present on this Mac | Does not include claude.ai web or other devices; cache tokens are included |

ClaudeUsage reads only the structured timestamp and usage-number fields needed for aggregation. It does not retain message content from Claude Code logs. Local token totals are refreshed at most once every five minutes.

## Quota and reset-credit sources

| Metric | Source | Notes |
|---|---|---|
| Claude quota percentages and reset times | Authenticated claude.ai usage response | Server-backed and currently undocumented by Anthropic |
| Codex quota percentages and reset times | Codex app-server `account/rateLimits/read` | Server-backed account snapshot returned through a local RPC process |
| Codex reset-credit count and expiry | Optional `rateLimitResetCredits` in newer `account/rateLimits/read` responses | Not a transcript or local-session scan; absent on unsupported builds/accounts |

Newer Codex app-server builds may also expose `account/rateLimitResetCredit/consume`. ClaudeUsage's proposed Mimo advisor is read-only: it may explain availability and recommend when a reset is useful, but it must never consume a reset credit automatically. Any future consume action must identify the selected credit and require an explicit user confirmation.

## Provider access assessment

### OpenAI

The app now uses only the documented local Codex app-server methods:

- `account/rateLimits/read` for quota windows
- `account/usage/read` for token-activity summaries and daily buckets

These methods are listed in OpenAI's [codex app-server documentation](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md). The previous direct call to the internal `chatgpt.com/backend-api/wham/usage` endpoint has been removed. This is materially safer than scraping the ChatGPT settings page or calling an undocumented web endpoint.

OpenAI's [Terms of Use](https://openai.com/policies/row-terms-of-use/) still prohibit automatic or programmatic extraction and bypassing rate limits. The documented app-server interface is the strongest available supported integration path, but this project does not claim that its existence is a separate legal authorization for every third-party distribution scenario.

### Anthropic

Claude's current quota source is an undocumented claude.ai usage endpoint authenticated with the user's own session cookie. Anthropic's [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) prohibit crawling or scraping and prohibit automated or non-human access except through an Anthropic API key or where Anthropic explicitly permits it.

Anthropic documents interactive Claude Code commands such as `/usage` and `/cost` in its [Claude Code cheatsheet](https://support.claude.com/en/articles/14553413-claude-code-cheatsheet), but no supported consumer quota API for third-party background widgets was found during this review. Therefore:

- Local analysis of files already stored on the user's Mac is lower risk because it does not access Anthropic's service.
- The current automatic claude.ai quota request has a material terms-of-service risk.
- Public or commercial distribution should wait for written Anthropic permission or a documented supported usage API.

## Related implementation precedent

[CodexBar](https://github.com/steipete/CodexBar) is an open-source macOS usage monitor that also separates local log analysis, local CLI/RPC sources, and optional web sources. It is useful implementation precedent, but another project's existence is not proof of provider authorization.

## Release recommendation

The Mimo UI and opt-in local history can be shipped independently of cloud scraping. Before a public release that keeps automatic Claude quota fetching, obtain written clarification from Anthropic or replace that source with a documented interface. Re-check both providers' terms whenever the data source or distribution model changes.
