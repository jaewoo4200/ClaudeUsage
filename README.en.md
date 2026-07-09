<div align="right">
  <a href="README.md">🇰🇷 한국어</a> · <b>🇺🇸 English</b>
</div>

# Claude + GPT Usage

<p align="center">
  <img src="docs/screenshots/app-icon.png" width="120" alt="App Icon">
</p>

<p align="center">
  <b>See Claude and OpenAI usage at a glance — macOS menu bar + floating widget</b>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13.0%2B-blue">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native-orange">
  <img alt="Universal" src="https://img.shields.io/badge/Universal-Intel%20%2B%20Apple%20Silicon-brightgreen">
  <img alt="Size" src="https://img.shields.io/badge/dmg-2.0MB-blueviolet">
</p>

<p align="center">
  <b>👉 <a href="#-installation-users">Install</a> · <a href="#-read-before-first-launch">First-launch guide</a> · <a href="#-is-it-safe-keychain-explained">Is it safe? (Keychain)</a></b>
</p>

---

## ✨ What is Claude Usage?

A native macOS app that shows **Claude and ChatGPT/Codex usage** in real time through a menu bar item and a floating widget. It combines Claude's 5-hour, weekly, and model limits with OpenAI's 5-hour, weekly, and server-provided model-specific limits.

- 🤖 **Claude + OpenAI**: Fetches both providers independently and presents them together
- 🧭 **Future model support**: Displays server-provided limits such as GPT-5.3-Codex-Spark and GPT-5.6 models without hardcoded model names
- 🪶 **Lightweight**: 2MB dmg, 80MB RAM, < 0.1% CPU — no problem leaving it on all day
- 🎨 **3 themes**: Daangn / Toss / Hybrid — switch live
- 🌏 **Multilingual**: Korean / English — toggle instantly
- 🔄 **Auto-refresh every 60s** plus manual refresh
- 🌑 **Dark mode** — follows system appearance
- 💻 **Universal Binary** (Intel + Apple Silicon)

## 📸 Screenshots

### Menu bar label

<p align="center">
  <img src="docs/screenshots/menubar.png" width="200" alt="Menu Bar">
</p>

> The menu bar always shows your usage like `[C] 38%`. Above 70% it changes to ⚠️, above 90% to 🛑 — using shape rather than color (macOS forces menu-bar items to be monochrome).

### Dropdown (3 themes)

<table>
  <tr>
    <td align="center"><b>🥕 Daangn</b></td>
    <td align="center"><b>💙 Toss</b></td>
    <td align="center"><b>✨ Hybrid</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/dropdown-daangn.png" width="300"></td>
    <td><img src="docs/screenshots/dropdown-toss.png" width="300"></td>
    <td><img src="docs/screenshots/dropdown-hybrid.png" width="300"></td>
  </tr>
</table>

### Floating widget (3 themes)

<table>
  <tr>
    <td align="center"><b>🥕 Daangn</b></td>
    <td align="center"><b>💙 Toss</b></td>
    <td align="center"><b>✨ Hybrid</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/widget-daangn.png" width="220"></td>
    <td><img src="docs/screenshots/widget-toss.png" width="220"></td>
    <td><img src="docs/screenshots/widget-hybrid.png" width="220"></td>
  </tr>
</table>

### Multilingual — Korean / English

<table>
  <tr>
    <td align="center"><b>🇰🇷 Korean</b></td>
    <td align="center"><b>🇺🇸 English</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/dropdown-daangn.png" width="300"></td>
    <td><img src="docs/screenshots/dropdown-daangn-en.png" width="300"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/widget-daangn.png" width="220"></td>
    <td><img src="docs/screenshots/widget-daangn-en.png" width="220"></td>
  </tr>
</table>

### Settings

<table>
  <tr>
    <td align="center"><b>🇰🇷 Korean</b></td>
    <td align="center"><b>🇺🇸 English</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings.png" width="420"></td>
    <td><img src="docs/screenshots/settings-en.png" width="420"></td>
  </tr>
</table>

> Theme / always-on-top / language — all toggle live and reflect instantly across menu bar, widget, and settings.

