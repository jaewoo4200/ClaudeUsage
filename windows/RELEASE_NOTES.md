# ClaudeUsage for Windows — unsigned alpha

## 한국어

Windows 11 x64용 **미서명 self-contained 개발자 알파**입니다. ZIP 전체를 폴더에 압축 해제한 뒤 `ClaudeUsage.Windows.exe`를 실행하세요. 압축 파일 안에서 exe를 직접 실행하거나 exe 하나만 복사하면 안 됩니다.

### 포함 기능

- Claude와 Codex의 5시간·주간·동적 모델별 한도, 리셋 시간, Codex 리셋 크레딧, 오늘 토큰
- 알림 영역 플라이아웃과 세로·가로·전환·분리 떠다니는 위젯
- 당근/토스/하이브리드 테마, 시스템/라이트/다크 모드, 한국어/영어
- 9종 펫과 사용자가 켠 경우에만 저장되는 5분 간격·최대 14일/4,200개 로컬 기록
- Claude Code 로컬 JSONL의 시각·숫자형 usage 필드만 선택형 집계

### 요구사항과 연결

- Windows 11 x64. `win-arm64` 패키지는 아직 없습니다.
- Codex: `codex app-server`를 지원하는 공식 앱/CLI 설치와 로그인. 필요하면 `codex login`을 실행합니다.
- Claude: Microsoft Edge WebView2 Evergreen Runtime과 앱 안의 대화형 `claude.ai` 로그인.
- 공급자 사용량을 새로고칠 네트워크 연결.

### 개인정보와 보안

- Codex 인증은 설치된 Codex가 소유합니다. ClaudeUsage는 `%USERPROFILE%\.codex\auth.json`을 읽거나 토큰을 저장하지 않습니다.
- Claude 로그인은 세션별 격리 WebView2 프로필을 사용합니다. Claude 세션 쿠키 헤더는 현재 Windows 사용자만 복호화할 수 있도록 DPAPI로 암호화해 `%LOCALAPPDATA%\ClaudeUsage\claude-session.dat`에 저장합니다.
- 설정은 `%LOCALAPPDATA%\ClaudeUsage\settings.json`, 선택형 기록은 `%LOCALAPPDATA%\ClaudeUsage\usage-history.json`에 저장됩니다. 인증 쿠키는 설정/기록 파일에 넣지 않습니다.
- 기록과 `%USERPROFILE%\.claude\projects\**\*.jsonl` 스캔은 기본적으로 꺼져 있습니다. 프롬프트, 응답, 파일명, 프로젝트명은 기록하지 않습니다.
- 공급자 오류는 분리됩니다. Claude 로그인/endpoint 오류가 마지막 정상 Codex 스냅샷을 지우지 않으며 그 반대도 같습니다.

### 알파 제한

- Claude 한도는 Anthropic이 문서화하지 않은 `claude.ai/api/organizations/.../usage`에 의존하므로 예고 없이 변경·차단될 수 있습니다.
- 이 ZIP은 코드 서명되지 않아 SmartScreen이 경고할 수 있습니다. 서명된 설치 프로그램/MSIX는 신뢰할 수 있는 인증서와 배포 ID가 마련되기 전까지 제공하지 않습니다.
- `win-arm64`와 공급자별 다중 계정은 지원하지 않습니다. App Installer 자동 업데이트는 서명되고 HTTPS로 호스팅된 프로덕션 채널에서만 사용할 수 있습니다.
- Windows 자동 시작은 포터블 ZIP에서 현재 사용자 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`을 사용하고, MSIX에서는 업데이트 후에도 유지되는 패키지 ID 기반 Startup Task를 사용합니다. ZIP 폴더 삭제나 MSIX 제거만으로 로컬 설정·기록이나 공급자 데이터가 삭제되지는 않습니다.

### 다운로드 검증

```powershell
Get-FileHash .\ClaudeUsage-Windows-*-win-x64.zip -Algorithm SHA256
Get-Content .\ClaudeUsage-Windows-*-win-x64.zip.sha256
```

압축 해제 전에 두 16진수 값이 일치하는지 확인하세요.

---

## English

This is an **unsigned, self-contained developer alpha for Windows 11 x64**. Extract the entire ZIP before running `ClaudeUsage.Windows.exe`; do not launch it from inside the archive or copy only the executable.

### Included

- Claude and Codex five-hour, weekly, and dynamic model limits; reset times; Codex reset credits; and today's tokens.
- Notification-area flyout plus stacked, horizontal, paged, and separate floating widgets.
- Daangn, Toss, and Hybrid themes; system/light/dark appearance; Korean and English.
- Nine companions and opt-in local history sampled every five minutes, bounded to 14 days/4,200 entries.
- Opt-in aggregation of timestamp and numeric usage fields from local Claude Code JSONL files.

### Requirements and sign-in

- Windows 11 x64. No `win-arm64` package is published yet.
- Codex: an installed and signed-in official app/CLI with `codex app-server`; run `codex login` if needed.
- Claude: Microsoft Edge WebView2 Evergreen Runtime and interactive `claude.ai` sign-in inside the app.
- Network access to provider endpoints while refreshing.

### Privacy and security

- Codex owns its authentication. ClaudeUsage does not read `%USERPROFILE%\.codex\auth.json` or store its token.
- Claude sign-in uses a per-session isolated WebView2 profile. The Claude session cookie header is encrypted with Windows DPAPI for the current user at `%LOCALAPPDATA%\ClaudeUsage\claude-session.dat`.
- Settings live at `%LOCALAPPDATA%\ClaudeUsage\settings.json`; opt-in history lives at `%LOCALAPPDATA%\ClaudeUsage\usage-history.json`. Auth cookies are not written into either file.
- History and scanning `%USERPROFILE%\.claude\projects\**\*.jsonl` are off by default. Prompts, responses, filenames, and project names are not retained.
- Provider failures are isolated: a Claude sign-in/endpoint failure does not erase the last good Codex snapshot, and vice versa.

### Alpha limitations

- Claude quota retrieval uses Anthropic's undocumented `claude.ai/api/organizations/.../usage` endpoint. Anthropic may change or restrict it without notice.
- The portable ZIP may be unsigned in development CI, so SmartScreen can warn. The repository now has gated MSIX/App Installer, SPDX SBOM, SHA-256, license-notice, and clean-machine smoke tooling, but no public installer is claimed until the permanent identity and trusted signing certificate pass that gate.
- There is no `win-arm64` package or multiple-account support per provider. App Installer auto-update is available only for a signed, HTTPS-hosted production channel.
- Optional auto-start uses the current-user `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` key for the portable ZIP and an update-safe, identity-based Startup Task for MSIX. Removing the ZIP folder or uninstalling MSIX does not delete local settings/history or provider-owned data.

### Verify the download

```powershell
Get-FileHash .\ClaudeUsage-Windows-*-win-x64.zip -Algorithm SHA256
Get-Content .\ClaudeUsage-Windows-*-win-x64.zip.sha256
```

The hexadecimal values must match before extraction.
