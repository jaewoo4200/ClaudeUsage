[CmdletBinding()]
param(
    [string]$ArtifactRoot,
    [ValidateSet("win-x64")]
    [string]$Runtime = "win-x64",
    [string]$ExpectedVersion,
    [string]$PreviousPublicPackageVersion,
    [switch]$RequireMsix,
    [switch]$RequireAppInstaller,
    [switch]$RequireSignature,
    [string]$SignToolPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $ArtifactRoot = Join-Path $windowsRoot "artifacts"
}
$artifactPath = [System.IO.Path]::GetFullPath($ArtifactRoot)
if (-not (Test-Path -LiteralPath $artifactPath -PathType Container)) {
    throw "Artifact directory does not exist: $artifactPath"
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
    $ExpectedVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "ExpectedVersion must be a concrete SemVer without wildcard characters."
}

function Get-SingleArtifact {
    param(
        [Parameter(Mandatory)] [string]$Pattern,
        [switch]$Optional
    )

    $matches = @(Get-ChildItem -LiteralPath $artifactPath -File -Filter $Pattern)
    if ($matches.Count -eq 0 -and $Optional) {
        return $null
    }
    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$Pattern' artifact, found $($matches.Count)."
    }
    return $matches[0]
}

function Read-ZipEntryText {
    param(
        [Parameter(Mandatory)] [System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory)] [string]$Name
    )

    $entry = $Archive.GetEntry($Name)
    if ($null -eq $entry) {
        throw "Required archive entry is missing: $Name"
    }
    $stream = $entry.Open()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Read-ZipEntryBytes {
    param(
        [Parameter(Mandatory)] [System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory)] [string]$Name
    )

    $entry = $Archive.GetEntry($Name)
    if ($null -eq $entry) {
        throw "Required archive entry is missing: $Name"
    }
    $input = $entry.Open()
    $output = [System.IO.MemoryStream]::new()
    try {
        $input.CopyTo($output)
        return $output.ToArray()
    }
    finally {
        $output.Dispose()
        $input.Dispose()
    }
}

function Assert-SidecarChecksum {
    param([Parameter(Mandatory)] [System.IO.FileInfo]$Artifact)

    $sidecarPath = "$($Artifact.FullName).sha256"
    if (-not (Test-Path -LiteralPath $sidecarPath -PathType Leaf)) {
        throw "Checksum sidecar is missing: $sidecarPath"
    }
    $line = (Get-Content -LiteralPath $sidecarPath -Raw).Trim()
    if ($line -notmatch '^(?<hash>[a-f0-9]{64})  (?<name>.+)$') {
        throw "Checksum sidecar has an invalid format: $sidecarPath"
    }
    if ($Matches.name -cne $Artifact.Name) {
        throw "Checksum sidecar names '$($Matches.name)' instead of '$($Artifact.Name)'."
    }
    $actual = (Get-FileHash -LiteralPath $Artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Matches.hash) {
        throw "SHA-256 mismatch for $($Artifact.Name)."
    }
}

function Find-SignTool {
    if (-not [string]::IsNullOrWhiteSpace($SignToolPath)) {
        return [System.IO.Path]::GetFullPath($SignToolPath)
    }
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path -LiteralPath $sdkRoot) {
        foreach ($directory in (Get-ChildItem -LiteralPath $sdkRoot -Directory |
            Where-Object Name -Match '^\d+\.\d+\.\d+\.\d+$' |
            Sort-Object { [Version]$_.Name } -Descending)) {
            $candidate = Join-Path $directory.FullName "x64\signtool.exe"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }
    return $null
}

function ConvertTo-MsixVersion {
    param(
        [Parameter(Mandatory)] [string]$Value,
        [Parameter(Mandatory)] [string]$Description
    )

    if ($Value -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "$Description must contain four numeric parts: $Value"
    }
    foreach ($part in $Value.Split('.')) {
        $numericPart = [uint32]$part
        if ($numericPart -gt 65535) {
            throw "Every $Description part must be between 0 and 65535: $Value"
        }
    }
    return [Version]$Value
}