## 🚀 Installation (Users)

1. Download the latest `ClaudeUsage-x.x.x.dmg` from [Releases](https://github.com/jaewoo4200/ClaudeUsage/releases)
2. Open the dmg → drag to `Applications`
3. Before launching, please read ⬇️ [**Read before first launch**](#-read-before-first-launch)!

## 🔑 Read before first launch

This app is **not signed with an Apple Developer ID** (free open-source — didn't pay the $99/year fee). macOS may show two security dialogs as a result. **Both are normal and safe.**

### 1) Bypass "unidentified developer"

Depending on your macOS version:

#### macOS Sonoma (14) or later — recommended

1. Double-click `ClaudeUsage.app` → if you see **"is damaged and can't be opened"**, click **Cancel**
2. Open **System Settings → Privacy & Security**
3. Scroll down → next to **"ClaudeUsage was blocked from use"** click **"Open Anyway"**
4. Confirm the next dialog → **"Open"**

#### macOS Ventura (13) — right-click

1. In Applications, **right-click (Control+click) `ClaudeUsage.app` → "Open"**
2. Confirm dialog → **"Open"** (once only — subsequent launches work normally)

#### Terminal one-liner (works on any version, fastest)

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeUsage.app
```

Removes the macOS quarantine flag (auto-added to downloaded files). After this, normal double-click works.

### 2) Sign in & first fetch

- Click **[C] Sign in** in the menu bar → log in to claude.ai (Google supported)
- OpenAI usage connects automatically when you are signed in with a ChatGPT account through Codex or a ChatGPT app with Codex integration
- Once connected, each provider updates independently ✨

## 🔒 Is it safe? Keychain explained

Right after signing in, macOS may show this dialog:

> **"ClaudeUsage wants to access key 'app.claudeusage' in your keychain."**
> *"To allow this, enter the 'login' keychain password."*

### What is this?

When you first sign in, ClaudeUsage saves your **claude.ai session cookies in the macOS Keychain** so you don't have to re-login every time. macOS asks for permission when an **unsigned app accesses Keychain for the first time** — this is standard behavior.

### Why is it safe?

- 🔓 **Open source**: [The entire code is on GitHub](https://github.com/jaewoo4200/ClaudeUsage/tree/main/Sources/ClaudeUsage). Keychain code lives in [CookieStore.swift](https://github.com/jaewoo4200/ClaudeUsage/blob/main/Sources/ClaudeUsage/Services/CookieStore.swift) — about 28 lines.
- 🍪 **Your cookies, your Mac only**: claude.ai cookies are stored only in your local Keychain (no iCloud backup — `AfterFirstUnlockThisDeviceOnly` is set).
- 🌐 **No external transmission**: Cookies are used **only** for `claude.ai` API calls. No analytics, telemetry, or third-party servers.
- 🔐 **We don't see your password**: You log in on claude.ai's official page directly — the app never displays a password form itself.

### How is the OpenAI session handled?

- ClaudeUsage only **reads** the local Codex session at `~/.codex/auth.json`. It never stores the OpenAI token separately or writes it to logs.
- The session is sent only to `chatgpt.com` when fetching usage. No additional login window or token copy is required.
- If the file is missing or the session expires, Claude remains available and only the OpenAI section shows a connection prompt.

### What should you do?

When the dialog appears:

- ✅ **"Always Allow"** (recommended) — Enter your Mac login password once → never asked again
- ⚠️ **"Allow"** — One-time only → asks again on next fetch
- ❌ **"Deny"** — Usage data won't load

> With code signing (Apple Developer ID, $99/year) this dialog wouldn't appear at all. Since this is a free open-source app, the dialog is part of macOS's standard process.

## 🔧 Build (Developers)

### Prerequisites

```bash
# Xcode 15+ and Command Line Tools
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# xcodegen (generates .xcodeproj from project.yml)
brew install xcodegen
```

### Build

```bash
git clone https://github.com/jaewoo4200/ClaudeUsage.git
cd ClaudeUsage

# Generate Xcode project
xcodegen

# Open in Xcode, or build via CLI
open ClaudeUsage.xcodeproj
# or
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage build
```

### Package as dmg (Universal Binary)

```bash
./scripts/build-dmg.sh
# → build/ClaudeUsage-1.2.0.dmg (supports Intel + Apple Silicon)
```

### Regenerate icon

```bash
# After editing icon.svg
./scripts/build-icon.sh
# → Sources/ClaudeUsage/Resources/AppIcon.icns
```

## 🏗️ Project Structure

```
ClaudeUsage/
├── project.yml                  # xcodegen definition (project file as code)
├── scripts/
│   ├── icon.svg                 # icon source
│   ├── build-icon.sh            # SVG → .icns
│   └── build-dmg.sh             # Release Universal + dmg
├── Sources/ClaudeUsage/
│   ├── ClaudeUsageApp.swift     # @main + AppDelegate
│   ├── Models/                  # Claude/OpenAI usage response and display models
│   ├── Services/                # auth, API, ViewModel, ThemeStore, AppSettings, LanguageStore, Localization
│   ├── Views/                   # menu bar, widget, settings + design system
│   └── Resources/               # Info.plist, entitlements, AppIcon.icns
└── docs/screenshots/            # README assets
```

## 🛠️ Tech Stack

- **SwiftUI** + AppKit (native macOS)
- **WKWebView** (claude.ai OAuth/Google sign-in → cookie capture)
- **Keychain Services** (secure session cookie storage)
- **Local Codex OAuth session** (read-only access to `~/.codex/auth.json`)
- **URLSession async/await** (usage API calls)
- **NSPanel** (.statusBar level for the widget window)
- **xcodegen** (project file managed as code)

## ⚠️ Known Limitations

| Item | Detail |
|---|---|
| Unofficial API | `claude.ai/api/organizations/.../usage` is undocumented. May break if Anthropic changes it |
| OpenAI usage API | `chatgpt.com/backend-api/wham/usage` is internal and may require updates if OpenAI changes its response |
| Session expiry | When claude.ai cookies expire, you'll need to sign in again (the app shows a prompt) |
| OpenAI connection | Requires a local Codex session; sign in again through Codex/ChatGPT if it expires |
| Single account | One account per provider at a time |
| Code signing | Not signed with Apple Developer ID — first run needs right-click → Open |

## 🗺️ Roadmap

- [x] 🌑 **Dark mode** — added in v1.1.0
- [x] 🤖 **GPT / OpenAI usage** — added in v1.2.0
- [ ] 🔔 macOS notifications at 70% / 90%
- [ ] 📊 Usage history graph (local SQLite)
- [ ] 👥 Multiple organization accounts
- [ ] 🖥️ macOS Sonoma+ desktop widget (WidgetKit)

Contributions welcome — feel free to open issues or PRs.

## 📜 Disclaimer

This is an **independent open-source project, not affiliated with Anthropic or OpenAI**.

- It calls **undocumented internal APIs** of claude.ai. Behavior may break if these change.
- OpenAI usage also relies on an **undocumented internal ChatGPT API**.
- Use is at your own risk. Please comply with claude.ai's [Terms of Service](https://www.anthropic.com/legal/consumer-terms).
- Only your own claude.ai cookies are stored in your local Keychain. No data is transmitted externally.
- "Claude" and related design elements are Anthropic's property. This is a fan-made utility app.

## 🙏 Inspiration / Credits

- Original **Claude Widget** by [ficklestudio26](https://ficklestudio26.blogspot.com/2026/05/mac.html) — referenced for the behavioral patterns of the Electron widget.
- UI inspiration: [Toss](https://toss.im/) / [Daangn](https://www.daangn.com/) — calm, friendly Korean fintech and community-app design languages.
- This project was built with extensive use of **[Claude](https://claude.ai)** and **[Claude Code](https://claude.com/claude-code)**. Analysis, design, SwiftUI code, debugging, icon SVG, localization, and even this README — every stage was assisted by Claude.

## 📄 License

MIT License — fork, modify, and use freely. You are responsible for complying with each service's terms.

---

<p align="center">
  Made with ☕ and Claude in Korea 🇰🇷
</p>
