# ClaudeUsage Windows Port Handoff

Last updated: 2026-07-23

## 0. Handoff status

- macOS functional baseline: ClaudeUsage `1.5.0` (build `14`)
- Windows implementation: Phase 0–5 feature integration is complete as a Windows 11 x64 developer alpha
- Windows stack: .NET SDK `10.0.302` + WPF, with an exact-version WebView2 dependency
- Repository strategy: keep the macOS app unchanged and add a sibling `windows/` solution
- Implemented alpha scope: independent Claude/Codex refresh, combined tray flyout, four floating-widget layouts, themes/localization/settings, nine companions, optional bounded history, Claude Code JSONL aggregation, and per-user startup
- Phase 6 foundation: `windows-latest` CI, deterministic self-contained `win-x64` ZIP, structural MSIX/App Installer, SPDX SBOM, license/checksum validation, and a two-environment signed-candidate workflow are implemented
- Local Windows runtime/UIA audit, Release tests, DPI/resource validation, and byte-reproducible ZIP/MSIX packaging are complete. Release-readiness work still pending: mixed-DPI/assistive-technology checks on additional hardware, permanent package identity and trusted certificate provisioning, hosted update-channel verification, clean-machine install/update/uninstall/startup smoke, and an explicitly authorized public Windows release
- Current local gate (2026-07-23): all 220 Release tests pass (66 Core, 2 startup black-box, and 152 Windows), including real-HWND widget movement/clamp/independent-position restore, fixed-size movable settings-window and resizable history-window work-area integration, passive tray/widget activation, WebView2 login-policy hardening, real subprocess app-server/startup coverage, vector-icon parity checks, and real WPF layout/scroll-command checks for the overlay-scrollbar, fixed flyout footer, and responsive history. Release builds complete with zero warnings, and the exact current ZIP passes both the runtime smoke and the checked-in real-pointer movement smoke: Settings moved `+180,+100`, History `+180,+100`, and Widget `-180,+100` through `SendInput` while all sizes/work-area bounds stayed valid and the real settings file, test processes, input state, and bounded temporary directory passed cleanup postconditions. Windows PowerShell 5.1 static guards for both smoke harnesses pass, and CI validates them before packaging/signing. Two fixed-epoch package runs produced byte-identical ZIP, structural MSIX, and SPDX SBOM artifacts. A final Windows runtime capture verifies the 420-pixel fixed settings window, thin scrollbar, unwrapped sensitivity text, and vector chart/delete/external-link icons; the flyout overlay geometry is additionally covered by real WPF runtime layout tests. The standard-user self-signed lifecycle harness now delegates only an exact certificate lease to one UAC broker, uses explicit cross-account event/mutex ACLs, and has Windows PowerShell 5.1 static, immutable-payload, failure-protocol, and abandoned-parent cleanup coverage. Its live install/upgrade/uninstall rerun and the separate clean-machine signed release gate are still required.
- Reproducible local artifact hashes: ZIP `a34d356ec21b29a3044b26009ede23b78d21041a3c905c49e450bca089d5a5d2`; unsigned structural MSIX `21ec181cc8ef482fcce6830671b43a58e73b13cd0c3f5dcd5a5ec496205abaa2`; SPDX SBOM `0b6e0e782e280759d74e5e4dbf35239c0fa183ee046a870740973f3c0d4544c6`. These development artifacts are not authorized for public publication; their local `build-info.json` records `sourceCommit` as `unknown`, so protected CI must rebuild from the committed SHA before any release decision.
- Not currently offered publicly: a signed installer/MSIX, `win-arm64` package, hosted automatic-update channel, or stable Windows release
- `windows/PHASE_0_2_REPORT.md` is a historical Phase 0–2 checkpoint, not the current test count or artifact checksum

This is a native Windows port, not a direct rebuild of the SwiftUI project. The feature implementation now lives under `windows/`; the unchecked live, clean-machine, signing, and public-release gates later in this document are acceptance work, not missing Phase 0–5 product code. WPF runtime and visual QA must be performed on Windows or a Windows CI runner.

## 1. Copy-paste continuation prompt for final verification/release work

First pull the handoff onto Windows:

```powershell
git clone https://github.com/jaewoo4200/ClaudeUsage.git
Set-Location ClaudeUsage
git switch main
git pull --ff-only
Get-Content HANDOFF.md
```

```text
Read HANDOFF.md and the existing macOS source before editing.

Phase 0–5 feature integration is complete. Continue with verification and release-readiness only:
1. restore and test the full Windows solution from a fresh checkout using the pinned .NET SDK,
2. run the combined tray, Claude WebView2 login/logout, Codex app-server, four widget layouts, settings, history clear, startup, localization, and companion smoke checks on Windows 11 x64,
3. build the self-contained win-x64 ZIP plus structural MSIX/App Installer candidate with windows/scripts/package.ps1 and verify the SBOM, notices, and generated SHA-256 files,
4. validate the signed MSIX install/update/uninstall path under a disposable clean Windows 11 x64 machine without a system-wide .NET runtime,
5. report exact results and new artifact hashes only after those commands finish.

Keep Sources/ClaudeUsage and the current macOS behavior unchanged. Do not scrape chatgpt.com, read OpenAI token files, hardcode new model names, consume reset credits, or publish an unsigned prerelease. Public publication must promote the exact signed candidate through the protected `windows-signing` and `windows-production-release` environments after the permanent MSIX identity, trusted certificate, HTTPS update host, and clean-machine smoke gates pass.
```

