# Historical checkpoint — Windows Phase 0–2

> This file preserves the Phase 0–2 checkpoint captured before Claude login, full widgets, settings/themes, companions, and optional history were integrated. Phase 0–5 feature implementation is now complete in the Windows 11 x64 developer alpha; see the current [handoff status](../HANDOFF.md) and [Windows README](README.md). The test count, screenshot, ZIP name, and SHA-256 below belong **only to the historical Phase 0–2 artifact** and must not be quoted as results for the current integrated tree.

Phase completed at this checkpoint: Phase 0 machine reconnaissance, Phase 1 pure core, Phase 2 Codex-first tray vertical slice

Commit: based on macOS repository `0e928c67b218f0fe138acd187fa0de673b69b10c` (`v1.5.0`); Windows changes are currently uncommitted

Windows version and architecture: Windows NT 10.0.26200, x64

Codex version and resolved executable path category: `codex-cli 0.144.0-alpha.4`; discovered from the per-user Codex Desktop executable cache. Usernames and account identifiers are not recorded.

What worked at this checkpoint:

- .NET 10 WPF app with one notification-area icon and click flyout
- Live `codex app-server` JSONL initialization
- Required `account/rateLimits/read` and optional `account/usage/read`
- Plan, five-hour/weekly counters, dynamic model counters, reset time, reset credits, and today's token bucket
- User-selected executable, `PATH`, and per-user Codex Desktop executable discovery
- 20-second total timeout, concurrent stderr drain, cancellation, and process-tree cleanup
- Immediate startup refresh, 60-second timer, and superseding manual refresh
- Separate current error state and last good snapshot
- Setup guidance for unavailable or signed-out Codex
- Per-monitor work-area clamping near the current cursor/taskbar
- Atomic versioned settings under `%LOCALAPPDATA%\ClaudeUsage\settings.json`
- Self-contained `win-x64` developer zip

What remained at this checkpoint:

- Phase 2 review before Phase 3 — superseded by the integrated Phase 0–5 developer alpha
- Validate the current integrated ZIP on a second Windows account or clean machine — **still pending as a release gate**
- Finish the external production release gates — MSIX/App Installer, SPDX/SHA/license generation, protected signing injection, and smoke automation now exist; the permanent identity, trusted certificate, HTTPS channel, and clean-machine evidence are **still pending**
- Phase 3 Claude WebView2 login, temporary profile cleanup, DPAPI cookie storage, and policy gate — implemented after this checkpoint
- Phase 4–5 floating widget layouts, three themes, English localization, history, and nine companions — implemented after this checkpoint

Historical tests run and result:

- `.NET SDK 10.0.301` and Windows Desktop Runtime 10.0.9 verified
- Debug solution build: passed, 0 warnings / 0 errors
- Release xUnit: 19 passed / 0 failed
- Live Codex app-server probe: initialize, rate limits, token usage, and sanitized response IDs verified
- WPF live render: plan, live quota, reset time, reset credits, and token-unavailable state rendered without binding errors
- Self-contained Release smoke test: process remained running and responsive without a system-wide .NET install

Historical screenshots/artifacts (not current release assets):

- `windows/artifacts/screenshots/codex-live.png`
- `windows/artifacts/ClaudeUsage-Windows-v0.1.0-alpha-win-x64.zip`
- Historical Phase 0–2 ZIP SHA-256: `47D424E7DCDFCED4E7312DF427F40CC96FB0C92F0B013317119D24AFA7C8978D` — do not use this value to verify a later package

Payload differences discovered:

- The installed Codex build can return rate limits while the optional current-day token bucket is absent; the UI shows “집계 대기 중” without rejecting valid limits.
- UTF-8 standard input must be emitted without a byte-order mark. A BOM before the first JSON object caused the app-server to wait without returning an initialize response.
- Presentation must bind the WPF `ProgressBar.Value` one-way because normalized counters are immutable.

Security/privacy notes:

- The app does not scrape ChatGPT pages.
- The app does not read `%USERPROFILE%\.codex\auth.json` or store OpenAI tokens.
- Raw stdout, stderr, RPC payloads, cookies, account identifiers, and executable paths are not logged by the release UI.
- Release symbols are excluded from the zip; a binary scan found no absolute local username/build-path strings.
- Reset credits are display-only; no consume method is called.
- The undocumented Claude cloud endpoint was outside this checkpoint; the later developer alpha adds it behind an experimental provider setting and explicit policy warning.

Decision recorded at this checkpoint:

- Phase 2 progression was approved and Phase 3–5 implementation followed.
- The public Claude-enabled distribution question remains open: obtain Anthropic permission or prefer a documented supported usage interface before a stable/public release.

## Current follow-up after Phase 0–5 integration

- Run and record final tests and visual/live checks against the current integrated tree; no current total is asserted in this historical report.
- Build a fresh self-contained `win-x64` ZIP and use its newly generated `.zip.sha256`; do not reuse the historical hash above.
- Validate the extracted ZIP under a clean Windows account or clean machine.
- Keep public publication manual and explicitly authorized through the protected `Windows signed release candidate` workflow; unsigned CI artifacts must never be published as installers.
- Supply the permanent identity/certificate/update host and complete SignTool, SmartScreen, upgrade, uninstall, and data-retention validation before calling the Windows build stable.
