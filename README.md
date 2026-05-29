<div align="right">
  <b>🇰🇷 한국어</b> · <a href="README.en.md">🇺🇸 English</a>
</div>

# Claude Usage

<p align="center">
  <img src="docs/screenshots/app-icon.png" width="120" alt="App Icon">
</p>

<p align="center">
  <b>Claude 사용량을 한눈에 — macOS 메뉴바 + 떠다니는 위젯</b>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13.0%2B-blue">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native-orange">
  <img alt="Universal" src="https://img.shields.io/badge/Universal-Intel%20%2B%20Apple%20Silicon-brightgreen">
  <img alt="Size" src="https://img.shields.io/badge/dmg-2.0MB-blueviolet">
</p>

<p align="center">
  <b>👉 <a href="#-설치-사용자">설치하기</a> · <a href="#-처음-실행할-때-읽어주세요">처음 실행 가이드</a> · <a href="#-안전한가요-keychain-안내">Keychain이 안전한가요?</a></b>
</p>

---

## ✨ Claude Usage란?

Claude.ai의 사용량(5시간 / 7일 / Claude Design)을 **메뉴바와 떠다니는 위젯**으로 실시간 확인하는 macOS 앱입니다.

- 🪶 **가벼움**: 2MB dmg, RAM 80MB, CPU 0.1% 이하 — 상시 띄워둬도 부담 없음
- 🎨 **3가지 테마**: 당근 / 토스 / 하이브리드 — 실시간 전환
- 🌏 **다국어**: 한국어 / English — 즉시 토글
- 🔄 **60초 자동 새로고침** + 수동 새로고침
- 🌑 **다크 모드** 자동 대응 (시스템 설정 따라감)
- 💻 **Universal Binary** (Intel + Apple Silicon)

## 📸 스크린샷

### 메뉴바 라벨

<p align="center">
  <img src="docs/screenshots/menubar.png" width="200" alt="Menu Bar">
</p>

> 메뉴바에 `[C] 38%` 처럼 사용량이 항상 표시됩니다. 70%↑면 ⚠️, 90%↑면 🛑로 모양 변화.

### 드롭다운 (3가지 테마)

<table>
  <tr>
    <td align="center"><b>🥕 당근</b></td>
    <td align="center"><b>💙 토스</b></td>
    <td align="center"><b>✨ 하이브리드</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/dropdown-daangn.png" width="300"></td>
    <td><img src="docs/screenshots/dropdown-toss.png" width="300"></td>
    <td><img src="docs/screenshots/dropdown-hybrid.png" width="300"></td>
  </tr>
</table>

### 떠다니는 위젯 (3가지 테마)

<table>
  <tr>
    <td align="center"><b>🥕 당근</b></td>
    <td align="center"><b>💙 토스</b></td>
    <td align="center"><b>✨ 하이브리드</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/widget-daangn.png" width="220"></td>
    <td><img src="docs/screenshots/widget-toss.png" width="220"></td>
    <td><img src="docs/screenshots/widget-hybrid.png" width="220"></td>
  </tr>
</table>

### 다국어 — 한국어 / English

<table>
  <tr>
    <td align="center"><b>🇰🇷 한국어</b></td>
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

### 설정 창

<table>
  <tr>
    <td align="center"><b>🇰🇷 한국어</b></td>
    <td align="center"><b>🇺🇸 English</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings.png" width="420"></td>
    <td><img src="docs/screenshots/settings-en.png" width="420"></td>
  </tr>
</table>

> 테마 / 위젯 항상 위에 표시 / 언어 — 모두 실시간 토글 가능. 변경 즉시 모든 화면에 반영됩니다.

## 🚀 설치 (사용자)