## 2. Product goal

Build a Windows companion with the same user-facing meaning as the macOS app:

- Claude and Codex usage remain independent data sources.
- The user can inspect five-hour, weekly, and model-specific quota windows.
- Reset times and available Codex reset credits are visible.
- The app refreshes automatically and keeps the last good snapshot during temporary failures.
- A movable, optional always-on-top widget supports stacked, horizontal, paged, and separate-provider layouts.
- One of nine selectable companions reacts to current pressure and optional local trend history.
- Korean and English, light/dark/auto appearance, and the three existing themes remain available.
- Sensitive session material stays local and encrypted for the current Windows user.

### Continuing non-goals and safety boundaries

- Do not rewrite or refactor the macOS app while establishing the Windows port.
- Do not ship every companion animation before live Codex usage works end to end.
- Do not build a browser scraper for ChatGPT usage settings.
- Do not implement automatic reset-credit consumption.
- Do not require the ChatGPT or Codex GUI to stay open.
- Do not promise exact macOS menu-bar text parity in the Windows notification area.

## 3. Decisions already made

### 3.1 UI framework: WPF on .NET 10 LTS

Use WPF rather than WinUI 3 for this port.

Reasons:

- WPF directly supports borderless, transparent, movable, topmost desktop windows.
- `System.Windows.Forms.NotifyIcon` is a stable notification-area integration and can coexist with a WPF app.
- WebView2 has an official WPF control.
- WPF data binding, vector shapes, and animation are sufficient for quota rings and the companion catalog.
- The app does not need Windows App SDK features that would justify the additional packaging and runtime complexity of WinUI 3.

Use the currently supported .NET 10 LTS SDK and pin exact package versions in the project files. Do not use floating `*` package versions.

### 3.2 Repository layout: one repo, separate platform subtree

Do not attempt to compile Swift on Windows. Add a Windows solution under `windows/` and keep platform boundaries obvious.

```text
windows/
├── ClaudeUsage.Windows.sln
├── Directory.Build.props
├── src/
│   ├── ClaudeUsage.Core/
│   │   ├── Models/
│   │   ├── Parsing/
│   │   ├── Services/
│   │   └── History/
│   └── ClaudeUsage.Windows/
│       ├── App.xaml
│       ├── Assets/
│       ├── Controls/
│       ├── Platform/
│       ├── Resources/
│       ├── ViewModels/
│       └── Views/
└── tests/
    └── ClaudeUsage.Core.Tests/
        └── Fixtures/
```

`ClaudeUsage.Core` must not reference WPF, WinForms, WebView2, registry, or Windows-only UI types. The Windows project owns tray, window, login, startup, file-location, and secret-storage integration.

### 3.3 First release shape

1. Developer alpha: self-contained `win-x64` portable ZIP plus unsigned structural MSIX/App Installer artifacts. **Local packaging, CI validation, checksums, SPDX SBOM, and license notices are implemented; clean-machine validation and any public upload remain pending.**
2. Beta: signed x64 MSIX with the permanent package identity and HTTPS App Installer update feed.
3. Public release: the exact validated signed candidate, clean install/update/uninstall evidence, and Windows download added to the website.

Do not block local functional validation on MSIX signing, but never publish the unsigned structural MSIX produced by ordinary CI. The release workflow creates a signed candidate behind the `windows-signing` environment and publishes that exact artifact only after a separate `windows-production-release` approval.

## 4. macOS source-of-truth map

Read these files before porting each subsystem. Preserve behavior, not Swift syntax.

