# Usage history, privacy, and provider policy

Last reviewed: 2026-07-10

This document describes what ClaudeUsage reads and stores, and records the current provider-policy assessment. It is a technical assessment, not legal advice.

## What the history feature stores

Usage history is **off by default**. When the user enables it, the app writes one local JSON file at:

```text
~/Library/Application Support/ClaudeUsage/usage-history.json
```

The file contains only timestamps, quota percentages, model-limit identifiers and display names, and daily token totals. It does not store prompts, responses, filenames, project names, account identifiers, cookies, or access tokens.

- Sampling interval: five minutes, plus immediate samples when a quota reset is detected
- Retention: 14 days
- Deletion: Settings > Companion > Clear usage history
- Reinstallation: deleting the `.app` bundle does not remove `usage-history.json`; the Settings action is required to delete ClaudeUsage's retained samples
- Network: history data is never uploaded by ClaudeUsage
- Viewer: the local chart window can filter 1 hour, 24 hours, 7 days, or 14 days and All, Claude, or Codex

Clearing ClaudeUsage history does not delete Claude Code's `~/.claude/projects` files or any Codex/ChatGPT account data. Daily token totals are source-backed and may therefore reappear on the next refresh even after the local 14-day trend file is cleared.

## Peak pressure and companion thresholds

The selected companion uses the highest currently visible quota percentage as its immediate pressure level. It is not a sum or average:

```text
pressure = max(
  Claude 5-hour,
  Claude weekly,
  Claude model-specific limits,
  Codex 5-hour,
  Codex weekly,
  visible Codex model-specific limits
)
```

An unavailable value is ignored. A model limit hidden by the user, such as the optional Spark counters, is also excluded. Beginning with v1.4.0, the history file preserves individual model-limit identifiers, labels, and percentages instead of retaining only the model maximum. Older samples remain readable and appear as a generic model-maximum series.

When history is enabled, the selected companion also uses the last hour of pressure and token deltas. Pressure pace is calculated from locally sampled pressure points, so it has gaps whenever ClaudeUsage was not running.

| Sensitivity | Focused | Sleepy | Tired |
|---|---:|---:|---:|
| Early | 35% or 8%p/hour | 70% or 22%p/hour | 90% or 40%p/hour |
| Balanced (default) | 50% or 14%p/hour | 75% or 28%p/hour | 90% or 45%p/hour |
| Relaxed | 60% or 18%p/hour | 82% or 34%p/hour | 94% or 52%p/hour |

The highest matching state wins. A quota drop of at least 15 percentage points followed by pressure below 60% can produce the Refreshed state for up to 30 minutes.

Animation modes affect presentation only, not the state calculation. Auto updates target poses at an adaptive cadence and transitions for only 0.16 to 0.25 seconds depending on state. Lively updates every 0.25 seconds with a 0.16-second transition, while Still performs no continuous animation. Floating-widget animation is paused when that widget is hidden, and macOS Reduce Motion is always respected.

OpenAI daily token buckets may not contain the current calendar day while a Codex task is still active. In that case the companion continues to react to the live quota-percentage trend and adds token deltas later when the official bucket becomes available.

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

Newer Codex app-server builds may also expose `account/rateLimitResetCredit/consume`. ClaudeUsage's proposed companion advisor is read-only: it may explain availability and recommend when a reset is useful, but it must never consume a reset credit automatically. Any future consume action must identify the selected credit and require an explicit user confirmation.

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

The companion UI and opt-in local history can be shipped independently of cloud scraping. Before a public release that keeps automatic Claude quota fetching, obtain written clarification from Anthropic or replace that source with a documented interface. Re-check both providers' terms whenever the data source or distribution model changes.
