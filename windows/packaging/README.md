# Windows distribution and signing policy

ClaudeUsage has two Windows artifacts built from the same self-contained
`win-x64` publish directory:

- A deterministic portable ZIP for diagnosis and fallback distribution.
- An MSIX for per-user install, update, repair, and uninstall. A 2021-schema
  `.appinstaller` file can associate the installed package with an HTTPS update
  location.

The MSIX layout is assembled with the Windows SDK `MakeAppx.exe`. This follows
Microsoft's documented [MakeAppx packaging
flow](https://learn.microsoft.com/windows/msix/package/create-app-package-with-makeappx-tool).
The application is declared as a full-trust packaged classic desktop app. Its
own `%LOCALAPPDATA%\ClaudeUsage` directory is explicitly excluded from package
virtualization, so app/provider data is not package-owned and is not silently
removed during uninstall.

The MSIX declares an identity-based `windows.startupTask`. A small packaged
helper launches the main process with `--background`; Windows resolves the
helper relative to the current package version, so an update never leaves a
versioned `WindowsApps` path in the Run key. The portable ZIP continues to use
the per-user `HKCU Run` fallback and rewrites it whenever settings synchronize.
On first packaged launch, ClaudeUsage also removes its same-name legacy ZIP Run
value to avoid duplicate login launches.

## Build artifacts locally

The default command remains compatible with machines that only have the pinned
.NET SDK and produces the ZIP, SPDX SBOM, license notices, and SHA-256 files:

```powershell
pwsh -File windows/scripts/package.ps1 -Runtime win-x64
```

To require an MSIX, install the Windows 10/11 SDK (for `MakeAppx.exe`) and run:

```powershell
pwsh -File windows/scripts/package.ps1 `
  -Runtime win-x64 `
  -IncludeMsix `
  -RequireMsix `
  -PackageName "your.permanent.package.name" `
  -Publisher "CN=Exact certificate subject"
```

Every project commits its NuGet `packages.lock.json`; local packaging and both
Windows workflows restore in locked mode before using those exact dependencies.
CI downloads the pinned, Microsoft-signed `Microsoft.Windows.SDK.BuildTools`
NuGet through `get-windows-sdk-tools.ps1`, verifies its committed SHA-256, and
passes exact MakeAppx/SignTool paths. This avoids depending on whichever SDK a
hosted runner happens to contain. The script can also prepare the tools in a
local temporary directory when the full SDK is unavailable.

An unsigned MSIX is a structural CI artifact; Windows will not trust it for a
public install. Do not publish the development identity
`jaewoo4200.ClaudeUsage.Dev` or publisher `CN=ClaudeUsage Development`.

Every build includes:

- `ClaudeUsage-Windows-<version>-win-x64.zip`
- `ClaudeUsage-Windows-<version>-win-x64.spdx.json` (SPDX 2.3)
- one `.sha256` sidecar per artifact and `SHA256SUMS.txt`
- `LICENSE.txt`, generated `THIRD-PARTY-NOTICES.txt`, `SBOM.spdx.json`, and
  `build-info.json` inside the portable/MSIX payload
- `ClaudeUsage.Startup.exe`, the silent packaged login helper (not a second app)
- an MSIX when `-IncludeMsix` succeeds
- `ClaudeUsage.appinstaller` only when both HTTPS distribution URIs are passed

`global.json` disables SDK roll-forward, and packaging rejects any SDK other
than that exact version. `SOURCE_DATE_EPOCH` fixes build metadata and ZIP entry timestamps. CI sets it
to the source commit time and rebuilds the unsigned ZIP to verify byte-for-byte
reproducibility. RFC 3161 timestamps make signed outputs intentionally
non-reproducible; validate their source commit, SBOM, and signature instead.

Run the artifact checks locally or in CI:

```powershell
pwsh -File windows/scripts/validate-package.ps1 `
  -ArtifactRoot windows/artifacts `
  -Runtime win-x64 `
  -RequireMsix
```

For a signed release, `-RequireSignature` extracts the portable ZIP into an
isolated temporary directory and uses SignTool to validate the Authenticode
signature of every deployed `.exe` and `.dll`, in addition to validating the
MSIX signature. A single unsigned or invalid binary fails the release gate.

## Identity and code signing gate

Before the first public MSIX, freeze these values. Changing either later creates
a different app and breaks update continuity:

1. Package `Name` (3-50 allowed MSIX identity characters).
2. Manifest `Publisher`, which must exactly equal the signing certificate
   subject, including distinguished-name fields and order.

The checked-in public release ledger is
[`public-msix-version-ledger.json`](public-msix-version-ledger.json). Its
`latestPublicPackageVersion` is the source of truth for the four-part numeric
MSIX version. It must increase for every published package, including multiple
SemVer prereleases that share the same `major.minor.patch`; never reuse or
decrease that value. Pass the ledger's latest value to both packaging and
independent validation as `-PreviousPublicPackageVersion 1.2.3.4`. Before a
public release, the protected workflow requires the input to exactly match the
ledger and requires the candidate to be greater. Equality, downgrade, a stale
operator input, malformed history, and duplicate ledger entries all fail.

The ledger records releases that are already public, not the candidate awaiting
approval. After publication, append the released tag, package version, and a UTC
`publishedAtUtc` timestamp; update `latestPublicPackageVersion`; commit that
change before creating the next Windows release tag. The initial empty ledger
uses `0.0.0.0`, which is also the required baseline input for the first public
MSIX. Omitting `-PreviousPublicPackageVersion` remains suitable only for local
dry runs, where packaging and validation report an explicit `SKIPPED` result.

The sample in `identity.sample.json` is documentation, not a production
identity. Configure the real values as protected `windows-signing` environment
variables:

- `WINDOWS_PACKAGE_NAME`
- `WINDOWS_PACKAGE_PUBLISHER`
- `WINDOWS_PUBLISHER_DISPLAY_NAME`
- `WINDOWS_TIMESTAMP_URL` (an approved RFC 3161 HTTPS service)

Configure the certificate as protected secrets on the `windows-signing`
environment:

- `WINDOWS_SIGNING_PFX_BASE64`
- `WINDOWS_SIGNING_PFX_PASSWORD`
- `WINDOWS_SIGNING_PFX_SHA256`

The release-candidate workflow verifies the decoded PFX hash, imports it only
into the ephemeral runner's current-user certificate store, checks the subject
against the manifest publisher, signs the app binaries and MSIX with SHA-256,
verifies with `SignTool`, and removes both the file and imported certificate in
an `always()` cleanup step. Microsoft documents the same SignTool package
signing requirement in [Sign an app package using
SignTool](https://learn.microsoft.com/windows/msix/package/sign-app-package-using-signtool).

No workflow publishes an unsigned public installer. Public GitHub release
creation is a separate explicit boolean input, defaults to false, requires an
existing `windows-v<semver>` tag and confirmation that a prior dry-run candidate
from that tag passed the clean-machine checklist. Signing and publication are
separate jobs: the signed candidate is uploaded first, then the
`windows-production-release` environment must be approved. Reviewers can
download and inspect that exact artifact while publication waits. The publish
job downloads the same artifact rather than rebuilding it, rechecks checksums
and SignTool verification, and only then creates the release. Signed packages
and the GitHub release use `windows/SIGNED_RELEASE_NOTES.md`; the unsigned alpha
notes are never used on this path. Every Windows GitHub release is explicitly
created with `--latest=false`, and a tag with a SemVer prerelease suffix is also
created with GitHub's `--prerelease` classification.

## App Installer update channel

The release-candidate workflow requires two HTTPS inputs when generating
`ClaudeUsage.appinstaller`:

- `appinstaller_uri`: a **stable** URL that is overwritten with the newest
  `.appinstaller` metadata. It must not be versioned, and its decoded URL-path
  basename must be exactly `ClaudeUsage.appinstaller` (case-sensitive).
- `package_uri`: the immutable HTTPS URL of that version's signed MSIX.
  Its decoded URL-path basename must exactly match the generated asset,
  `ClaudeUsage-Windows-<project-version>-win-x64.msix` (case-sensitive).

The two files may use different hosts or directories. Query strings and URL
fragments do not participate in the basename comparison.

The 2021 App Installer schema checks every four hours on launch and also permits
background update checks. It never allows a downgrade. These settings require
Windows 10 2004+ and work on the supported Windows 11 target; see Microsoft's
[auto-update and repair overview](https://learn.microsoft.com/windows/msix/app-installer/auto-update-and-repair--overview)
and [manual App Installer file
format](https://learn.microsoft.com/windows/msix/app-installer/how-to-create-appinstaller-file).
The web host must serve correct content types and `Content-Length`. The
`ms-appinstaller` protocol can be disabled by organizational policy, so retain
the signed MSIX as a manual install/upgrade path.

## Uninstall and data ownership

MSIX owns only its protected program files. The package does not own or delete:

- `%LOCALAPPDATA%\ClaudeUsage` settings, history, and DPAPI session state
- `%USERPROFILE%\.claude`
- `%USERPROFILE%\.codex`

Uninstall therefore removes binaries and registrations while retaining user
data. A future explicit in-app “delete my ClaudeUsage data” action must remain a
separate, user-confirmed operation. Never add provider folders to an installer
cleanup rule.

Complete the [clean-machine smoke procedure](CLEAN_MACHINE_SMOKE.md) for every
release candidate. Its automated portion is explicitly an existing-user
lifecycle check: it intentionally refuses to run without a destructive-test
acknowledgement and refuses to touch an existing real package, process, or
legacy Run value. A pre-existing `%LOCALAPPDATA%\ClaudeUsage` directory may be
non-empty and is retained. That automated lifecycle check is only one part of
the separate disposable-VM clean-machine release gate.