function Get-UriAssetName {
    param([Parameter(Mandatory)] [Uri]$Uri)

    return [Uri]::UnescapeDataString(
        [System.IO.Path]::GetFileName($Uri.AbsolutePath))
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$artifactVersionPattern = if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { "*" } else { $ExpectedVersion }
$zip = Get-SingleArtifact -Pattern "ClaudeUsage-Windows-$artifactVersionPattern-$Runtime.zip"
$sbom = Get-SingleArtifact -Pattern "ClaudeUsage-Windows-$artifactVersionPattern-$Runtime.spdx.json"
Assert-SidecarChecksum -Artifact $zip
Assert-SidecarChecksum -Artifact $sbom

$checksumManifest = Join-Path $artifactPath "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $checksumManifest -PathType Leaf)) {
    throw "SHA256SUMS.txt is missing."
}
$manifestEntries = @{}
foreach ($line in Get-Content -LiteralPath $checksumManifest) {
    if ($line -notmatch '^(?<hash>[a-f0-9]{64})  (?<name>.+)$') {
        throw "Invalid SHA256SUMS.txt line: $line"
    }
    $manifestEntries[$Matches.name] = $Matches.hash
    $target = Join-Path $artifactPath $Matches.name
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "SHA256SUMS.txt references a missing artifact: $($Matches.name)"
    }
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Matches.hash) {
        throw "SHA256SUMS.txt mismatch for $($Matches.name)."
    }
}