| Concern | macOS source of truth | Windows responsibility |
|---|---|---|
| Claude response normalization, including Fable | `Sources/ClaudeUsage/Models/UsageData.swift` | Port parser and fixtures to `ClaudeUsage.Core` |
| Claude organization and usage requests | `Sources/ClaudeUsage/Services/UsageService.swift` | `HttpClient` service with the same request sequence |
| Claude login and cookie capture | `Sources/ClaudeUsage/Services/LoginWindowController.swift` | WebView2 login window and cookie manager |
| Claude cookie storage | `Sources/ClaudeUsage/Services/CookieStore.swift` | DPAPI-protected current-user storage |
| Codex app-server process/RPC | `Sources/ClaudeUsage/Services/CodexAppServerUsageService.swift` | Redirected `codex.exe app-server` process |
| Codex normalized counters | `Sources/ClaudeUsage/Models/OpenAIUsageData.swift` | Port models and dynamic counter construction |
| Independent provider state and refresh | `Sources/ClaudeUsage/Services/UsageViewModel.swift` | Windows view model/orchestrator |
| Claude Code local token total | `Sources/ClaudeUsage/Services/ClaudeLocalTokenUsageService.swift` | Scan `%USERPROFILE%\.claude\projects\**\*.jsonl` |
| History, trend, and companion mood | `Sources/ClaudeUsage/Models/UsageHistory.swift` and `UsageHistoryStore.swift` | Preserve cadence, retention, and thresholds |
| Companion catalog | `docs/COMPANION_CATALOG.md` and `docs/MIMO_BEHAVIOR_SPEC.md` | Port the shared state machine before detailed character animation |
| Privacy and provider constraints | `docs/USAGE_HISTORY_AND_POLICY.md` | Keep Windows README and installer disclosure aligned |
| Widget layouts | `Sources/ClaudeUsage/Views/WidgetView.swift` | WPF windows and layout controls |
| Themes and usage colors | `DesignSystem.swift` and `ThemeStore.swift` | WPF resource dictionaries |
| Settings defaults | `AppSettings.swift` and `Localization.swift` | Versioned local settings JSON and `.resx` resources |
| Rendering regression coverage | `Tests/ClaudeUsageTests/WidgetLayoutTests.swift` | WPF screenshot/layout tests where practical |
| Parser and history coverage | `Tests/ClaudeUsageTests/*.swift` | Port equivalent xUnit tests first |

## 5. Behavioral contracts that must not drift

### 5.1 Provider state and refresh

- Claude and Codex load independently.
- Refresh immediately at startup, then every 60 seconds.
- Manual refresh cancels or supersedes the prior refresh safely.
- Fetch the two providers concurrently.
- A transient failure must retain a previously loaded snapshot.
- Claude authentication failure clears only the Claude session and returns Claude to `needsLogin`.
- Codex failure must not hide or reset Claude data.
- Do not show `0%` when a source is unavailable; show an unavailable or sign-in state.
- Local Claude token scanning is performed only when history is enabled and at most every five minutes.

Suggested Windows state shape:

```csharp
public enum ProviderLoadState
{
    NeedsLogin,
    Unavailable,
    Loading,
    Loaded,
    Error
}
```

Store the last good value separately from the current state so an error message can coexist with non-stale UI data.

### 5.2 Claude quota source and parsing

Request sequence:

1. `GET https://claude.ai/api/organizations`
2. Select the first decoded organization, matching current behavior.
3. `GET https://claude.ai/api/organizations/{organizationId}/usage`
4. Send the user's Claude cookie string, `Referer: https://claude.ai/`, JSON accept headers, and the default Windows WebView/HTTP user agent.
5. Treat 401 and 403 as an expired Claude session.

Important parser rules:

- Base fields are `five_hour` and `seven_day`.
- Known optional fields include Sonnet, Opus, Omelette/Claude Design, and Fable.
- Fable was proven to arrive inside nested `limits`, identified by values such as `scope.model.display_name = Fable`; it is not reliably a top-level `seven_day_fable` field.
- A Fable reset follows the weekly reset when a trustworthy weekly reset is present.
- Accept percentage keys such as `utilization`, `used_percent`, `percentage`, and `percent`.
- Normalize values in `[0, 1]` to percentages by multiplying by 100.
- Reject five-hour candidates while selecting a Fable weekly candidate.
- Preserve unknown `seven_day_*` counters rather than dropping them.
- Never substitute the five-hour percentage for a missing model percentage.

Port the parser tests before connecting live Claude login. A parser change is complete only when a redacted fixture demonstrates the changed payload shape.

### 5.3 Codex app-server contract

The Windows MVP should require an installed, signed-in Codex CLI available in `PATH`. Desktop-app executable discovery can be added after the vertical slice works.

The ChatGPT/Codex GUI does not need to stay open. ClaudeUsage launches a short-lived local app-server process for each refresh.

Executable discovery order after MVP:

1. A user-selected executable path saved in settings and revalidated on use.
2. `where.exe codex` / `PATH` resolution.
3. Known per-user Codex installation locations discovered from environment and package metadata.
4. Installed Microsoft Store Codex package location discovered through Windows package APIs.
5. A setup action that opens the official Codex install instructions.

Do not recursively scan `C:\Program Files\WindowsApps`; it is protected and versioned. Do not hardcode one Store package version path.

Start the process with:

- executable: resolved `codex.exe`
- arguments: `app-server`
- `UseShellExecute = false`
- redirected stdin, stdout, and stderr
- UTF-8 newline-delimited JSON
- no console window
- 20-second total timeout

RPC sequence, matching the working macOS client:

```json
{"method":"initialize","id":0,"params":{"clientInfo":{"name":"claude_usage","title":"ClaudeUsage","version":"1.0"},"capabilities":{}}}
{"method":"initialized","params":{}}
{"method":"account/rateLimits/read","id":7}
{"method":"account/usage/read","id":8}
```

