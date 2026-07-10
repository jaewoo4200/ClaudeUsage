# ClaudeUsage Windows Port Handoff

Last updated: 2026-07-10

## 0. Handoff status

- macOS functional baseline: ClaudeUsage `1.5.0` (build `14`)
- Windows implementation: not started
- Recommended first target: Windows 11 x64
- Recommended stack: .NET 10 LTS + WPF
- Repository strategy: keep the macOS app unchanged and add a sibling `windows/` solution
- First usable milestone: Codex usage in a Windows tray flyout
- Full parity milestone: Claude + Codex + four widget layouts + nine companions + installer

This is a native Windows port, not a direct rebuild of the SwiftUI project. WPF is Windows-only, so the final UI, tray behavior, WebView2 login, packaging, and visual QA must be completed on a Windows machine or a Windows CI runner. A Mac can still review the C# core and documentation, but it cannot provide trustworthy WPF runtime verification.

## 1. Copy-paste kickoff prompt for the Windows agent

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

Implement only Phase 0 through Phase 2 first:
1. verify the Windows development environment and the installed Codex executable,
2. create the windows/ .NET 10 WPF solution and pure C# core/test projects,
3. port the Codex app-server JSON-RPC client and parsing tests,
4. show live Codex 5-hour, weekly, model-specific limits, reset time, reset-credit count, and today's token bucket in a minimal Windows tray flyout.

Keep Sources/ClaudeUsage and the current macOS behavior unchanged. Do not scrape chatgpt.com, do not read OpenAI token files, do not hardcode new model names, and do not consume reset credits. Preserve the last good usage snapshot on transient refresh errors. Run tests and provide a Windows screenshot plus a zipped win-x64 build artifact before moving to Claude login or full widget parity.
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

### Explicit non-goals for the first milestone

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

1. Developer alpha: self-contained `win-x64` publish folder zipped as an artifact.
2. Beta: signed MSIX or MSIX bundle.
3. Public release: signed installer, update path, uninstall verification, and Windows download added to the website.

Do not block the first functional build on MSIX signing. An unsigned public MSIX produces a poor installation experience, so use a zip for internal validation until a signing decision is made.

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
| Login item | Optional `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry |
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

## 7. Windows implementation plan

### Phase 0: machine and live-source reconnaissance

Goal: prove the target machine can build WPF and launch a signed-in Codex app-server before writing product UI.

- [ ] Clone this repository and confirm `git status` is clean.
- [ ] Record `git rev-parse HEAD` in the Windows work log.
- [ ] Install the current Visual Studio 2022 release with `.NET desktop development` and a Windows 11 SDK.
- [ ] Install the .NET 10 SDK and verify `dotnet --info`.
- [ ] Verify the WebView2 Runtime is present.
- [ ] Install Codex from an official OpenAI distribution if it is not already installed.
- [ ] Sign in with `codex login` or an official managed Codex login flow.
- [ ] Record `where.exe codex` and `codex --version`.
- [ ] Manually start `codex app-server` and confirm the initialize/rate-limit sequence returns JSONL.
- [ ] Save only a redacted rate-limit fixture; remove account identifiers and secrets.
- [ ] Confirm whether `%USERPROFILE%\.claude\projects` exists.

Exit criteria:

- WPF hello-world app runs on the target Windows machine.
- `codex app-server` returns either valid rate limits or a clear authentication error.
- No dependency on an open Codex GUI is observed.

### Phase 1: solution and pure core

Goal: establish testable data contracts before desktop plumbing.

- [ ] Create `ClaudeUsage.Windows.sln`.
- [ ] Add `ClaudeUsage.Core`, `ClaudeUsage.Windows`, and `ClaudeUsage.Core.Tests`.
- [ ] Target .NET 10 and enable nullable reference types and warnings.
- [ ] Add exact-version WebView2 only to the Windows project.
- [ ] Add WPF/WinForms integration for `NotifyIcon` only to the Windows project.
- [ ] Port quota-window, organization, Codex limit, reset-credit, token-activity, history, and trend models.
- [ ] Port the dynamic Codex counter builder.
- [ ] Port Claude `UsageData` normalization, especially nested Fable selection.
- [ ] Port the existing parser/history fixture tests to xUnit.
- [ ] Add JSON fixtures under `windows/tests/ClaudeUsage.Core.Tests/Fixtures`.

Exit criteria:

- `dotnet test windows/ClaudeUsage.Windows.sln` passes.
- Unknown GPT model names appear without code changes.
- Nested Fable is distinct from five-hour usage and uses the weekly reset.
- Malformed optional model limits do not break standard limits.

### Phase 2: Codex-first vertical slice

Goal: ship one complete, source-backed Windows path before adding Claude login.

- [ ] Implement `CodexExecutableLocator` with manual-path and PATH support first.
- [ ] Implement cancellable, line-oriented `CodexAppServerClient`.
- [ ] Add 20-second timeout and process-tree cleanup.
- [ ] Fetch rate limits and token activity concurrently after initialization.
- [ ] Map transient errors without destroying the last good snapshot.
- [ ] Build a minimal `UsageCoordinator` with 60-second refresh.
- [ ] Create one tray icon and localized tooltip.
- [ ] Create a click flyout showing plan, five-hour, weekly, dynamic models, reset times, reset credits, and today's Codex tokens.
- [ ] Add manual refresh, Settings, and Quit actions.
- [ ] Display setup guidance when `codex.exe` is unavailable or signed out.

Exit criteria:

- Values match the same account's `chatgpt.com/#settings/Usage` or Codex UI at the same observation time, allowing for refresh delay.
- Closing the Codex GUI does not stop refreshes as long as the executable and login session remain available.
- A temporary app-server failure leaves the previous values visible with a stale/error indicator.
- The tray icon is disposed when the app exits.
- A zipped self-contained `win-x64` build runs on a second Windows account/machine used for testing.

