# ClaudeUsage for Windows

This is a signed, self-contained Windows 11 x64 release. Release maturity
(stable or prerelease) follows the `windows-v<semver>` tag.

The release includes Authenticode-signed portable binaries, a signed MSIX, an
HTTPS App Installer update manifest, SHA-256 checksums, and an SPDX 2.3 SBOM.
Verify the downloaded artifact against its `.sha256` sidecar or
`SHA256SUMS.txt` before installation.

Claude sign-in requires Microsoft Edge WebView2 Evergreen Runtime. Claude quota
retrieval depends on an undocumented `claude.ai` endpoint that may change, and
`win-arm64` is not currently published.