Rules:

- Wait for the `initialize` response before sending `initialized` and account requests.
- Read stdout one complete line at a time.
- Drain stderr concurrently to prevent process blocking, but never log secrets.
- Require a valid rate-limit response.
- Token activity is optional; a failed or unsupported `account/usage/read` must not discard valid rate limits.
- Terminate the process tree after success, timeout, or cancellation.
- Support `rateLimits` and `rateLimitsByLimitId`.
- Select the standard `codex` limit without assuming dictionary order.
- Convert `windowDurationMins` to seconds and `resetsAt` from Unix seconds.
- Preserve every unknown model-specific limit dynamically.
- Detect code-review limits separately when the normalized identity contains `code_review` or `code review`.
- Hide Codex Spark only at presentation time when the setting is off. Never remove it from fetched data.
- Parse optional `rateLimitResetCredits`, including available count, status, grant time, expiry, title, and description.
- Reset-credit advice is read-only. Never invoke a consume method automatically.
- Do not read `%USERPROFILE%\.codex\auth.json` or copy OpenAI tokens.

The official app-server also provides `account/read` and managed login methods. Those may be used in a later milestone for a better setup flow, but Phase 2 should reuse an already signed-in Codex installation.

### 5.4 Local token aggregation

Claude Code source:

```text
%USERPROFILE%\.claude\projects\**\*.jsonl
```

For files modified today, process JSONL entries whose top-level timestamp is today and not in the future. Read only:

- `requestId`
- `message.id`
- `timestamp`
- `message.usage.input_tokens`
- `message.usage.output_tokens`
- `message.usage.cache_creation_input_tokens`
- `message.usage.cache_read_input_tokens`

Deduplicate by `requestId|message.id|timestamp`. Numeric strings must be accepted. Do not retain prompts, responses, filenames, project names, or full log entries.

Codex token activity comes only from `account/usage/read` daily buckets. It may lag behind a currently active task. Do not infer quota percentage from token totals.

### 5.5 History and companions

Windows history location:

```text
%LOCALAPPDATA%\ClaudeUsage\usage-history.json
```

Preserve these rules:

- History is off by default.
- Sample every five minutes.
- Force a sample when maximum pressure falls by at least 15 percentage points.
- Retain 14 days and at most 4,200 samples.
- Pressure is the highest visible percentage across Claude and Codex standard/model counters.
- Trend uses the most recent one-hour segment after the last detected reset.
- A reset remains a refreshed state for 30 minutes.
- Today tokens are the sum of available Claude and Codex daily totals.
- Deleting history deletes only this file, not Claude Code logs or Codex account buckets.

Existing mood thresholds:

| Mood | Rule |
|---|---|
| Refreshed | reset detected and pressure below 60 |
| Tired | pressure at least 90 or pace at least 45 percentage points/hour |
| Sleepy | pressure at least 75 or pace at least 28/hour |
| Focused | pressure at least 50 or pace at least 14/hour |
| Calm | lower connected usage |
| Waiting | no provider usage available |

Port the deterministic state machine before recreating every body animation. Character-specific behavior is in `docs/COMPANION_CATALOG.md`; the original action catalogue and speech-bubble priority remain in `docs/MIMO_BEHAVIOR_SPEC.md`.

### 5.6 Settings defaults

Use `%LOCALAPPDATA%\ClaudeUsage\settings.json` with a `schemaVersion` field and atomic writes.

Defaults:

| Setting | Default |
|---|---|
| Always on top | on |
| Appearance | auto |
| Companion enabled | on |
| Selected companion | Mimo |
| Usage history | off |
| Widget layout | stacked |
| Separate Claude widget | on |
| Separate Codex widget | on |
| Show Codex Spark | off |
| Theme | Daangn |
| Language | Korean when the OS language starts with `ko`, otherwise English |

Do not store the Claude cookie in this settings file.

## 6. Platform mapping

| macOS implementation | Windows replacement |
|---|---|
| SwiftUI | WPF XAML + C# |
| `MenuBarExtra` | `System.Windows.Forms.NotifyIcon` hosted by WPF |
| Status item text with two percentages | One tray icon + tooltip + click flyout |
| `NSPanel` | Borderless WPF `Window` with `ShowInTaskbar=false` |
| `.statusBar` panel level | WPF `Topmost` setting |
| `WKWebView` | Microsoft Edge WebView2 WPF control |
| macOS Keychain | DPAPI `ProtectedData` with `CurrentUser` scope |
| `UserDefaults` | Versioned JSON under `%LOCALAPPDATA%` |
| Application Support | `%LOCALAPPDATA%\ClaudeUsage` |
| Login item | ZIP: optional `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`; MSIX: identity-based `windows.startupTask` plus background launcher |
| `.icns` | Multi-size `.ico` plus PNG assets |
| Xcode/XCTest | Visual Studio or `dotnet` + xUnit |
| DMG | Zip for alpha, signed MSIX/MSIX bundle for release |

