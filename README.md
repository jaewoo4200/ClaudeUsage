<div align="right">
  <b>🇰🇷 한국어</b> · <a href="README.en.md">🇺🇸 English</a>
</div>

# Claude + Codex Usage

<p align="center">
  <img src="docs/screenshots/app-icon.png" width="120" alt="App Icon">
</p>

<p align="center">
  <b>Claude와 Codex 사용량을 한눈에 — macOS 메뉴바 + 떠다니는 위젯</b>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13.0%2B-blue">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native-orange">
  <img alt="Universal" src="https://img.shields.io/badge/Universal-Intel%20%2B%20Apple%20Silicon-brightgreen">
  <img alt="Size" src="https://img.shields.io/badge/dmg-3.5MB-blueviolet">
</p>

<p align="center">
  <b>👉 <a href="https://jaewoo4200.github.io/ClaudeUsage/">공식 사이트</a> · <a href="https://github.com/jaewoo4200/ClaudeUsage/releases/download/v1.3.2/ClaudeUsage-1.3.2.dmg">v1.3.2 다운로드</a> · <a href="#-처음-실행할-때-읽어주세요">처음 실행 가이드</a></b>
</p>

---

## ✨ Claude Usage란?

Claude.ai와 ChatGPT/Codex의 사용량을 **메뉴바와 떠다니는 위젯**으로 실시간 확인하는 macOS 앱입니다. Claude의 5시간·7일·모델별 한도뿐 아니라 OpenAI의 5시간·주간 한도와 서버가 제공하는 모델별 한도를 함께 표시합니다.

- 🤖 **Claude + Codex**: 두 계정 상태를 독립적으로 조회하고 한 화면에 표시
- 🪟 **4가지 위젯 배치**: 세로 / 가로 / 화살표 전환 / Claude·Codex 독립 위젯 중 선택
- 🧭 **새 모델 자동 대응**: 서버가 내려주는 모델별 한도를 이름 고정 없이 표시하며 GPT-5.3-Codex-Spark는 기본 숨김·선택 표시
- 🧡 **큰 Mimo 펫**: 현재 한도와 최근 사용 속도에 따라 표정과 대사가 달라지며 가로 위젯에서는 더 크게 표시
- 📈 **선택형 로컬 기록**: 5분 간격 사용량과 토큰 추이를 이 Mac에만 14일 보관하며 기본값은 꺼짐
- 🪶 **네이티브 경량 앱**: SwiftUI 메뉴바 앱이며 로컬 기록은 사용자가 켠 경우에만 동작
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

> 메뉴바에 Claude 아이콘과 퍼센트, Codex 아이콘과 퍼센트가 함께 표시됩니다. 각 서비스는 독립적으로 갱신됩니다.

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

> 위젯 배치 / 분리할 서비스 / Spark 표시 / 테마 / Mimo / 로컬 기록 / 언어 — 모두 실시간 토글 가능. 변경 즉시 모든 화면에 반영됩니다.

## 🚀 설치 (사용자)

