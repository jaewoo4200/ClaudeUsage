# ClaudeUsage for Windows — developer alpha

<div align="right">
  <b>한국어</b> · <a href="#english">English</a>
</div>

Windows 11 x64에서 Claude와 Codex 사용량을 알림 영역 플라이아웃과 떠다니는 WPF 위젯으로 확인하는 포트입니다. 안정 배포 중인 macOS 앱과 별개의 **미서명 개발자 알파**입니다.

## 현재 범위

- Claude와 Codex를 독립적으로 60초마다 갱신하고 한쪽 오류 시 다른 쪽과 마지막 정상 값을 유지
- 5시간·주간·서버 제공 모델별 한도, 리셋 시간, Codex 리셋 크레딧, 오늘 토큰 표시
- 세로·가로·화살표 전환·Claude/Codex 분리 위젯과 모니터별 위치 저장
- 항상 위, Windows 시작 시 실행, 다크/라이트/시스템 모드, 당근/토스/하이브리드 테마
- 한국어/영어와 Mimo, Lumi, Kumo, Dot, Navi, Bori, Muru, Tori, Pico 9종 펫
- 명시적으로 켠 경우에만 5분 간격, 최대 14일/4,200개의 로컬 사용량 기록

## 설치 — Windows 11 x64

### 요구사항

- Windows 11 x64. `win-arm64`는 실제 장치 검증 전까지 배포하지 않습니다.
- Claude 로그인: [Microsoft Edge WebView2 Evergreen Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)이 필요합니다. Windows 11에는 보통 포함되어 있지만 앱이 찾지 못하면 별도로 설치해야 합니다.
- Codex 사용량: `codex app-server`를 지원하는 공식 Codex 앱/CLI가 설치되고 로그인되어 있어야 합니다.
- 새로고침 중 Claude와 OpenAI 공급자 endpoint에 연결할 네트워크.

### ZIP 실행