### Notification-area divergence

Windows notification icons do not provide the same inline text surface as a macOS status item. Recommended behavior:

- Use one ClaudeUsage icon in the notification area.
- Tooltip: `Claude 37% · Codex 39%` or a localized connection message.
- Left-click: open the full usage flyout near the cursor/taskbar and clamp it to the monitor work area.
- Right-click: context menu with Show/Hide Widget, Refresh, Settings, and Quit.
- Change icon state for normal/warning/danger using shape as well as color.

Do not squeeze two tiny percentages into a 16-pixel tray icon. A later experiment may offer two provider icons, but that is not an MVP requirement.

## 7. Windows implementation record and remaining release work

Phase 0–5 product code is integrated. Checked items below describe implemented/reconnaissance work. Unchecked live, visual, clean-machine, signing, and publication items remain acceptance or release gates; they do not indicate that the Phase 0–5 feature code is absent.

### Phase 0: machine and live-source reconnaissance — complete

Goal: prove the target machine can build WPF and launch a signed-in Codex app-server before writing product UI.

- [x] Clone this repository and establish the source baseline.
- [x] Record the baseline commit in the Windows work log.
- [x] Verify a Windows 11 x64 WPF-capable toolchain.
- [x] Install the pinned .NET 10 SDK and verify the CLI/runtime.
- [x] Verify the WebView2 Runtime is present.
- [x] Locate Codex from an official OpenAI distribution.
- [x] Reuse an official signed-in Codex session.
- [x] Record a redacted Codex version and executable-path category.
- [x] Start `codex app-server` and confirm the initialize/rate-limit sequence returns JSONL.
- [x] Save only redacted fixtures without account identifiers or secrets.
- [x] Confirm the optional `%USERPROFILE%\.claude\projects` input location.

Exit criteria:

- WPF hello-world app runs on the target Windows machine.
- `codex app-server` returns either valid rate limits or a clear authentication error.
- No dependency on an open Codex GUI is observed.

### Phase 1: solution and pure core — complete

Goal: establish testable data contracts before desktop plumbing.

- [x] Create `ClaudeUsage.Windows.sln`.
- [x] Add `ClaudeUsage.Core`, `ClaudeUsage.Windows`, and `ClaudeUsage.Core.Tests`.
- [x] Target .NET 10 and enable nullable reference types and warnings.
- [x] Add exact-version WebView2 only to the Windows project.
- [x] Add WPF/WinForms integration for `NotifyIcon` only to the Windows project.
- [x] Port quota-window, organization, Codex limit, reset-credit, token-activity, history, and trend models.
- [x] Port the dynamic Codex counter builder.
- [x] Port Claude `UsageData` normalization, especially nested Fable selection.
- [x] Port parser/history fixture tests to xUnit.
- [x] Add redacted JSON fixtures under `windows/tests/ClaudeUsage.Core.Tests/Fixtures`.

Exit criteria:

- `dotnet test windows/ClaudeUsage.Windows.sln` passes.
- Unknown GPT model names appear without code changes.
- Nested Fable is distinct from five-hour usage and uses the weekly reset.
- Malformed optional model limits do not break standard limits.

### Phase 2: Codex-first vertical slice — complete

Goal: ship one complete, source-backed Windows path before adding Claude login.

- [x] Implement `CodexExecutableLocator` with manual-path, PATH, and supported desktop-install discovery.
- [x] Implement cancellable, line-oriented `CodexAppServerClient`.
- [x] Add bounded timeout and process-tree cleanup.
- [x] Fetch rate limits and optional token activity after initialization.
- [x] Map transient errors without destroying the last good snapshot.
- [x] Build a `UsageCoordinator` with 60-second refresh and superseding manual refresh.
- [x] Create one tray icon and localized tooltip.
- [x] Create a click flyout showing plan, five-hour, weekly, dynamic models, reset times, reset credits, and today's Codex tokens.
- [x] Add manual refresh, Settings, widget, and Quit actions.
- [x] Display setup guidance when `codex.exe` is unavailable or signed out.

Exit criteria:

- Values match the same account's `chatgpt.com/#settings/Usage` or Codex UI at the same observation time, allowing for refresh delay.
- Closing the Codex GUI does not stop refreshes as long as the executable and login session remain available.
- A temporary app-server failure leaves the previous values visible with a stale/error indicator.
- The tray icon is disposed when the app exits.
- A zipped self-contained `win-x64` build runs on a second Windows account/machine used for testing.

The historical Phase 0–2 checkpoint is preserved in `windows/PHASE_0_2_REPORT.md`. Its test count, screenshot, artifact name, and SHA refer only to that checkpoint. Clean-account/machine validation of the current integrated package remains a Phase 6 release gate.

### Phase 3: Claude login and quota source — complete in the developer alpha

Goal: add Claude without weakening local security or parser resilience.