$zipArchive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
try {
    $requiredEntries = @(
        "ClaudeUsage.Windows.exe",
        "ClaudeUsage.Windows.dll",
        "ClaudeUsage.Windows.deps.json",
        "ClaudeUsage.Windows.runtimeconfig.json",
        "ClaudeUsage.Core.dll",
        "ClaudeUsage.Startup.exe",
        "ClaudeUsage.Startup.dll",
        "ClaudeUsage.Startup.deps.json",
        "ClaudeUsage.Startup.runtimeconfig.json",
        "Microsoft.Windows.SDK.NET.dll",
        "WinRT.Runtime.dll",
        "coreclr.dll",
        "clrjit.dll",
        "hostfxr.dll",
        "hostpolicy.dll",
        "System.Private.CoreLib.dll",
        "PresentationCore.dll",
        "PresentationFramework.dll",
        "WindowsBase.dll",
        "Microsoft.Web.WebView2.Core.dll",
        "Microsoft.Web.WebView2.Wpf.dll",
        "WebView2Loader.dll",
        "LICENSE.txt",
        "THIRD-PARTY-NOTICES.txt",
        "README.md",
        "RELEASE_NOTES.md",
        "build-info.json",
        "SBOM.spdx.json"
    )
    foreach ($entryName in $requiredEntries) {
        if ($null -eq $zipArchive.GetEntry($entryName)) {
            throw "ZIP is missing required entry: $entryName"
        }
    }
    foreach ($entry in $zipArchive.Entries) {
        if ($entry.FullName -match '(?i)(\.pfx$|\.p12$|settings\.json$|cookies?\.json$|\.pdb$)') {
            throw "ZIP contains a forbidden secret/debug artifact: $($entry.FullName)"
        }
    }

    $buildInfo = Read-ZipEntryText -Archive $zipArchive -Name "build-info.json" | ConvertFrom-Json
    if ($buildInfo.runtime -cne $Runtime -or -not $buildInfo.selfContained) {
        throw "build-info.json does not describe a self-contained $Runtime build."
    }
    if ($RequireSignature -and -not $buildInfo.signed) {
        throw "build-info.json does not identify a signed release build."
    }
    $expectedSdkVersion = (Get-Content -LiteralPath (Join-Path $repoRoot "global.json") -Raw |
        ConvertFrom-Json).sdk.version
    if ($buildInfo.dotnetSdkVersion -cne $expectedSdkVersion) {
        throw "build-info.json does not identify the pinned .NET SDK $expectedSdkVersion."
    }
    $projectXml = [xml](Get-Content -LiteralPath (Join-Path $windowsRoot "src\ClaudeUsage.Windows\ClaudeUsage.Windows.csproj") -Raw)
    $expectedWindowsSdkNetVersion = [string]($projectXml.Project.PropertyGroup.WindowsSdkPackageVersion |
        Select-Object -First 1)
    if ($buildInfo.windowsSdkNetVersion -cne $expectedWindowsSdkNetVersion) {
        throw "build-info.json does not identify the pinned Windows SDK .NET projection $expectedWindowsSdkNetVersion."
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $git -and $buildInfo.sourceCommit -cne "unknown") {
        $headCommitOutput = @(& $git.Source -C $repoRoot rev-parse HEAD 2>$null)
        $headCommitExitCode = $LASTEXITCODE
        $headCommit = if ($headCommitOutput.Count -gt 0) { [string]$headCommitOutput[0] } else { $null }
        if ($headCommitExitCode -ne 0 -or
            [string]::IsNullOrWhiteSpace($headCommit) -or
            $buildInfo.sourceCommit -cne $headCommit.Trim()) {
            throw "build-info.json source commit does not match the checked-out source."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and $buildInfo.version -cne $ExpectedVersion) {
        throw "Expected version '$ExpectedVersion', found '$($buildInfo.version)'."
    }
    if ([string]$buildInfo.version -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)') {
        throw "build-info.json contains an invalid product version '$($buildInfo.version)'."
    }
    $expectedFileVersion = "$($Matches.major).$($Matches.minor).$($Matches.patch).0"
    $versionCheckDirectory = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        "ClaudeUsage-version-check-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $versionCheckDirectory | Out-Null
    try {
        foreach ($binaryName in @(
            "ClaudeUsage.Windows.exe",
            "ClaudeUsage.Windows.dll",
            "ClaudeUsage.Core.dll",
            "ClaudeUsage.Startup.exe",
            "ClaudeUsage.Startup.dll")) {
            $binaryPath = Join-Path $versionCheckDirectory $binaryName
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
                $zipArchive.GetEntry($binaryName),
                $binaryPath)
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($binaryPath)
            if ($versionInfo.FileVersion -cne $expectedFileVersion) {
                throw "$binaryName has file version '$($versionInfo.FileVersion)' instead of '$expectedFileVersion'."
            }
            if ($versionInfo.ProductVersion -cne [string]$buildInfo.version -and
                -not $versionInfo.ProductVersion.StartsWith(
                    "$($buildInfo.version)+",
                    [StringComparison]::Ordinal)) {
                throw "$binaryName has product version '$($versionInfo.ProductVersion)' instead of '$($buildInfo.version)'."
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $versionCheckDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    $releaseNotesText = Read-ZipEntryText -Archive $zipArchive -Name "RELEASE_NOTES.md"
    if ($RequireSignature -and
        ($releaseNotesText.IndexOf("signed", [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
            $releaseNotesText.IndexOf("unsigned", [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
        throw "A signed release ZIP must contain signed-release notes without an unsigned-build claim."
    }
    $noticeText = Read-ZipEntryText -Archive $zipArchive -Name "THIRD-PARTY-NOTICES.txt"
    foreach ($component in @(
        "Microsoft.Web.WebView2",
        "Microsoft.Windows.SDK.NET.Ref",
        "Microsoft.NETCore.App.Runtime",
        "Microsoft.WindowsDesktop.App.Runtime")) {
        if ($noticeText.IndexOf($component, [StringComparison]::Ordinal) -lt 0) {
            throw "Third-party notices do not identify $component."
        }
    }
    [byte[]]$embeddedSbomBytes = Read-ZipEntryBytes -Archive $zipArchive -Name "SBOM.spdx.json"
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $embeddedSbomText = $strictUtf8.GetString($embeddedSbomBytes)
    $embeddedSbom = $embeddedSbomText.TrimStart([char]0xfeff) | ConvertFrom-Json
    if ($embeddedSbom.spdxVersion -cne "SPDX-2.3" -or
        $embeddedSbom.packages.Count -lt 5 -or
        $embeddedSbom.files.Count -lt 1) {
        throw "Embedded SPDX SBOM is incomplete."
    }
    $windowsSdkPackage = @($embeddedSbom.packages |
        Where-Object { $_.name -ceq "Microsoft.Windows.SDK.NET.Ref" })
    if ($windowsSdkPackage.Count -ne 1 -or
        $windowsSdkPackage[0].versionInfo -cne $buildInfo.windowsSdkNetVersion -or
        $windowsSdkPackage[0].licenseDeclared -cne "NOASSERTION") {
        throw "Embedded SPDX SBOM does not describe the pinned Windows SDK .NET projection."
    }
    if ($noticeText.IndexOf(
        "Microsoft.Windows.SDK.NET.Ref $($buildInfo.windowsSdkNetVersion)",
        [StringComparison]::Ordinal) -lt 0) {
        throw "Third-party notices do not identify the pinned Windows SDK .NET projection version."
    }
}
finally {
    $zipArchive.Dispose()
}

if ($RequireSignature) {
    $zipSignTool = Find-SignTool
    if ([string]::IsNullOrWhiteSpace($zipSignTool)) {
        throw "SignTool.exe is required to verify release binary signatures."
    }
    $signatureCheckDirectory = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        "ClaudeUsage-signature-check-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $signatureCheckDirectory | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory(
            $zip.FullName,
            $signatureCheckDirectory)
        $deploymentBinaries = @(Get-ChildItem -LiteralPath $signatureCheckDirectory -Recurse -File |
            Where-Object { $_.Extension -in @(".exe", ".dll") } |
            Sort-Object FullName)
        if ($deploymentBinaries.Count -eq 0) {
            throw "The portable ZIP contains no EXE/DLL deployment binaries to verify."
        }
        foreach ($requiredBinary in @("ClaudeUsage.Windows.exe", "ClaudeUsage.Startup.exe")) {
            if (-not (Test-Path -LiteralPath (Join-Path $signatureCheckDirectory $requiredBinary) -PathType Leaf)) {
                throw "Signed ZIP entry is missing: $requiredBinary"
            }
        }

        $signatureBatchSize = 40
        for ($offset = 0; $offset -lt $deploymentBinaries.Count; $offset += $signatureBatchSize) {
            $batch = @($deploymentBinaries | Select-Object -Skip $offset -First $signatureBatchSize)
            $signatureArguments = @("verify", "/pa", "/all", "/v") + @(
                $batch | Select-Object -ExpandProperty FullName)
            & $zipSignTool @signatureArguments
            if ($LASTEXITCODE -ne 0) {
                $failedBatch = @($batch | ForEach-Object {
                    $_.FullName.Substring($signatureCheckDirectory.Length + 1)
                }) -join ", "
                throw "SignTool rejected one or more portable ZIP binary signatures: $failedBatch"
            }
        }
        Write-Output "Validated Authenticode signatures for all $($deploymentBinaries.Count) portable ZIP EXE/DLL files."
    }
    finally {
        Remove-Item -LiteralPath $signatureCheckDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

[byte[]]$standaloneSbomBytes = [System.IO.File]::ReadAllBytes($sbom.FullName)
$standaloneSbomText = $strictUtf8.GetString($standaloneSbomBytes)
$standaloneSbom = $standaloneSbomText.TrimStart([char]0xfeff) | ConvertFrom-Json
if ($standaloneSbom.spdxVersion -cne "SPDX-2.3") {
    throw "Standalone SBOM is not SPDX 2.3 JSON."
}
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $embeddedSbomHash = ([BitConverter]::ToString($sha256.ComputeHash($embeddedSbomBytes))).Replace("-", "")
    $standaloneSbomHash = ([BitConverter]::ToString($sha256.ComputeHash($standaloneSbomBytes))).Replace("-", "")
}
finally {
    $sha256.Dispose()
}
if ($standaloneSbomHash -cne $embeddedSbomHash) {
    throw "Standalone and embedded SPDX SBOM files are not identical."
}

$msix = Get-SingleArtifact -Pattern "ClaudeUsage-Windows-$artifactVersionPattern-$Runtime.msix" -Optional:(-not $RequireMsix)
if ($null -ne $msix) {
    Assert-SidecarChecksum -Artifact $msix
    $msixArchive = [System.IO.Compression.ZipFile]::OpenRead($msix.FullName)
    try {
        foreach ($entryName in @(
            "AppxManifest.xml",
            "AppxBlockMap.xml",
            "[Content_Types].xml",
            "Assets/StoreLogo.png",
            "Assets/Square44x44Logo.png",
            "Assets/Square150x150Logo.png",
            "Assets/Wide310x150Logo.png",
            "ClaudeUsage.Windows.exe",
            "ClaudeUsage.Windows.dll",
            "ClaudeUsage.Core.dll",
            "Microsoft.Web.WebView2.Core.dll",
            "Microsoft.Web.WebView2.Wpf.dll",
            "WebView2Loader.dll",
            "build-info.json",
            "SBOM.spdx.json",
            "ClaudeUsage.Startup.exe")) {
            if ($null -eq $msixArchive.GetEntry($entryName)) {
                throw "MSIX is missing required entry: $entryName"
            }
        }

        $manifestXml = [xml](Read-ZipEntryText -Archive $msixArchive -Name "AppxManifest.xml")
        $namespace = [System.Xml.XmlNamespaceManager]::new($manifestXml.NameTable)
        $namespace.AddNamespace("f", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
        $namespace.AddNamespace("desktop", "http://schemas.microsoft.com/appx/manifest/desktop/windows10")
        $namespace.AddNamespace("uap10", "http://schemas.microsoft.com/appx/manifest/uap/windows10/10")
        $identity = $manifestXml.SelectSingleNode("/f:Package/f:Identity", $namespace)
        if ($null -eq $identity) {
            throw "MSIX manifest identity is missing."
        }
        if ($identity.Name -cne $buildInfo.packageIdentity -or
            $identity.Publisher -cne $buildInfo.publisher -or
            $identity.Version -cne $buildInfo.msixVersion) {
            throw "MSIX identity does not match build-info.json."
        }
        $application = $manifestXml.SelectSingleNode("/f:Package/f:Applications/f:Application", $namespace)
        if ($null -eq $application -or
            $application.Id -cne "App" -or
            $application.Executable -cne "ClaudeUsage.Windows.exe" -or
            $application.EntryPoint -cne "Windows.FullTrustApplication" -or
            $application.GetAttribute("RuntimeBehavior", "http://schemas.microsoft.com/appx/manifest/uap/windows10/10") -cne "packagedClassicApp" -or
            $application.GetAttribute("TrustLevel", "http://schemas.microsoft.com/appx/manifest/uap/windows10/10") -cne "mediumIL") {
            throw "MSIX does not contain the expected main full-trust application entry."
        }
        $startupExtension = $manifestXml.SelectSingleNode(
            "/f:Package/f:Applications/f:Application/f:Extensions/desktop:Extension[@Category='windows.startupTask']",
            $namespace)
        $startupTask = if ($null -eq $startupExtension) {
            $null
        }
        else {
            $startupExtension.SelectSingleNode("desktop:StartupTask", $namespace)
        }
        if ($null -eq $startupExtension -or $null -eq $startupTask -or
            $startupExtension.Executable -cne "ClaudeUsage.Startup.exe" -or
            $startupExtension.EntryPoint -cne "Windows.FullTrustApplication" -or
            $startupTask.TaskId -cne "ClaudeUsageStartup" -or
            $startupTask.Enabled -cne "false") {
            throw "MSIX does not contain the expected identity-based startup task."
        }
        $hasSignature = $null -ne $msixArchive.GetEntry("AppxSignature.p7x")
        if ($RequireSignature -and -not $hasSignature) {
            throw "MSIX does not contain an AppxSignature.p7x signature."
        }
    }
    finally {
        $msixArchive.Dispose()
    }

    if ($RequireSignature) {
        $signTool = Find-SignTool
        if ([string]::IsNullOrWhiteSpace($signTool)) {
            throw "SignTool.exe is required to verify a release signature."
        }
        & $signTool verify /pa /all /v $msix.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "SignTool rejected the MSIX signature."
        }
    }
}

$appInstaller = Get-SingleArtifact -Pattern "ClaudeUsage.appinstaller" -Optional:(-not $RequireAppInstaller)
if ($null -ne $appInstaller) {
    Assert-SidecarChecksum -Artifact $appInstaller
    if ($null -eq $msix) {
        throw "An App Installer file exists without an MSIX."
    }
    $appInstallerXml = [xml](Get-Content -LiteralPath $appInstaller.FullName -Raw)
    $namespaceUri = "http://schemas.microsoft.com/appx/appinstaller/2021"
    $namespace = [System.Xml.XmlNamespaceManager]::new($appInstallerXml.NameTable)
    $namespace.AddNamespace("a", $namespaceUri)
    $root = $appInstallerXml.SelectSingleNode("/a:AppInstaller", $namespace)
    $mainPackage = $appInstallerXml.SelectSingleNode("/a:AppInstaller/a:MainPackage", $namespace)
    if ($null -eq $root -or $null -eq $mainPackage) {
        throw "App Installer 2021 document is incomplete."
    }
    $appInstallerDistributionUri = $null
    $packageDistributionUri = $null
    if (-not [Uri]::TryCreate(
            [string]$root.Uri,
            [UriKind]::Absolute,
            [ref]$appInstallerDistributionUri) -or
        $appInstallerDistributionUri.Scheme -cne "https" -or
        -not [Uri]::TryCreate(
            [string]$mainPackage.Uri,
            [UriKind]::Absolute,
            [ref]$packageDistributionUri) -or
        $packageDistributionUri.Scheme -cne "https") {
        throw "App Installer distribution URIs must be absolute HTTPS URLs."
    }
    $appInstallerUriAssetName = Get-UriAssetName -Uri $appInstallerDistributionUri
    if ($appInstallerUriAssetName -cne $appInstaller.Name) {
        throw "App Installer URI asset basename must match '$($appInstaller.Name)', found '$appInstallerUriAssetName'."
    }
    $packageUriAssetName = Get-UriAssetName -Uri $packageDistributionUri
    if ($packageUriAssetName -cne $msix.Name) {
        throw "MainPackage URI asset basename must match '$($msix.Name)', found '$packageUriAssetName'."
    }
    if ($root.Version -cne $buildInfo.msixVersion -or
        $mainPackage.Name -cne $buildInfo.packageIdentity -or
        $mainPackage.Publisher -cne $buildInfo.publisher -or
        $mainPackage.Version -cne $buildInfo.msixVersion) {
        throw "App Installer identity does not match the MSIX."
    }
    $updateSettings = $appInstallerXml.SelectSingleNode("/a:AppInstaller/a:UpdateSettings", $namespace)
    $onLaunch = $appInstallerXml.SelectSingleNode("/a:AppInstaller/a:UpdateSettings/a:OnLaunch", $namespace)
    $backgroundTask = $appInstallerXml.SelectSingleNode("/a:AppInstaller/a:UpdateSettings/a:AutomaticBackgroundTask", $namespace)
    $forceUpdate = $appInstallerXml.SelectSingleNode("/a:AppInstaller/a:UpdateSettings/a:ForceUpdateFromAnyVersion", $namespace)
    if ($null -eq $updateSettings -or $null -eq $onLaunch -or $null -eq $backgroundTask -or
        $null -eq $forceUpdate -or $onLaunch.HoursBetweenUpdateChecks -cne "4" -or
        $onLaunch.ShowPrompt -cne "true" -or $onLaunch.UpdateBlocksActivation -cne "false" -or
        $forceUpdate.InnerText.Trim() -cne "false") {
        throw "App Installer update policy does not match the release policy."
    }
}

$currentPublicCandidateVersion = ConvertTo-MsixVersion `
    -Value ([string]$buildInfo.msixVersion) `
    -Description "candidate MSIX version"
if ([string]::IsNullOrWhiteSpace($PreviousPublicPackageVersion)) {
    Write-Output "Version monotonicity: SKIPPED (PreviousPublicPackageVersion was not supplied)."
}
else {
    if ($null -eq $msix) {
        throw "PreviousPublicPackageVersion requires an MSIX artifact to validate."
    }
    $previousPublicVersion = ConvertTo-MsixVersion `
        -Value $PreviousPublicPackageVersion `
        -Description "previous public MSIX version"
    if ($currentPublicCandidateVersion.CompareTo($previousPublicVersion) -le 0) {
        throw "MSIX/App Installer version '$currentPublicCandidateVersion' must be greater than the previous public version '$previousPublicVersion'."
    }
    if ($buildInfo.previousPublicMsixVersion -cne $previousPublicVersion.ToString() -or
        $buildInfo.versionMonotonicity -cne "verified-increase") {
        throw "build-info.json does not record the validated previous public MSIX version."
    }
    Write-Output "Version monotonicity: VERIFIED ($previousPublicVersion -> $currentPublicCandidateVersion)."
}

$requiredChecksumArtifacts = @($zip, $sbom)
if ($null -ne $msix) {
    $requiredChecksumArtifacts += $msix
}
if ($null -ne $appInstaller) {
    $requiredChecksumArtifacts += $appInstaller
}
foreach ($requiredArtifact in $requiredChecksumArtifacts) {
    $requiredName = $requiredArtifact.Name
    if (-not $manifestEntries.ContainsKey($requiredName)) {
        throw "SHA256SUMS.txt does not cover $requiredName."
    }
}

Write-Output "Validated ZIP, SPDX SBOM, licenses, and checksums for $($buildInfo.version)."
if ($null -ne $msix) {
    Write-Output "Validated MSIX identity $($buildInfo.packageIdentity) $($buildInfo.msixVersion)."
}
if ($null -ne $appInstaller) {
    Write-Output "Validated App Installer update metadata."
}