1. [ClaudeUsage-1.3.2.dmg](https://github.com/jaewoo4200/ClaudeUsage/releases/download/v1.3.2/ClaudeUsage-1.3.2.dmg) 다운로드 ([모든 릴리스](https://github.com/jaewoo4200/ClaudeUsage/releases))
2. dmg 열기 → `Applications` 폴더로 드래그
3. 처음 실행 전 ⬇️ [**처음 실행 가이드**](#-처음-실행할-때-읽어주세요)를 꼭 한 번 봐주세요!

> **Codex 사용량 표시 조건:** ChatGPT/Codex 앱 또는 호환되는 Codex 실행 파일이 설치되어 있고, 해당 Codex 세션에 로그인되어 있어야 합니다. **GUI 앱을 계속 켜 둘 필요는 없습니다.** ClaudeUsage가 조회할 때 로컬 `codex app-server` 프로세스를 직접 시작합니다.

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
- OpenAI 사용량은 Codex 또는 Codex가 통합된 ChatGPT 앱이 설치되어 있고 ChatGPT 계정으로 로그인되어 있으면 자동 연결. GUI 앱은 꺼져 있어도 됩니다.
- 로그인 완료 → 각 서비스의 사용량을 독립적으로 표시 ✨

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

### OpenAI 로그인은 어떻게 처리하나요?

- 설치된 ChatGPT/Codex 앱 또는 호환 Codex 실행 파일의 `codex app-server` 로컬 인터페이스를 사용합니다. ClaudeUsage가 조회 시 해당 프로세스를 직접 시작하므로 ChatGPT/Codex GUI를 계속 실행할 필요가 없고, OpenAI 토큰 파일을 직접 읽거나 별도로 저장하지도 않습니다.
- `account/rateLimits/read`와 `account/usage/read`만 호출하므로 추가 로그인 창이나 토큰 복사는 필요하지 않습니다.
- Codex/ChatGPT 앱을 찾을 수 없거나 세션이 만료되면 Claude 사용량은 그대로 유지되고, OpenAI 영역에만 연결 안내가 표시됩니다.

### 사용량 데이터는 정확히 어디서 오나요?

`로컬 인터페이스`는 로컬 대화 기록을 읽는다는 뜻이 아닙니다. Mac에서 실행되는 Codex 프로세스에 요청하고, 그 프로세스가 로그인된 ChatGPT 계정의 서버 기반 사용량 스냅샷을 돌려주는 방식입니다.

| 표시값 | 데이터 출처 | 대화 기록 직접 읽기 |
|---|---|---|
| Claude 5시간·주간·모델 한도 | Keychain의 본인 세션으로 claude.ai 사용량 조회 | 아니요 |
| Claude Code 오늘 토큰·추이 | 이 Mac의 `~/.claude/projects/**/*.jsonl`에서 시각과 숫자형 usage 필드만 합산 | 예, Claude Code 로컬 기록만 |
| Codex 5시간·주간·모델 한도 | ChatGPT/Codex에 포함된 `codex app-server`의 `account/rateLimits/read` | 아니요 |
| Codex 일별 토큰·추이 | `codex app-server`의 `account/usage/read`가 제공하는 계정 단위 일별 버킷 | 아니요 |
| Mimo 14일 기록 | ClaudeUsage가 사용자가 켠 경우에만 만드는 `usage-history.json` | ClaudeUsage 자체 기록 |

일반 ChatGPT 대화나 ChatGPT Classic 기록, Codex 세션 본문을 스캔하지 않습니다. 현재 ChatGPT 앱의 Codex 통합, 독립 Codex 앱 또는 호환되는 Codex 실행 파일과 로그인된 세션을 사용합니다.

### Mimo 기록은 무엇을 저장하나요?

- 기록은 **기본적으로 꺼져 있으며**, 설정에서 직접 켠 경우에만 시작합니다.
- 퍼센트, 일별 토큰 합계, 시각만 `~/Library/Application Support/ClaudeUsage/usage-history.json`에 최대 14일 저장합니다.
- 프롬프트, 응답, 파일명, 프로젝트명, 쿠키, 토큰은 기록하지 않으며 설정에서 즉시 전체 삭제할 수 있습니다.
- 앱 번들만 삭제하거나 재설치해도 이 기록 파일은 자동으로 삭제되지 않습니다. 설정의 **사용량 기록 지우기**는 ClaudeUsage의 14일 추이 기록만 지우며, 오늘 토큰 합계는 Claude Code 로컬 로그와 Codex 계정 일별 버킷에서 다시 계산되어 곧바로 다시 표시될 수 있습니다.
- 자세한 데이터 출처와 약관 검토는 [사용량 기록·개인정보·서비스 정책](docs/USAGE_HISTORY_AND_POLICY.md)을 확인하세요.

### 어떻게 해야 하나요?

다이얼로그가 뜨면:

- ✅ **"Always Allow"** (권장) — Mac 로그인 비밀번호 입력 → 이후로는 안 뜸
- ⚠️ **"Allow"** — 한 번만 허용 → 다음 fetch 때 다시 물어봄
- ❌ **"Deny"** — 사용량 조회 안 됨

> 코드 서명을 한다면(Apple Developer ID, $99/년) 이 다이얼로그 자체가 안 떠요. 무료 오픈소스라 서명을 안 했고, 이게 macOS의 표준 절차입니다.

## Windows 포트

Windows 구현은 아직 시작 전입니다. Windows 11에서 이어서 작업할 때는 기술 선택, 단계별 계획, 테스트 기준, 첫 작업 프롬프트를 정리한 [Windows 포트 HANDOFF](HANDOFF.md)를 먼저 확인하세요.

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
# → build/ClaudeUsage-1.3.2.dmg (Intel + Apple Silicon 둘 다 지원)
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
│   ├── Models/                  # Claude/OpenAI 사용량 응답과 표시 모델
│   ├── Services/                # 인증, API, ViewModel, ThemeStore, AppSettings, LanguageStore, Localization
│   ├── Views/                   # 메뉴바, 위젯, 설정 + 디자인 시스템
│   └── Resources/               # Info.plist, entitlements, AppIcon.icns
└── docs/screenshots/            # README용 캡쳐
```

## 🛠️ 사용 기술

- **SwiftUI** + AppKit (네이티브 macOS 앱)
- **WKWebView** (claude.ai OAuth/Google 로그인 → 쿠키 캡처)
- **Keychain Services** (세션 쿠키 안전 저장)
- **Codex app-server JSON-RPC** (문서화된 로컬 사용량 인터페이스)
- **Claude Code 로컬 JSONL 집계** (선택형 토큰 추이, 내용 미저장)
- **URLSession async/await** (사용량 API 호출)
- **NSPanel** (.statusBar level 위젯 윈도우)
- **xcodegen** (프로젝트 파일 코드 관리)

## ⚠️ 알려진 한계

| 항목 | 내용 |
|---|---|
| 비공식 API | `claude.ai/api/organizations/.../usage` 는 비공개 endpoint. Anthropic이 변경하면 깨질 수 있음 |
| 세션 만료 | claude.ai 쿠키가 만료되면 재로그인 필요 (앱이 알림 표시) |
| OpenAI 연결 | `codex app-server`가 포함된 Codex/ChatGPT 또는 호환 실행 파일과 로그인된 로컬 세션이 필요. GUI 앱은 꺼져 있어도 됨 |
| 토큰 추이 | OpenAI 일별 bucket은 현재 작업보다 늦게 반영될 수 있음. Claude는 이 Mac의 오늘 Claude Code 로그만 집계하며 둘 다 한도 퍼센트와 1:1 대응하지 않음 |
| 다중 계정 | 서비스별로 한 번에 하나의 계정만 지원 |
| 코드 서명 | Apple Developer 서명 없음 — 첫 실행 시 우클릭→열기 필요 |

## 🗺️ Roadmap (예정)

- [x] 🌑 **다크 모드** 자동 대응 — v1.1.0에서 추가
- [x] 🤖 **Codex / OpenAI 사용량** 지원 — v1.2.0에서 추가
- [x] 🧡 **Mimo 펫 + 14일 로컬 추이 + 4가지 위젯 배치** — v1.3.0에서 추가
- [ ] 🔔 70% / 90% 도달 시 macOS 알림
- [ ] 📊 장기 사용량 분석 화면
- [ ] 👥 다중 organization 계정 지원
- [ ] 🖥️ macOS Sonoma+ 데스크탑 위젯 (WidgetKit)

기여 환영합니다! 이슈/PR 부담 없이 올려주세요.

## 📜 Disclaimer

이 프로젝트는 **Anthropic 및 OpenAI와 무관한 개인 오픈소스 프로젝트**입니다.

- claude.ai의 **공식 문서화되지 않은 내부 API**를 호출합니다. API 변경 시 동작이 깨질 수 있습니다.
- OpenAI 사용량은 Codex의 문서화된 `app-server` 인터페이스만 사용하며, 비공개 `wham/usage` 직접 호출은 제거했습니다.
- Anthropic 소비자 약관은 API 키 또는 명시적 허용이 없는 자동 접근을 제한합니다. 공개 배포 전 [정책 검토 문서](docs/USAGE_HISTORY_AND_POLICY.md)를 확인하세요.
- 사용은 본인 책임이며 Anthropic의 [이용 약관](https://www.anthropic.com/legal/consumer-terms)과 OpenAI의 [이용 약관](https://openai.com/policies/row-terms-of-use/)을 준수해야 합니다.
- 본인의 claude.ai 계정 쿠키만 본인 Mac의 Keychain에 저장합니다. 외부로 데이터를 전송하지 않습니다.
- "Claude" 명칭과 관련 디자인 요소는 Anthropic의 자산입니다. 이 앱은 fan-made/utility 앱으로 만들어졌습니다.

## 🙏 영감 / 크레딧

- 원본 **Claude Widget** by [ficklestudio26](https://ficklestudio26.blogspot.com/2026/05/mac.html) — Electron 위젯의 동작 패턴을 참고했습니다.
- UI 디자인 영감: [토스(Toss)](https://toss.im/) / [당근(Daangn)](https://www.daangn.com/) — 차분하고 친근한 한국 fintech/커뮤니티 앱 디자인 언어.
- 본 작업은 **[Claude](https://claude.ai)** 와 **[Claude Code](https://claude.com/claude-code)** 를 적극 활용해 만들어졌습니다. 분석, 설계, SwiftUI 코드 작성, 디버깅, 아이콘 SVG 디자인, 다국어 처리, README 작성까지 — 모든 단계에서 Claude의 도움을 받았습니다.

## 📄 License

MIT License — 자유롭게 fork/수정/사용 가능. 다만 각 서비스의 이용 약관은 본인 책임으로 준수.

---

<p align="center">
  Made with ☕ and Claude in Korea 🇰🇷
</p>