- [x] Add a dedicated WebView2 login window for `https://claude.ai/login`.
- [x] Use an isolated temporary WebView2 profile/data folder, not the user's general Edge profile.
- [x] Poll/react to navigation and call `GetCookiesAsync("https://claude.ai")`.
- [x] Accept session cookie names `sessionKey`, `__Secure-next-auth.session-token`, and `next-auth.session-token`.
- [x] Capture only recognized root-path session cookies whose domain is exactly `claude.ai` or `.claude.ai`.
- [x] Encrypt the final cookie header using DPAPI `CurrentUser` scope.
- [x] Clear browsing data and remove the temporary profile immediately or on a later cleanup attempt if files remain locked.
- [x] Avoid logging cookie values or raw provider payloads.
- [x] Add login, logout, and login-data cleanup paths.
- [x] Port organization and usage HTTP requests.
- [x] Apply the tolerant dynamic parser and last-good-state behavior.
- [x] Add an experimental-provider toggle and visible policy warning based on `docs/USAGE_HISTORY_AND_POLICY.md`.

Exit criteria:

- Fresh login, restart, refresh, session expiry, logout, and relogin all work.
- Claude five-hour, weekly, Fable, and other model values match the source response.
- An expired Claude session does not affect Codex.
- The plaintext cookie is not present in settings, logs, crash reports, or package output.

### Phase 4: widget and settings parity — feature implementation complete

Goal: reproduce the established workflows with Windows-native behavior.

- [x] Build the combined tray flyout with independent Claude/Codex states.
- [x] Build a movable floating widget with `ShowInTaskbar=false` and optional `Topmost`.
- [x] Add stacked layout at 240 logical pixels wide.
- [x] Add horizontal layout at approximately 480 logical pixels wide.
- [x] Add paged layout with stable dimensions while switching providers.
- [x] Add separate Claude and Codex windows.
- [x] Save each window position and clamp it to the current monitor work area.
- [ ] Test taskbars on bottom, top, left, and right.
- [ ] Test 100%, 125%, 150%, and 200% display scaling.
- [x] Add Daangn, Toss, and Hybrid resource dictionaries.
- [x] Add light, dark, and system appearance.
- [x] Port Korean and English strings into WPF resource dictionaries.
- [x] Add Spark visibility and the Windows settings defaults.

Exit criteria:

- No text clipping at stress-case model names and reset values.
- Switching layout never moves quota rings or the selected companion as a side effect.
- Separate-provider windows persist independent positions.
- Flyout and widget remain fully inside the active monitor.
- Keyboard navigation and screen-reader labels cover every actionable control.

### Phase 5: companions and optional history — complete in the developer alpha

Goal: restore companion behavior after data and layout contracts are stable.

- [x] Port history persistence, trend calculations, mood resolution, and tests.
- [x] Implement a fixed-footprint `CompanionControl` using WPF shapes/canvas.
- [x] Keep quota UI geometry independent from companion pose changes.
- [x] Add persisted selection for Mimo, Lumi, Kumo, Dot, Navi, Bori, Muru, Tori, and Pico.
- [x] Implement reduced-motion pose behavior.
- [x] Port deterministic idle, pressure, reset, tired, and reset-credit presentation priorities.
- [x] Add a reserved speech-bubble area that cannot resize the widget.
- [x] Keep reset-credit advice read-only; no consume command is exposed.
- [x] Add opt-in sampling, clear-history behavior, and bilingual privacy text.

Exit criteria:

- Mood thresholds match the existing unit tests.
- Animation changes pose without changing the control footprint.
- Text does not overlap the companion, quota rings, navigation, or settings.
- Disabling history stops sampling and local Claude-log scanning.

### Phase 6: packaging, CI, and release — foundation complete; release gates pending

Goal: produce a reproducible Windows artifact and installation path.

- [x] Add a `windows-latest` GitHub Actions job for restore, test, and package.
- [x] Restrict the current package to `win-x64`; add `win-arm64` only after a real-device test.
- [x] Produce a self-contained ZIP and SHA-256 artifact for alpha testing.
- [x] Add script-driven MSIX/App Installer packaging with pinned Windows SDK tooling.
- [x] Configure templated app identity, icons, display name, capabilities, and explicit user-data retention policy; production identity values remain an external release gate.
- [x] Use an in-app, per-user `HKCU Run` setting for the ZIP alpha.
- [ ] Sign the public installer and verify SmartScreen/install behavior.
- [ ] Verify upgrade and uninstall paths do not delete unrelated Codex/Claude data.
- [x] Add Windows installation, privacy, and data-source wording to both READMEs, the website, Windows README, and release notes.
- [x] Add a manual signed-candidate workflow with distinct `windows-signing` and `windows-production-release` environment gates; public publication defaults off.
- [ ] Validate the current integrated ZIP under a clean Windows account or clean machine.
- [ ] Explicitly authorize and run a public GitHub prerelease with checksums and Windows requirements.

Exit criteria:

- Clean Windows runner builds from a fresh checkout.
- Tests pass before packaging.
- Installer or zip runs without Visual Studio installed.
- Download checksum matches the release asset.
- The Windows release notes identify the required Codex install/login state and Claude endpoint risk.