Stop here for review before Phase 3. Capture screenshots and a short live-response audit.

### Phase 3: Claude login and quota source

Goal: add Claude without weakening local security or parser resilience.

- [ ] Add a dedicated WebView2 login window for `https://claude.ai/login`.
- [ ] Use an isolated temporary WebView2 profile/data folder, not the user's general Edge profile.
- [ ] Poll or react to navigation and call `GetCookiesAsync("https://claude.ai")`.
- [ ] Accept session cookie names `sessionKey`, `__Secure-next-auth.session-token`, and `next-auth.session-token`.
- [ ] Capture only `claude.ai` and subdomain cookies.
- [ ] Encrypt the final cookie header using DPAPI `CurrentUser` scope.
- [ ] Clear all browsing data after capture, close WebView2, and remove the temporary profile folder immediately or on the next startup if files are still locked.
- [ ] Never log cookie names and values together; never log values.
- [ ] Add clear-login-data and logout actions.
- [ ] Port organization and usage HTTP requests.
- [ ] Apply the tested dynamic parser and last-good-state behavior.
- [ ] Add a prominent internal/public distribution policy gate based on `docs/USAGE_HISTORY_AND_POLICY.md`.

Exit criteria:

- Fresh login, restart, refresh, session expiry, logout, and relogin all work.
- Claude five-hour, weekly, Fable, and other model values match the source response.
- An expired Claude session does not affect Codex.
- The plaintext cookie is not present in settings, logs, crash reports, or package output.

### Phase 4: widget and settings parity

Goal: reproduce the established workflows with Windows-native behavior.

- [ ] Build the combined tray flyout with independent Claude/Codex states.
- [ ] Build a movable floating widget with `ShowInTaskbar=false` and optional `Topmost`.
- [ ] Add stacked layout at 240 logical pixels wide.
- [ ] Add horizontal layout at approximately 480 logical pixels wide.
- [ ] Add paged layout with stable dimensions while switching providers.
- [ ] Add separate Claude and Codex windows.
- [ ] Save each window position and clamp it to the current monitor work area.
- [ ] Test taskbars on bottom, top, left, and right.
- [ ] Test 100%, 125%, 150%, and 200% display scaling.
- [ ] Add Daangn, Toss, and Hybrid resource dictionaries.
- [ ] Add light, dark, and system appearance.
- [ ] Port Korean and English strings into `.resx` resources.
- [ ] Add Spark visibility and all current settings defaults.

Exit criteria:

- No text clipping at stress-case model names and reset values.
- Switching layout never moves quota rings or the selected companion as a side effect.
- Separate-provider windows persist independent positions.
- Flyout and widget remain fully inside the active monitor.
- Keyboard navigation and screen-reader labels cover every actionable control.

### Phase 5: companions and optional history

Goal: restore companion behavior after data and layout contracts are stable.

- [ ] Port history persistence, trend calculations, and mood tests first.
- [ ] Implement a fixed-footprint `CompanionControl` using WPF shapes/canvas, with Mimo as the first parity target.
- [ ] Keep the body and quota ring stationary; animate only character parts, expressions, props, and action marks.
- [ ] Add persisted selection for Mimo, Lumi, Kumo, Dot, Navi, Bori, Muru, Tori, and Pico.
- [ ] Implement reduced-motion pose changes.
- [ ] Port idle, provider-specific, rapid-use, reset, tired, and reset-credit actions in priority order.
- [ ] Add a reserved speech-bubble area that cannot resize the widget.
- [ ] Keep reset-credit advice read-only and require explicit confirmation for any future consume action.
- [ ] Add clear-history behavior and privacy text.

Exit criteria:

- Mood thresholds match the existing unit tests.
- Animation changes pose without changing the control footprint.
- Text does not overlap the companion, quota rings, navigation, or settings.
- Disabling history stops sampling and local Claude-log scanning.

### Phase 6: packaging, CI, and release

Goal: produce a reproducible Windows artifact and installation path.

- [ ] Add a `windows-latest` GitHub Actions job for restore, test, and publish.
- [ ] Publish `win-x64` first; add `win-arm64` after a real-device test.
- [ ] Produce a self-contained zip artifact for alpha testing.
- [ ] Add a Windows Application Packaging Project for MSIX when signing is ready.
- [ ] Configure app identity, icons, display name, capabilities, and uninstall cleanup.
- [ ] Decide whether startup-on-login is installer-managed or an in-app `HKCU Run` setting.
- [ ] Sign the public installer and verify SmartScreen/install behavior.
- [ ] Verify upgrade and uninstall paths do not delete unrelated Codex/Claude data.
- [ ] Add Windows installation and data-source wording to both READMEs and the website.
- [ ] Publish a GitHub prerelease with checksums and explicit Windows requirements.

Exit criteria:

- Clean Windows runner builds from a fresh checkout.
- Tests pass before packaging.
- Installer or zip runs without Visual Studio installed.
- Download checksum matches the release asset.
- The Windows release notes identify the required Codex install/login state and Claude endpoint risk.

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
| Unsigned alpha triggers warnings | Zip for internal testing; signed MSIX before public release |
| Daily Codex tokens lag active work | Treat token totals as supporting information, never a quota substitute |
| Claude endpoint policy changes | Keep provider feature-gated and preserve Codex-only operation |

## 12. Definition of done

The Windows port is complete only when all of the following are true:

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

## 13. What the Windows agent should report after each phase

Use this exact structure in the handback:

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