Windows prerelease 자산이 게시된 경우 [GitHub Releases](https://github.com/jaewoo4200/ClaudeUsage/releases)에서 다음 두 파일을 함께 받습니다.

```text
ClaudeUsage-Windows-<version>-win-x64.zip
ClaudeUsage-Windows-<version>-win-x64.zip.sha256
```

PowerShell에서 체크섬을 확인합니다.

```powershell
Get-FileHash .\ClaudeUsage-Windows-*-win-x64.zip -Algorithm SHA256
Get-Content .\ClaudeUsage-Windows-*-win-x64.zip.sha256
```

두 해시가 같으면 ZIP **전체를 폴더에 압축 해제**하고 `ClaudeUsage.Windows.exe`를 실행합니다. 실행에 별도 .NET 설치는 필요하지 않습니다. 압축 파일 내부에서 exe만 직접 실행하거나 exe 하나만 복사하면 안 됩니다.

현재 ZIP과 실행 파일은 코드 서명되지 않았으므로 SmartScreen이 첫 실행을 경고할 수 있습니다. 신뢰할 수 있는 태그·체크섬·소스와 일치하는 빌드인지 확인한 뒤에만 실행하세요. 서명된 설치 프로그램/MSIX는 아직 제공하지 않습니다.

### 첫 연결

Codex가 로그인되지 않았다면 터미널에서 다음을 실행합니다.

```powershell
codex login
```

Codex GUI는 계속 켜 둘 필요가 없습니다. ClaudeUsage가 새로고칠 때 설치된 실행 파일의 로컬 `codex app-server`를 시작합니다. Claude는 플라이아웃의 **Claude 로그인**에서 WebView2로 `claude.ai`에 직접 로그인합니다. 두 공급자는 독립적이므로 Claude 로그인을 건너뛰고 Codex만 사용할 수도 있습니다.

## 데이터 출처와 개인정보

| 기능 | 출처/동작 | 저장 또는 접근 경로 |
|---|---|---|
| Codex 한도·오늘 토큰 | 설치된 Codex의 `account/rateLimits/read`, `account/usage/read` | Codex 인증 소유권을 유지하며 `%USERPROFILE%\.codex\auth.json`을 직접 읽거나 토큰을 저장하지 않음 |
| Claude 한도 | 격리된 WebView2에서 본인이 로그인한 세션으로 `claude.ai` 사용량 조회 | Claude 세션 쿠키 헤더를 `%LOCALAPPDATA%\ClaudeUsage\claude-session.dat`에 Windows DPAPI `CurrentUser`로 암호화 |
| 일반 설정 | 위젯, 테마, 언어, 실행 경로 등 | `%LOCALAPPDATA%\ClaudeUsage\settings.json`; 인증 쿠키 없음 |
| 선택형 사용량 기록 | 5분 간격의 퍼센트·모델 식별자/이름·오늘 토큰·시각 | `%LOCALAPPDATA%\ClaudeUsage\usage-history.json`; 최대 14일 또는 4,200개 샘플 |
| 선택형 Claude Code 집계 | 오늘 수정된 `%USERPROFILE%\.claude\projects\**\*.jsonl`에서 시각과 숫자형 usage 필드만 합산 | 읽기 전용 집계이며 JSONL 내용, 프롬프트, 응답, 파일명, 프로젝트명을 기록 파일에 복사하지 않음 |
| Windows 자동 시작 | ZIP은 현재 사용자 Run 키, MSIX는 패키지 ID 기반 Startup Task | ZIP: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`; MSIX: Windows 시작 앱 |

사용량 기록과 Claude Code JSONL 스캔은 **기본적으로 꺼져 있으며 동일한 사용자의 선택으로만 켜집니다**. 로컬 추이 파일은 일반 JSON이고, JSONL은 Claude Code가 이미 만든 로컬 로그의 입력 소스입니다. 둘은 같은 파일이 아닙니다.

현재 Windows 개발자 알파는 이 기록으로 최근 추이와 펫 상태를 계산하며, macOS 앱과 같은 별도 사용량 기록 창에서 1시간·24시간·7일·14일 범위와 공급자 필터를 제공합니다.

Claude 로그인은 매번 `%TEMP%\ClaudeUsage\WebView2\login-*` 아래에 독립 프로필을 만들며 비밀번호 자동 저장과 자동 완성을 끕니다. 세션 쿠키를 DPAPI 파일로 옮긴 뒤 로그인 프로필과 브라우징 데이터를 삭제하려고 시도합니다. 로그아웃하면 저장된 `claude-session.dat`을 지웁니다. DPAPI 파일은 같은 Windows 사용자 컨텍스트에서만 복호화할 수 있습니다.

앱 자체 분석/광고 SDK는 없으며 사용량 샘플을 별도 ClaudeUsage 서버로 업로드하지 않습니다. 공급자 조회에는 당연히 해당 공급자의 서버와 통신합니다.

### 비공식 Claude endpoint 주의

Claude 클라우드 한도는 Anthropic이 공개 문서화하지 않은 `claude.ai/api/organizations`와 `claude.ai/api/organizations/.../usage`에 의존합니다. Anthropic이 이를 변경·차단하거나 정책을 바꾸면 Claude 조회가 예고 없이 중단될 수 있습니다. Codex 공급자는 이 경로와 분리되어 있으므로 Claude 오류가 Codex 인증이나 마지막 정상 스냅샷을 지우지 않습니다. 배포·사용 전 [사용량 기록 및 정책 문서](../docs/USAGE_HISTORY_AND_POLICY.md)와 각 공급자의 최신 약관을 확인하세요.

## 소스에서 빌드

개발에는 Windows 11 x64, PowerShell 7(`pwsh`), 저장소의 `global.json`에 고정된 .NET 10 SDK가 필요합니다. 저장소 루트에서 실행합니다.

```powershell
dotnet restore windows/ClaudeUsage.Windows.sln --runtime win-x64 --configfile windows/NuGet.Config
dotnet test windows/ClaudeUsage.Windows.sln -c Release --no-restore
dotnet run --project windows/src/ClaudeUsage.Windows/ClaudeUsage.Windows.csproj
```

Codex 연결만 점검하려면 원문 RPC 응답이나 토큰을 출력하지 않는 진단 도구를 사용할 수 있습니다.

```powershell
dotnet run --project windows/tools/ClaudeUsage.Probe/ClaudeUsage.Probe.csproj
```

## ZIP·SBOM·MSIX 만들기

전체 restore·test·publish·zip·checksum 과정을 실행합니다.

```powershell
pwsh -File windows/scripts/package.ps1 -Runtime win-x64
```

이미 restore와 test를 통과했다면 다음처럼 중복 실행을 건너뛸 수 있습니다.

```powershell
pwsh -File windows/scripts/package.ps1 -Runtime win-x64 -SkipRestore -SkipTests
```

기본 결과는 `windows/artifacts/` 아래의 self-contained ZIP, SPDX 2.3 SBOM, 제3자 라이선스 고지, 산출물별 `.sha256`, `SHA256SUMS.txt`입니다. Windows SDK가 있으면 `-IncludeMsix -RequireMsix`로 MSIX를 만들 수 있고, 안정적인 App Installer URL과 버전별 MSIX URL을 함께 주면 2021 스키마의 `.appinstaller`도 생성합니다. 실제 배포 ID·코드 서명·업데이트 호스팅 방법은 [패키징 및 서명 정책](packaging/README.md)을 따릅니다.

### ZIP 창 이동 스모크

잠금 해제된 대화형 Windows 데스크톱의 **일반 사용자(관리자 아님)** PowerShell에서 먼저 정적 안전 검사를 실행한 뒤, 배포할 정확한 ZIP을 검사합니다. 실행 중 Settings, History, Widget 창과 마우스 포인터가 잠시 움직입니다. 스크립트는 테스트 전 포인터와 전경 창을 복원하고, 실제 사용자 설정의 해시·수정 시각이 바뀌지 않았는지와 테스트 프로세스·임시 디렉터리가 남지 않았는지를 확인합니다. 패키지를 설치하거나 인증서·레지스트리를 변경하지 않습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test-portable-movement-smoke-static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test-portable-movement-smoke.ps1 `
  -ZipPath windows/artifacts/ClaudeUsage-Windows-<version>-win-x64.zip
```

개발 중 압축을 푼 빌드는 두 번째 명령에서 `-ZipPath` 대신 `-ExecutablePath .\portable\ClaudeUsage.Windows.exe`로 검사할 수 있습니다. 릴리스 승인은 반드시 최종 ZIP 형식을 사용합니다.

GitHub Actions의 `Windows` workflow는 고정 .NET SDK와 해시로 고정한 Microsoft SDK BuildTools를 사용해 테스트, 구조 검증용 미서명 MSIX/App Installer, SBOM·라이선스·체크섬, 결정적 ZIP 재빌드를 검사합니다. 공개 배포는 태그 push로 자동 게시되지 않습니다. 별도의 `Windows signed release candidate` workflow가 기존 `windows-v<semver>` 태그, 보호된 영구 패키지 ID, PFX 해시·비밀번호, 인증서 subject 일치, RFC 3161 타임스탬프, SignTool 검증을 모두 요구하며 공개 게시는 기본값이 꺼진 명시적 승인입니다.

## 알파 제한

- 실사용 Windows 11 x64 장치와 계정에서 추가 검증이 필요한 개발자 알파입니다.
- MSIX/App Installer 파이프라인은 준비됐지만 영구 배포 ID·신뢰할 수 있는 인증서·HTTPS 업데이트 위치·[클린 머신 검증](packaging/CLEAN_MACHINE_SMOKE.md)이 끝나기 전에는 공개 설치 프로그램으로 간주하지 않습니다. `win-arm64` 패키지도 아직 없습니다.
- 공급자별 한도와 일별 토큰 버킷은 서버 반영 시점에 따라 현재 작업과 차이가 날 수 있습니다.
- Claude 세션 만료 시 다시 로그인해야 하며, 비공식 endpoint 변경은 앱 업데이트가 필요할 수 있습니다.
- 서비스별 한 번에 한 계정만 지원합니다.

---

<a id="english"></a>

## English

ClaudeUsage for Windows is an **unsigned developer alpha** for Windows 11 x64, separate from the stable macOS release. It is a .NET 10 WPF notification-area app with a combined flyout, floating widgets, four layouts, three themes, Korean/English UI, nine companions, and opt-in local trends.

### Install — Windows 11 x64

- The release target is Windows 11 x64 only. There is no `win-arm64` release. The repository can build an MSIX/App Installer channel, but no public installer is release-ready until the permanent identity and trusted signing certificate pass the clean-machine gate.
- The self-contained ZIP includes the .NET runtime. Claude sign-in still requires the [Microsoft Edge WebView2 Evergreen Runtime](https://developer.microsoft.com/microsoft-edge/webview2/), normally present on Windows 11.
- Codex usage requires an installed and signed-in official Codex app/CLI with `codex app-server`; run `codex login` if needed.

When a Windows prerelease asset exists, download both `ClaudeUsage-Windows-<version>-win-x64.zip` and `.zip.sha256` from [GitHub Releases](https://github.com/jaewoo4200/ClaudeUsage/releases). Compare the two values below, extract the **entire** ZIP, and then run `ClaudeUsage.Windows.exe`.

```powershell
Get-FileHash .\ClaudeUsage-Windows-*-win-x64.zip -Algorithm SHA256
Get-Content .\ClaudeUsage-Windows-*-win-x64.zip.sha256
```

Do not launch the executable from inside the archive. SmartScreen may warn because the alpha is unsigned; only proceed after verifying the source, tag, and checksum. Sign in to Claude through the app's isolated WebView2 window. Claude and Codex are independent, so Codex-only use does not require a Claude session.

### Data sources and privacy

| Feature | Source/behavior | Local storage or access |
|---|---|---|
| Codex limits and tokens | Installed Codex `account/rateLimits/read` and `account/usage/read` | Does not read `%USERPROFILE%\.codex\auth.json` or copy its token |
| Claude limits | Your authenticated `claude.ai` session in an isolated WebView2 profile | Claude session cookie header encrypted for the current user with DPAPI at `%LOCALAPPDATA%\ClaudeUsage\claude-session.dat` |
| Settings | Widget, theme, language, executable path | `%LOCALAPPDATA%\ClaudeUsage\settings.json`; no auth cookie |
| Optional history | Percentages, model IDs/names, today's tokens, timestamps every five minutes | `%LOCALAPPDATA%\ClaudeUsage\usage-history.json`; up to 14 days or 4,200 samples |
| Optional Claude Code aggregation | Timestamp and numeric usage fields from today's `%USERPROFILE%\.claude\projects\**\*.jsonl` | Read-only aggregation; prompts, responses, filenames, and project names are not copied into history |
| Optional auto-start | ZIP: current-user Run key; MSIX: identity-based Startup Task | ZIP: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`; MSIX: Windows Startup Apps |

History and Claude Code JSONL scanning are **off by default and share the same explicit opt-in**. The app's history is a regular JSON file; JSONL refers only to the pre-existing Claude Code logs used as an input source.

The current Windows developer alpha uses these samples for recent trends and companion state, and includes the macOS-style standalone usage-history dashboard with 1-hour, 24-hour, 7-day, and 14-day ranges plus provider filters.

Each Claude sign-in creates a temporary profile under `%TEMP%\ClaudeUsage\WebView2\login-*`, disables password saving/autofill, and attempts to delete the profile and browsing data when the window closes. The captured session cookie is stored only in the DPAPI `CurrentUser` file, not in `settings.json`. Logging out removes that file. No ClaudeUsage analytics or advertising SDK uploads usage samples to a separate project server.

Claude quota retrieval depends on Anthropic's undocumented `claude.ai/api/organizations/.../usage` endpoint. It may change or be restricted without notice. Codex-only operation is isolated from that path. Review [usage-history and policy notes](../docs/USAGE_HISTORY_AND_POLICY.md) and the providers' current terms before distribution or use.

### Build, test, and package

Install PowerShell 7 (`pwsh`) and the .NET 10 SDK pinned by the repository's `global.json`, then run from the repository root:

```powershell
dotnet restore windows/ClaudeUsage.Windows.sln --runtime win-x64 --configfile windows/NuGet.Config
dotnet test windows/ClaudeUsage.Windows.sln -c Release --no-restore
dotnet run --project windows/src/ClaudeUsage.Windows/ClaudeUsage.Windows.csproj
pwsh -File windows/scripts/package.ps1 -Runtime win-x64 -SkipRestore -SkipTests
```

The packaging script always writes a self-contained ZIP, SPDX 2.3 SBOM, generated third-party notices, per-artifact `.sha256` files, and `SHA256SUMS.txt` to `windows/artifacts/`. With the Windows SDK installed, `-IncludeMsix -RequireMsix` also creates an MSIX; supplying both HTTPS update URIs creates a 2021-schema `.appinstaller`. Update builds accept `-PreviousPublicPackageVersion <four-part-version>` and reject equality or downgrades; omission is reported as an explicit skip. URI path basenames must exactly match the generated App Installer and MSIX asset names. Signed validation checks every deployed ZIP `.exe`/`.dll` plus the MSIX with SignTool. See [the packaging/signing policy](packaging/README.md). The optional redaction-safe Codex probe is:

```powershell
dotnet run --project windows/tools/ClaudeUsage.Probe/ClaudeUsage.Probe.csproj
```

Run the portable movement smoke from an unlocked, interactive Windows desktop in a **standard-user (non-administrator)** PowerShell session. It briefly moves the pointer and the Settings, History, and Widget windows through real pointer drags, then restores the original pointer/foreground window and verifies unchanged user settings plus zero test-process/temp-directory residue. It does not install a package or mutate certificates or the registry.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test-portable-movement-smoke-static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/scripts/test-portable-movement-smoke.ps1 `
  -ZipPath windows/artifacts/ClaudeUsage-Windows-<version>-win-x64.zip
```

For an unpacked development build, replace `-ZipPath ...` with `-ExecutablePath .\portable\ClaudeUsage.Windows.exe`. Release approval requires the exact final ZIP form.

The regular `Windows` GitHub Actions workflow tests and produces unsigned structural verification artifacts on `windows-latest`; it also checks deterministic ZIP reproduction. Public releases are **not** published automatically on tag push. The protected release-candidate workflow requires an existing `windows-v<semver>` tag, permanent package identity, trusted certificate secrets, exact publisher matching, RFC 3161 timestamping, SignTool verification, the checked-in [public MSIX version ledger](packaging/public-msix-version-ledger.json), and explicit publication approval. Signed artifacts and their GitHub release use dedicated signed-release notes; Windows releases never become GitHub's automatic "Latest" release, and prerelease SemVer tags are classified as prereleases. Follow the [clean-machine smoke checklist](packaging/CLEAN_MACHINE_SMOKE.md) before publication.

Known alpha limits include the still-unfulfilled production certificate/identity and clean-machine gates, no ARM64 package, one account per provider, possible server-bucket lag, and the risk of Claude's undocumented endpoint changing.