The prerelease workflow intentionally does not trigger from tag pushes. `workflow_dispatch` plus the boolean confirmation and environment gate prevents an ordinary tag from publishing an unsigned build. This safety mechanism prepares a release path; it is not evidence that a public Windows prerelease has been authorized or published.

## 8. Initial scaffold commands on Windows

Run from the repository root in PowerShell after installing the .NET 10 SDK:

```powershell
New-Item -ItemType Directory -Force -Path windows/src, windows/tests | Out-Null

dotnet new sln --format sln -n ClaudeUsage.Windows -o windows
dotnet new classlib -n ClaudeUsage.Core -o windows/src/ClaudeUsage.Core
dotnet new wpf -n ClaudeUsage.Windows -o windows/src/ClaudeUsage.Windows
dotnet new xunit -n ClaudeUsage.Core.Tests -o windows/tests/ClaudeUsage.Core.Tests

dotnet sln windows/ClaudeUsage.Windows.sln add windows/src/ClaudeUsage.Core/ClaudeUsage.Core.csproj
dotnet sln windows/ClaudeUsage.Windows.sln add windows/src/ClaudeUsage.Windows/ClaudeUsage.Windows.csproj
dotnet sln windows/ClaudeUsage.Windows.sln add windows/tests/ClaudeUsage.Core.Tests/ClaudeUsage.Core.Tests.csproj

dotnet add windows/src/ClaudeUsage.Windows/ClaudeUsage.Windows.csproj reference windows/src/ClaudeUsage.Core/ClaudeUsage.Core.csproj
dotnet add windows/tests/ClaudeUsage.Core.Tests/ClaudeUsage.Core.Tests.csproj reference windows/src/ClaudeUsage.Core/ClaudeUsage.Core.csproj

dotnet test windows/ClaudeUsage.Windows.sln
```

Then edit the WPF project to include:

```xml
<PropertyGroup>
  <TargetFramework>net10.0-windows</TargetFramework>
  <UseWPF>true</UseWPF>
  <UseWindowsForms>true</UseWindowsForms>
  <Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings>
</PropertyGroup>
```

Add the current stable WebView2 package with an exact version selected on the Windows machine:

```powershell
dotnet add windows/src/ClaudeUsage.Windows/ClaudeUsage.Windows.csproj package Microsoft.Web.WebView2 --version <PINNED_STABLE_VERSION>
```

Do not put `<PINNED_STABLE_VERSION>` into the project. Resolve the current stable version, record why it was selected, and commit the exact number.

Developer alpha publish command:

```powershell
dotnet publish windows/src/ClaudeUsage.Windows/ClaudeUsage.Windows.csproj `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:PublishSingleFile=false `
  -o windows/artifacts/win-x64
```

Keep `PublishSingleFile=false` initially because WebView2 includes native runtime components that must be tested before attempting single-file packaging.

## 9. Test and acceptance matrix

The corresponding automated test code and fixtures are present, but this matrix records the final release audit. Leave an item unchecked until it has been rerun against the current integrated tree or manually observed on the target configuration. Do not copy the historical Phase 0–2 test count or ZIP hash as a current result.

### Core automated tests

- [ ] Standard Codex primary/secondary windows map correctly.
- [ ] `rateLimitsByLimitId` order does not affect standard-limit selection.
- [ ] Unknown GPT names create dynamic five-hour/weekly counters.
- [ ] Spark can be hidden without mutating fetched data.
- [ ] Reset-credit available/consumed/expired status is correct.
- [ ] Token daily bucket and summary fields map correctly.
- [ ] Token endpoint absence does not fail rate limits.
- [ ] Nested Fable parses independently and follows the weekly reset.
- [ ] Percentage values in 0-1 and 0-100 forms normalize correctly.
- [ ] Malformed optional counters do not destroy base usage.
- [ ] Claude JSONL tokens deduplicate and ignore prior-day entries.
- [ ] History cadence, reset segmentation, retention, and moods match Swift tests.

### Live Windows checks

- [ ] Codex installed in PATH.
- [ ] Codex unavailable state.
- [ ] Codex signed-out state.
- [ ] Codex GUI closed while refresh succeeds.
- [ ] Claude fresh login and Google/OAuth popup behavior.
- [ ] Claude 401/403 expiry and relogin.
- [ ] Network offline and recovery.
- [ ] System sleep/wake and clock/time-zone change.
- [ ] Multiple displays and DPI scales.
- [ ] Taskbar auto-hide and non-bottom placement.
- [ ] App restart with persisted settings/window positions.
- [ ] History clear and app uninstall behavior.

### Visual checks

- [ ] 240-pixel stacked widget.
- [ ] 480-pixel horizontal widget.
- [ ] Paged provider switching.
- [ ] Two separate provider widgets.
- [ ] Korean and English longest strings.
- [ ] Long unknown model names.
- [ ] 0%, 9%, 99%, and 100% ring labels.
- [ ] Reset time with day/hour/minute variants.
- [ ] Light and dark appearance across all themes.
- [ ] All nine companions in still, focused, tired, reset, and reduced-motion states.