1. [Releases](https://github.com/jaewoo4200/ClaudeUsage/releases)에서 최신 `ClaudeUsage-x.x.x.dmg` 다운로드
2. dmg 열기 → `Applications` 폴더로 드래그
3. 처음 실행 전 ⬇️ [**처음 실행 가이드**](#-처음-실행할-때-읽어주세요)를 꼭 한 번 봐주세요!

## 🔑 처음 실행할 때 읽어주세요

이 앱은 **Apple Developer ID 코드 서명이 없습니다** (개인 오픈소스라 $99/년 비용을 들이지 않았어요). 그래서 macOS가 다음 두 가지 보안 다이얼로그를 띄울 수 있는데, **둘 다 정상이고 안전**합니다.

### 1) "확인되지 않은 개발자" 경고 우회

macOS 버전에 따라 다음 중 하나로:

#### macOS Sonoma (14) 이상 — 권장

1. `ClaudeUsage.app` 더블클릭 → **"손상되어 휴지통으로 이동" 경고 뜨면 "취소"**
2. **시스템 설정 → 개인정보 보호 및 보안** 열기
3. 아래로 스크롤 → **"ClaudeUsage이(가) 차단되었습니다"** 옆 **"그래도 열기"** 클릭
4. 다시 한번 확인 다이얼로그 → **"열기"** 클릭

#### macOS Ventura (13) — 우클릭

1. Applications 폴더에서 `ClaudeUsage.app` **우클릭(Control+클릭) → "열기"**
2. 경고 다이얼로그에서 **"열기"** 클릭 (1회만 — 이후부턴 더블클릭으로 OK)

#### 터미널 한 줄 (가장 빠름, 모든 버전 동작)

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeUsage.app
```

다운로드 파일에 자동으로 붙는 quarantine flag를 제거합니다. 이후 더블클릭만으로 실행됩니다.

### 2) 로그인 + 첫 사용량 조회

- 메뉴바 **[C] 로그인** 클릭 → claude.ai 로그인 (Google 가능)
- 로그인 완료 → 자동으로 사용량 표시 ✨

## 🔒 안전한가요? Keychain 안내

로그인 직후 macOS가 다음 다이얼로그를 띄울 수 있어요:

> **"ClaudeUsage wants to access key 'app.claudeusage' in your keychain."**
> *"To allow this, enter the 'login' keychain password."*

### 이게 뭔가요?

처음 로그인하면 ClaudeUsage가 **claude.ai 세션 쿠키를 macOS Keychain에 저장**합니다. 매번 다시 로그인하지 않게요. macOS는 **서명 안 된 앱이 Keychain에 처음 접근할 때** 사용자 확인을 받는 것이 표준 동작입니다.

### 왜 안전한가요?

- 🔓 **오픈소스**: [전체 코드를 GitHub에서 검증](https://github.com/jaewoo4200/ClaudeUsage/tree/main/Sources/ClaudeUsage)할 수 있어요. Keychain 코드는 [CookieStore.swift](https://github.com/jaewoo4200/ClaudeUsage/blob/main/Sources/ClaudeUsage/Services/CookieStore.swift) 28줄짜리예요.
- 🍪 **본인 쿠키만 본인 Mac에**: claude.ai 로그인 쿠키가 본인 Mac의 Keychain에만 저장됩니다 (iCloud 백업 안 됨 — `AfterFirstUnlockThisDeviceOnly` 적용).
- 🌐 **외부 전송 없음**: 쿠키는 오직 `claude.ai`로 API 호출할 때만 사용. analytics, telemetry, 외부 서버 전송 없음.
- 🔐 **claude.ai 비밀번호는 안 봐요**: 로그인은 claude.ai 공식 페이지에서 직접 — 우리는 비밀번호 입력 폼 자체를 표시하지 않아요.

### 어떻게 해야 하나요?

다이얼로그가 뜨면:

- ✅ **"Always Allow"** (권장) — Mac 로그인 비밀번호 입력 → 이후로는 안 뜸
- ⚠️ **"Allow"** — 한 번만 허용 → 다음 fetch 때 다시 물어봄
- ❌ **"Deny"** — 사용량 조회 안 됨

> 코드 서명을 한다면(Apple Developer ID, $99/년) 이 다이얼로그 자체가 안 떠요. 무료 오픈소스라 서명을 안 했고, 이게 macOS의 표준 절차입니다.

## 🔧 빌드 (개발자)

### 사전 요구사항

```bash
# Xcode 15+ 와 Command Line Tools
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# xcodegen (project.yml로부터 .xcodeproj 생성)
brew install xcodegen
```

### 빌드

```bash
git clone https://github.com/jaewoo4200/ClaudeUsage.git
cd ClaudeUsage

# Xcode 프로젝트 생성
xcodegen

# Xcode에서 열어서 빌드 또는 명령줄
open ClaudeUsage.xcodeproj
# 또는
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage build
```

### dmg 패키징 (Universal Binary)

```bash
./scripts/build-dmg.sh
# → build/ClaudeUsage-1.1.1.dmg (Intel + Apple Silicon 둘 다 지원)
```

### 아이콘 재생성

```bash
# icon.svg 수정 후
./scripts/build-icon.sh
# → Sources/ClaudeUsage/Resources/AppIcon.icns
```

## 🏗️ 프로젝트 구조

```
ClaudeUsage/
├── project.yml                  # xcodegen 정의 (project file 코드 관리)
├── scripts/
│   ├── icon.svg                 # 아이콘 소스
│   ├── build-icon.sh            # SVG → .icns
│   └── build-dmg.sh             # Release Universal + dmg
├── Sources/ClaudeUsage/
│   ├── ClaudeUsageApp.swift     # @main + AppDelegate
│   ├── Models/                  # UsageData, Plan, ExtraUsage
│   ├── Services/                # 인증, API, ViewModel, ThemeStore, AppSettings, LanguageStore, Localization
│   ├── Views/                   # 메뉴바, 위젯, 설정 + 디자인 시스템
│   └── Resources/               # Info.plist, entitlements, AppIcon.icns
└── docs/screenshots/            # README용 캡쳐
```

## 🛠️ 사용 기술

- **SwiftUI** + AppKit (네이티브 macOS 앱)
- **WKWebView** (claude.ai OAuth/Google 로그인 → 쿠키 캡처)
- **Keychain Services** (세션 쿠키 안전 저장)
- **URLSession async/await** (사용량 API 호출)
- **NSPanel** (.statusBar level 위젯 윈도우)
- **xcodegen** (프로젝트 파일 코드 관리)

## ⚠️ 알려진 한계

| 항목 | 내용 |
|---|---|
| 비공식 API | `claude.ai/api/organizations/.../usage` 는 비공개 endpoint. Anthropic이 변경하면 깨질 수 있음 |
| 세션 만료 | claude.ai 쿠키가 만료되면 재로그인 필요 (앱이 알림 표시) |
| 다중 계정 | 한 번에 하나의 claude.ai 계정만 지원 |
| 코드 서명 | Apple Developer 서명 없음 — 첫 실행 시 우클릭→열기 필요 |

## 🗺️ Roadmap (예정)

- [x] 🌑 **다크 모드** 자동 대응 — v1.1.0에서 추가
- [ ] 🤖 **GPT / OpenAI 사용량** 지원 (multi-provider 확장)
- [ ] 🔔 70% / 90% 도달 시 macOS 알림
- [ ] 📊 사용량 히스토리 그래프 (로컬 SQLite)
- [ ] 👥 다중 organization 계정 지원
- [ ] 🖥️ macOS Sonoma+ 데스크탑 위젯 (WidgetKit)

기여 환영합니다! 이슈/PR 부담 없이 올려주세요.

## 📜 Disclaimer

이 프로젝트는 **Anthropic과 무관한 개인 오픈소스 프로젝트**입니다.

- claude.ai의 **공식 문서화되지 않은 내부 API**를 호출합니다. API 변경 시 동작이 깨질 수 있습니다.
- 사용은 본인 책임이며, claude.ai의 [이용 약관](https://www.anthropic.com/legal/consumer-terms)을 준수해주세요.
- 본인의 claude.ai 계정 쿠키만 본인 Mac의 Keychain에 저장합니다. 외부로 데이터를 전송하지 않습니다.
- "Claude" 명칭과 관련 디자인 요소는 Anthropic의 자산입니다. 이 앱은 fan-made/utility 앱으로 만들어졌습니다.

## 🙏 영감 / 크레딧

- 원본 **Claude Widget** by [ficklestudio26](https://ficklestudio26.blogspot.com/2026/05/mac.html) — Electron 위젯의 동작 패턴을 참고했습니다.
- UI 디자인 영감: [토스(Toss)](https://toss.im/) / [당근(Daangn)](https://www.daangn.com/) — 차분하고 친근한 한국 fintech/커뮤니티 앱 디자인 언어.
- 본 작업은 **[Claude](https://claude.ai)** 와 **[Claude Code](https://claude.com/claude-code)** 를 적극 활용해 만들어졌습니다. 분석, 설계, SwiftUI 코드 작성, 디버깅, 아이콘 SVG 디자인, 다국어 처리, README 작성까지 — 모든 단계에서 Claude의 도움을 받았습니다.

## 📄 License

MIT License — 자유롭게 fork/수정/사용 가능. 다만 Anthropic의 ToS는 본인 책임으로 준수.

---

<p align="center">
  Made with ☕ and Claude in Korea 🇰🇷
</p>