## 10. Security and policy gates

### Required security behavior

- Encrypt Claude cookies with DPAPI current-user scope.
- Use a temporary WebView2 profile and clear it after the cookie is transferred to DPAPI storage.
- Keep OpenAI authentication owned by Codex.
- Never log cookies, access tokens, full RPC responses, or full Claude responses in release builds.
- Redact organization/account identifiers from fixtures.
- Use atomic file writes for settings and history.
- Validate any user-selected executable before launch.
- Quote paths through `ProcessStartInfo.ArgumentList`; do not build a shell command string.
- Use HTTPS only for network requests.

### Distribution gate

OpenAI usage must remain on documented Codex app-server methods. Do not restore the removed private `wham/usage` request and do not scrape the ChatGPT Usage page.

Claude quota retrieval still uses an undocumented authenticated claude.ai endpoint. Before public or commercial Windows distribution:

1. Re-read `docs/USAGE_HISTORY_AND_POLICY.md`.
2. Re-check current Anthropic terms.
3. Prefer written permission or a documented supported quota interface.
4. Keep Codex-only and local-history features able to ship independently if Claude cloud access must be disabled.

## 11. Known Windows risks

| Risk | Mitigation |
|---|---|
| Store-installed `codex.exe` lives under a protected, versioned path | PATH/manual path first; package APIs later; never hardcode a version directory |
| App-server payload changes | Redacted live fixture, tolerant optional fields, dynamic model parsing |
| WebView2 OAuth opens a popup | Handle `NewWindowRequested` in the same login window or an owned child window |
| Cookie accidentally appears in logs | Central redaction and no raw response logging in release builds |
| Transparent WPF window has DPI/performance quirks | Test every target scale; animate fixed subparts only; honor Reduce Motion |
| Tray flyout opens off-screen | Position against current monitor work area and taskbar orientation |
| Windows hides notification icons | Keep tooltip/context menu robust; document how to pin the icon |
| Unsigned alpha triggers warnings | Disclosed ZIP plus manual confirmation/environment-gated prerelease workflow; signed installer before a stable public release |
| Daily Codex tokens lag active work | Treat token totals as supporting information, never a quota substitute |
| Claude endpoint policy changes | Keep provider feature-gated and preserve Codex-only operation |

## 12. Public-release definition of done

Phase 0–5 developer-alpha feature integration is complete. A stable/public Windows release is complete only when all of the following are true:

- A clean Windows machine can install or unpack and launch the app.
- Claude and Codex provider states are independent.
- Live values and reset times have been compared against the source account.
- Dynamic Fable/GPT model counters do not require model-name code changes.
- Codex works with its GUI closed.
- Four widget layouts and independent positions are stable across DPI changes.
- The selected companion does not move the quota UI or resize its footprint during animation.
- History remains opt-in, local, bounded, and deletable.
- No sensitive material is present in logs, settings, fixtures, or release artifacts.
- Automated tests and Windows visual checks pass.
- The release artifact has a published checksum and installation disclosure.
- README, website, and release notes explain Windows requirements and data sources.

## 13. What the Windows agent should report after verification or release work

Use this structure for the next clean-machine, signing, or publication handback. Report test totals and artifact hashes only from commands run against the current integrated tree:

```text
Phase completed:
Commit:
Windows version and architecture:
Codex version and resolved executable path category (PATH/manual/Store; do not expose username):
What works:
What remains:
Tests run and result:
Screenshots/artifacts:
Payload differences discovered:
Security/privacy notes:
Blocking decision needed from the user:
```

## 14. Primary references

- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy) - .NET 10 is the current active LTS baseline at handoff time.
- [WPF overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/) - Windows desktop UI framework.
- [WPF windows](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/windows/) - window sizing and lifecycle.
- [WebView2 in WPF](https://learn.microsoft.com/en-us/microsoft-edge/webview2/get-started/wpf) - embedded Claude login.
- [WebView2 cookie manager](https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2cookiemanager.getcookiesasync) - Claude cookie retrieval.
- [NotifyIcon](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.notifyicon) - Windows notification-area integration.
- [Windows DPAPI / ProtectedData](https://learn.microsoft.com/en-us/dotnet/standard/security/how-to-use-data-protection) - current-user cookie protection.
- [MSIX desktop packaging](https://learn.microsoft.com/en-us/windows/msix/package/packaging-uwp-apps) - installer packaging path.
- [.NET 10 solution format change](https://learn.microsoft.com/en-us/dotnet/core/compatibility/sdk/10.0/dotnet-new-sln-slnx-default) - why the scaffold command explicitly requests `.sln`.
- [Codex repository and Windows install](https://github.com/openai/codex) - official Codex CLI distribution.
- [Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md) - JSONL transport and account methods.
