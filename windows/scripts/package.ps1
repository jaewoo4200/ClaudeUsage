[CmdletBinding()]
param(
    [ValidateSet("win-x64")]
    [string]$Runtime = "win-x64",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$DotNet = "dotnet",
    [switch]$SkipRestore,
    [switch]$SkipTests,
    [switch]$IncludeMsix,
    [switch]$RequireMsix,
    [string]$PackageName = "jaewoo4200.ClaudeUsage.Dev",
    [string]$Publisher = "CN=ClaudeUsage Development",
    [string]$PublisherDisplayName = "Jaewoo Lee",
    [string]$PackageVersion,
    [string]$PreviousPublicPackageVersion,
    [string]$AppInstallerUri,
    [string]$PackageUri,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl,
    [string]$MakeAppxPath,
    [string]$SignToolPath,
    [switch]$RequireSignature
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot
$globalJson = Join-Path $repoRoot "global.json"
$solution = Join-Path $windowsRoot "ClaudeUsage.Windows.sln"
$project = Join-Path $windowsRoot "src\ClaudeUsage.Windows\ClaudeUsage.Windows.csproj"
$startupProject = Join-Path $windowsRoot "src\ClaudeUsage.Startup\ClaudeUsage.Startup.csproj"
$nugetConfig = Join-Path $windowsRoot "NuGet.Config"
$artifactRoot = Join-Path $windowsRoot "artifacts"
$publishDirectory = Join-Path $artifactRoot $Runtime
$msixLayoutDirectory = Join-Path $artifactRoot "msix-layout-$Runtime"
$manifestTemplate = Join-Path $windowsRoot "packaging\msix\AppxManifest.xml.in"
$appInstallerTemplate = Join-Path $windowsRoot "packaging\msix\ClaudeUsage.appinstaller.in"
$assetScript = Join-Path $PSScriptRoot "build-msix-assets.ps1"
$sbomScript = Join-Path $PSScriptRoot "generate-sbom.ps1"
$releaseNotesPath = if ($RequireSignature) {
    Join-Path $windowsRoot "SIGNED_RELEASE_NOTES.md"
}
else {
    Join-Path $windowsRoot "RELEASE_NOTES.md"
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory)] [string]$Parent,
        [Parameter(Mandatory)] [string]$Child
    )

    $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $childPath = [System.IO.Path]::GetFullPath($Child)
    if (-not $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the artifact directory: $childPath"
    }
}

function Invoke-DotNet {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$Arguments)

    & $DotNet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet command failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
}

function Invoke-NativeTool {
    param(
        [Parameter(Mandatory)] [string]$Tool,
        [Parameter(ValueFromRemainingArguments)] [string[]]$Arguments
    )

    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$([System.IO.Path]::GetFileName($Tool)) failed with exit code ${LASTEXITCODE}."
    }
}

function Find-WindowsSdkTool {
    param([Parameter(Mandatory)] [string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $kitRoots = @(
        (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"),
        (Join-Path $env:ProgramFiles "Windows Kits\10\bin")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }

    foreach ($root in $kitRoots) {
        $versionDirectories = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [Version]$_.Name } -Descending
        foreach ($directory in $versionDirectories) {
            foreach ($architecture in @("x64", "x86")) {
                $candidate = Join-Path $directory.FullName "$architecture\$Name"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $certificationKitCandidate = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\App Certification Kit\$Name"
        if (Test-Path -LiteralPath $certificationKitCandidate -PathType Leaf) {
            return $certificationKitCandidate
        }
    }

    return $null
}

function Resolve-PackageVersion {
    param(
        [Parameter(Mandatory)] [string]$ProjectVersion,
        [string]$RequestedVersion
    )

    $candidate = $RequestedVersion
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        if ($ProjectVersion -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)') {
            throw "Project version '$ProjectVersion' cannot be converted to a four-part MSIX version."
        }
        $candidate = "$($Matches.major).$($Matches.minor).$($Matches.patch).0"
    }

    if ($candidate -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "MSIX package version must contain four numeric parts: $candidate"
    }
    foreach ($part in $candidate.Split('.')) {
        $value = [uint32]$part
        if ($value -gt 65535) {
            throw "Every MSIX version part must be between 0 and 65535: $candidate"
        }
    }
    return ([Version]$candidate).ToString()
}

function Get-UriAssetName {
    param([Parameter(Mandatory)] [Uri]$Uri)

    return [Uri]::UnescapeDataString(
        [System.IO.Path]::GetFileName($Uri.AbsolutePath))
}

function ConvertTo-XmlText {
    param([Parameter(Mandatory)] [string]$Value)

    return [System.Security.SecurityElement]::Escape($Value)
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)] [string]$BaseDirectory,
        [Parameter(Mandatory)] [string]$Path
    )

    $basePath = [System.IO.Path]::GetFullPath($BaseDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $baseUri = [Uri]$basePath
    $pathUri = [Uri][System.IO.Path]::GetFullPath($Path)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar)
}

function Expand-Template {
    param(
        [Parameter(Mandatory)] [string]$TemplatePath,
        [Parameter(Mandatory)] [hashtable]$Values,
        [Parameter(Mandatory)] [string]$DestinationPath
    )

    $content = Get-Content -LiteralPath $TemplatePath -Raw
    foreach ($entry in $Values.GetEnumerator()) {
        $content = $content.Replace("@@$($entry.Key)@@", (ConvertTo-XmlText -Value ([string]$entry.Value)))
    }
    if ($content -match '@@[A-Z0-9_]+@@') {
        throw "Unexpanded packaging token remains in $TemplatePath."
    }
    Set-Content -LiteralPath $DestinationPath -Value $content -Encoding utf8
}

function New-ThirdPartyNotices {
    param(
        [Parameter(Mandatory)] [string]$DependenciesPath,
        [Parameter(Mandatory)] [string]$PackagesRoot,
        [Parameter(Mandatory)] [string]$WindowsSdkNetVersion,
        [Parameter(Mandatory)] [string]$DestinationPath
    )

    $deps = Get-Content -LiteralPath $DependenciesPath -Raw | ConvertFrom-Json
    $components = [System.Collections.Generic.List[object]]::new()
    foreach ($library in $deps.libraries.PSObject.Properties | Sort-Object Name) {
        $parts = $library.Name.Split('/', 2)
        if ($parts.Count -ne 2) {
            continue
        }
        $name = $parts[0]
        if ($name -eq "Microsoft.Web.WebView2") {
            $components.Add([pscustomobject]@{ Name = $name; Package = $name; Version = $parts[1] })
        }
        elseif ($name.StartsWith("runtimepack.Microsoft.NETCore.App.Runtime.", [StringComparison]::Ordinal) -or
                $name.StartsWith("runtimepack.Microsoft.WindowsDesktop.App.Runtime.", [StringComparison]::Ordinal)) {
            $packageName = $name.Substring("runtimepack.".Length)
            $components.Add([pscustomobject]@{ Name = $packageName; Package = $packageName; Version = $parts[1] })
        }
    }
    $components.Add([pscustomobject]@{
        Name = "Microsoft.Windows.SDK.NET.Ref"
        Package = "Microsoft.Windows.SDK.NET.Ref"
        Version = $WindowsSdkNetVersion
    })

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine("THIRD-PARTY NOTICES FOR CLAUDEUSAGE FOR WINDOWS")
    [void]$builder.AppendLine("Generated from the exact NuGet/runtime packages in this build.")
    [void]$builder.AppendLine()
    foreach ($component in $components | Sort-Object Name -Unique) {
        $componentDirectory = Join-Path $PackagesRoot "$($component.Package.ToLowerInvariant())\$($component.Version)"
        if (-not (Test-Path -LiteralPath $componentDirectory -PathType Container)) {
            throw "License source package is missing: $componentDirectory"
        }

        $noticeFiles = @(Get-ChildItem -LiteralPath $componentDirectory -File |
            Where-Object { $_.Name -match '^(LICENSE|NOTICE|THIRD-PARTY-NOTICES)(\.|$)' } |
            Sort-Object Name)
        if ($noticeFiles.Count -eq 0 -and $component.Name -cne "Microsoft.Windows.SDK.NET.Ref") {
            throw "No license or notice file was found for $($component.Name) $($component.Version)."
        }

        [void]$builder.AppendLine(('=' * 78))
        [void]$builder.AppendLine("$($component.Name) $($component.Version)")
        if ($component.Name -ceq "Microsoft.Windows.SDK.NET.Ref") {
            [void]$builder.AppendLine(('-' * 78))
            [void]$builder.AppendLine("The package declares the Microsoft Windows SDK license at:")
            [void]$builder.AppendLine("https://aka.ms/WinSDKLicenseURL")
            [void]$builder.AppendLine("Copyright (c) Microsoft Corporation. All rights reserved.")
            [void]$builder.AppendLine()
        }
        foreach ($noticeFile in $noticeFiles) {
            [void]$builder.AppendLine(('-' * 78))
            [void]$builder.AppendLine($noticeFile.Name)
            [void]$builder.AppendLine((Get-Content -LiteralPath $noticeFile.FullName -Raw).TrimEnd())
            [void]$builder.AppendLine()
        }
    }

    Set-Content -LiteralPath $DestinationPath -Value $builder.ToString() -Encoding utf8
}

function New-DeterministicZip {
    param(
        [Parameter(Mandatory)] [string]$SourceDirectory,
        [Parameter(Mandatory)] [string]$DestinationPath,
        [Parameter(Mandatory)] [DateTimeOffset]$Timestamp
    )

    Add-Type -AssemblyName System.IO.Compression
    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }

    $fixedTimestamp = $Timestamp.ToUniversalTime()
    if ($fixedTimestamp.Year -lt 1980) {
        $fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    }

    $fileStream = [System.IO.File]::Open(
        $DestinationPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None)
    $archive = [System.IO.Compression.ZipArchive]::new(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false,
        [System.Text.Encoding]::UTF8)
    try {
        $sourcePath = [System.IO.Path]::GetFullPath($SourceDirectory)
        $files = Get-ChildItem -LiteralPath $sourcePath -Recurse -File |
            Sort-Object { Get-RelativePath -BaseDirectory $sourcePath -Path $_.FullName }
        foreach ($file in $files) {
            $relativePath = (Get-RelativePath -BaseDirectory $sourcePath -Path $file.FullName).Replace('\', '/')
            $input = $null
            try {
                # OneDrive, antivirus, and indexers can briefly take an
                # exclusive handle immediately after dotnet publish. Retry only
                # that transient IOException and retain read-only sharing so a
                # concurrently modified payload can never enter the archive.
                for ($attempt = 0; $attempt -lt 8; $attempt++) {
                    try {
                        $input = [System.IO.File]::Open(
                            $file.FullName,
                            [System.IO.FileMode]::Open,
                            [System.IO.FileAccess]::Read,
                            [System.IO.FileShare]::Read)
                        break
                    }
                    catch [System.IO.IOException] {
                        if ($attempt -eq 7) {
                            throw
                        }
                        Start-Sleep -Milliseconds (75 * ($attempt + 1))
                    }
                }

                $entry = $archive.CreateEntry(
                    $relativePath,
                    [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTimestamp
                $output = $entry.Open()
                try {
                    $input.CopyTo($output)
                }
                finally {
                    $output.Dispose()
                }
            }
            finally {
                if ($null -ne $input) {
                    $input.Dispose()
                }
            }
        }
    }
    finally {
        $archive.Dispose()
        $fileStream.Dispose()
    }
}

function Set-ZipContainerTimestamp {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [DateTimeOffset]$Timestamp
    )

    # MakeAppx preserves package payloads but stamps the ZIP local/central headers
    # with the packaging clock. Normalize those metadata fields before signing so
    # identical inputs and SOURCE_DATE_EPOCH produce a byte-identical MSIX.
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)

    function Read-UInt16([int]$Offset) {
        return [BitConverter]::ToUInt16($bytes, $Offset)
    }

    function Read-UInt32([int]$Offset) {
        return [BitConverter]::ToUInt32($bytes, $Offset)
    }

    function Read-UInt64([int]$Offset) {
        return [BitConverter]::ToUInt64($bytes, $Offset)
    }

    function Write-UInt16([int]$Offset, [uint16]$Value) {
        [BitConverter]::GetBytes($Value).CopyTo($bytes, $Offset)
    }

    $fixedTimestamp = $Timestamp.ToUniversalTime()
    if ($fixedTimestamp.Year -lt 1980) {
        $fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    }
    elseif ($fixedTimestamp.Year -gt 2107) {
        throw "The deterministic ZIP timestamp must not be later than 2107."
    }

    [uint16]$dosTime = (($fixedTimestamp.Hour -shl 11) -bor
        ($fixedTimestamp.Minute -shl 5) -bor
        [Math]::Floor($fixedTimestamp.Second / 2))
    [uint16]$dosDate = ((($fixedTimestamp.Year - 1980) -shl 9) -bor
        ($fixedTimestamp.Month -shl 5) -bor
        $fixedTimestamp.Day)

    $minimumEocdOffset = [Math]::Max(0, $bytes.Length - 65557)
    $eocdOffset = -1
    for ($offset = $bytes.Length - 22; $offset -ge $minimumEocdOffset; $offset--) {
        if ((Read-UInt32 $offset) -eq 0x06054b50 -and
            $offset + 22 + (Read-UInt16 ($offset + 20)) -eq $bytes.Length) {
            $eocdOffset = $offset
            break
        }
    }
    if ($eocdOffset -lt 0) {
        throw "The ZIP end-of-central-directory record was not found in $Path."
    }

    [uint64]$entryCount = Read-UInt16 ($eocdOffset + 10)
    [uint64]$centralOffset = Read-UInt32 ($eocdOffset + 16)
    if ($entryCount -eq 0xffff -or $centralOffset -eq [uint32]::MaxValue) {
        $locatorOffset = $eocdOffset - 20
        if ($locatorOffset -lt 0 -or (Read-UInt32 $locatorOffset) -ne 0x07064b50) {
            throw "The ZIP64 end-of-central-directory locator was not found in $Path."
        }
        [uint64]$zip64EocdOffset = Read-UInt64 ($locatorOffset + 8)
        if ($zip64EocdOffset -gt [int]::MaxValue -or
            (Read-UInt32 ([int]$zip64EocdOffset)) -ne 0x06064b50) {
            throw "The ZIP64 end-of-central-directory record is invalid in $Path."
        }
        $entryCount = Read-UInt64 ([int]$zip64EocdOffset + 32)
        $centralOffset = Read-UInt64 ([int]$zip64EocdOffset + 48)
    }
    if ($entryCount -gt [int]::MaxValue -or $centralOffset -gt [int]::MaxValue) {
        throw "The MSIX ZIP container is too large to normalize safely."
    }

    $cursor = [int]$centralOffset
    for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
        if ((Read-UInt32 $cursor) -ne 0x02014b50) {
            throw "Invalid ZIP central-directory entry $entryIndex in $Path."
        }

        Write-UInt16 ($cursor + 12) $dosTime
        Write-UInt16 ($cursor + 14) $dosDate

        $fileNameLength = Read-UInt16 ($cursor + 28)
        $extraLength = Read-UInt16 ($cursor + 30)
        $commentLength = Read-UInt16 ($cursor + 32)
        [uint64]$localHeaderOffset = Read-UInt32 ($cursor + 42)
        if ($localHeaderOffset -eq [uint32]::MaxValue) {
            $extraCursor = $cursor + 46 + $fileNameLength
            $extraEnd = $extraCursor + $extraLength
            $zip64ValueCursor = -1
            $zip64DataEnd = -1
            while ($extraCursor + 4 -le $extraEnd) {
                $extraId = Read-UInt16 $extraCursor
                $extraSize = Read-UInt16 ($extraCursor + 2)
                $extraData = $extraCursor + 4
                if ($extraData + $extraSize -gt $extraEnd) {
                    throw "Invalid ZIP extra field for entry $entryIndex in $Path."
                }
                if ($extraId -eq 0x0001) {
                    $zip64ValueCursor = $extraData
                    $zip64DataEnd = $extraData + $extraSize
                    break
                }
                $extraCursor = $extraData + $extraSize
            }
            if ($zip64ValueCursor -lt 0) {
                throw "The ZIP64 local-header offset is missing for entry $entryIndex in $Path."
            }
            if ((Read-UInt32 ($cursor + 24)) -eq [uint32]::MaxValue) {
                $zip64ValueCursor += 8
            }
            if ((Read-UInt32 ($cursor + 20)) -eq [uint32]::MaxValue) {
                $zip64ValueCursor += 8
            }
            if ($zip64ValueCursor + 8 -gt $zip64DataEnd) {
                throw "The ZIP64 local-header offset is truncated for entry $entryIndex in $Path."
            }
            $localHeaderOffset = Read-UInt64 $zip64ValueCursor
        }
        if ($localHeaderOffset -gt [int]::MaxValue) {
            throw "The local-header offset is too large for entry $entryIndex in $Path."
        }
        if ((Read-UInt32 $localHeaderOffset) -ne 0x04034b50) {
            throw "Invalid ZIP local header for entry $entryIndex in $Path."
        }
        Write-UInt16 ($localHeaderOffset + 10) $dosTime
        Write-UInt16 ($localHeaderOffset + 12) $dosDate

        $cursor += 46 + $fileNameLength + $extraLength + $commentLength
    }

    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Invoke-SignFile {
    param([Parameter(Mandatory)] [string]$Path)

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @("sign", "/fd", "SHA256", "/sha1", $script:SigningCertificate.Thumbprint, "/s", "My", "/d", "ClaudeUsage for Windows")) {
        $arguments.Add($argument)
    }
    if (-not [string]::IsNullOrWhiteSpace($TimestampUrl)) {
        foreach ($argument in @("/tr", $TimestampUrl, "/td", "SHA256")) {
            $arguments.Add($argument)
        }
    }
    $arguments.Add($Path)
    Invoke-NativeTool -Tool $script:ResolvedSignTool @arguments
    Invoke-NativeTool -Tool $script:ResolvedSignTool verify /pa /all $Path
}

if ($RequireMsix) {
    $IncludeMsix = $true
}
if ($RequireSignature) {
    $IncludeMsix = $true
    $RequireMsix = $true
}
if (-not [string]::IsNullOrWhiteSpace($AppInstallerUri) -or
    -not [string]::IsNullOrWhiteSpace($PackageUri)) {
    if ([string]::IsNullOrWhiteSpace($AppInstallerUri) -or [string]::IsNullOrWhiteSpace($PackageUri)) {
        throw "AppInstallerUri and PackageUri must be supplied together."
    }
    $parsedDistributionUris = [System.Collections.Generic.List[Uri]]::new()
    foreach ($uriText in @($AppInstallerUri, $PackageUri)) {
        $uri = $null
        if (-not [Uri]::TryCreate($uriText, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne "https") {
            throw "App Installer distribution URIs must be absolute HTTPS URLs: $uriText"
        }
        $parsedDistributionUris.Add($uri)
    }
    if (-not $parsedDistributionUris[0].AbsolutePath.EndsWith('.appinstaller', [StringComparison]::OrdinalIgnoreCase)) {
        throw "AppInstallerUri must end in .appinstaller."
    }
    if (-not $parsedDistributionUris[1].AbsolutePath.EndsWith('.msix', [StringComparison]::OrdinalIgnoreCase)) {
        throw "PackageUri must end in .msix."
    }
    $IncludeMsix = $true
}
if ($PackageName -notmatch '^[A-Za-z0-9.-]{3,50}$' -or $PackageName.EndsWith('.')) {
    throw "PackageName must be a stable 3-50 character MSIX identity using letters, numbers, periods, or dashes."
}
if ([string]::IsNullOrWhiteSpace($Publisher)) {
    throw "Publisher cannot be empty. It must exactly match the signing certificate subject."
}
if ($RequireSignature -and [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    throw "RequireSignature was specified, but CertificateThumbprint is empty."
}
if ($RequireSignature -and [string]::IsNullOrWhiteSpace($TimestampUrl)) {
    throw "A trusted RFC 3161 TimestampUrl is required for a release signature."
}
if ($RequireSignature -and
    ($PackageName -match '(?i)(?:\.Dev|\.CI)$' -or $Publisher -match '(?i)(Development|ClaudeUsage CI)')) {
    throw "A release signature cannot be applied to the development/CI package identity."
}
if (-not (Test-Path -LiteralPath $releaseNotesPath -PathType Leaf)) {
    throw "Release notes were not found: $releaseNotesPath"
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($RequireSignature) {
    if ($null -eq $git) {
        throw "A signed release requires Git so the clean source worktree can be verified."
    }
    $insideWorktreeOutput = @(& $git.Source -C $repoRoot rev-parse --is-inside-work-tree 2>$null)
    $insideWorktreeExitCode = $LASTEXITCODE
    $insideWorktree = if ($insideWorktreeOutput.Count -gt 0) { [string]$insideWorktreeOutput[0] } else { $null }
    if ($insideWorktreeExitCode -ne 0 -or $insideWorktree -cne "true") {
        throw "A signed release requires a readable Git worktree."
    }
    $dirtyPaths = @(& $git.Source -C $repoRoot status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "A signed release requires a readable Git worktree status."
    }
    if ($dirtyPaths.Count -gt 0) {
        throw "A signed release requires a clean Git worktree. Commit or remove all tracked and untracked changes first."
    }
}

Assert-ChildPath -Parent $windowsRoot -Child $artifactRoot
Assert-ChildPath -Parent $artifactRoot -Child $publishDirectory
Assert-ChildPath -Parent $artifactRoot -Child $msixLayoutDirectory
$expectedSdkVersion = (Get-Content -LiteralPath $globalJson -Raw | ConvertFrom-Json).sdk.version
$actualSdkVersionOutput = & $DotNet --version
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the active .NET SDK version."
}
$actualSdkVersion = ($actualSdkVersionOutput | Select-Object -Last 1).Trim()
if ($actualSdkVersion -cne $expectedSdkVersion) {
    throw "Packaging requires the exact .NET SDK from global.json: expected $expectedSdkVersion, found $actualSdkVersion."
}
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
foreach ($directory in @($publishDirectory, $msixLayoutDirectory)) {
    if (Test-Path -LiteralPath $directory) {
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
}
New-Item -ItemType Directory -Force -Path $publishDirectory | Out-Null

if (-not $SkipRestore) {
    Invoke-DotNet restore $solution --runtime $Runtime --configfile $nugetConfig --locked-mode
}
if (-not $SkipTests) {
    Invoke-DotNet test $solution --configuration $Configuration --no-restore --logger "console;verbosity=normal"
}

Invoke-DotNet publish $project `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    --no-restore `
    "-p:PublishSingleFile=false" `
    "-p:ContinuousIntegrationBuild=true" `
    "-m:1" `
    --output $publishDirectory

# Publish the identity-based login helper into the same self-contained runtime
# directory. The shared framework files are identical and are overlaid; only the
# helper's apphost/assembly metadata adds payload size.
Invoke-DotNet publish $startupProject `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    --no-restore `
    "-p:PublishSingleFile=false" `
    "-p:ContinuousIntegrationBuild=true" `
    "-m:1" `
    --output $publishDirectory

$versionOutput = & $DotNet msbuild $project -nologo -getProperty:Version
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the project version."
}
$version = ($versionOutput | Where-Object { $_ -match '^\d' } | Select-Object -Last 1).Trim()
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "The project version is empty."
}
$resolvedPackageVersion = Resolve-PackageVersion -ProjectVersion $version -RequestedVersion $PackageVersion
$resolvedPreviousPublicPackageVersion = $null
$versionMonotonicity = "skipped-no-previous-public-version"
if ([string]::IsNullOrWhiteSpace($PreviousPublicPackageVersion)) {
    Write-Output "Version monotonicity: SKIPPED (PreviousPublicPackageVersion was not supplied)."
}
else {
    if (-not $IncludeMsix) {
        throw "PreviousPublicPackageVersion requires an MSIX/App Installer build. Pass -IncludeMsix or -RequireMsix."
    }
    $resolvedPreviousPublicPackageVersion = Resolve-PackageVersion `
        -ProjectVersion $version `
        -RequestedVersion $PreviousPublicPackageVersion
    if ([Version]$resolvedPackageVersion -le [Version]$resolvedPreviousPublicPackageVersion) {
        throw "MSIX/App Installer version '$resolvedPackageVersion' must be greater than the previous public version '$resolvedPreviousPublicPackageVersion'."
    }
    $versionMonotonicity = "verified-increase"
    Write-Output "Version monotonicity: VERIFIED ($resolvedPreviousPublicPackageVersion -> $resolvedPackageVersion)."
}
$projectXml = [xml](Get-Content -LiteralPath $project -Raw)
$windowsSdkNetVersion = [string]($projectXml.Project.PropertyGroup.WindowsSdkPackageVersion |
    Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($windowsSdkNetVersion)) {
    throw "ClaudeUsage.Windows.csproj must pin WindowsSdkPackageVersion."
}
$artifactBaseName = "ClaudeUsage-Windows-$version-$Runtime"
if (-not [string]::IsNullOrWhiteSpace($AppInstallerUri)) {
    $expectedAppInstallerAssetName = "ClaudeUsage.appinstaller"
    $actualAppInstallerAssetName = Get-UriAssetName -Uri $parsedDistributionUris[0]
    if ($actualAppInstallerAssetName -cne $expectedAppInstallerAssetName) {
        throw "AppInstallerUri asset basename must be '$expectedAppInstallerAssetName', found '$actualAppInstallerAssetName'."
    }

    $expectedPackageAssetName = "$artifactBaseName.msix"
    $actualPackageAssetName = Get-UriAssetName -Uri $parsedDistributionUris[1]
    if ($actualPackageAssetName -cne $expectedPackageAssetName) {
        throw "PackageUri asset basename must match the generated MSIX '$expectedPackageAssetName', found '$actualPackageAssetName'."
    }
}
$staleArtifactNames = @(
    "$artifactBaseName.zip",
    "$artifactBaseName.zip.sha256",
    "$artifactBaseName.msix",
    "$artifactBaseName.msix.sha256",
    "$artifactBaseName.spdx.json",
    "$artifactBaseName.spdx.json.sha256",
    "ClaudeUsage.appinstaller",
    "ClaudeUsage.appinstaller.sha256",
    "SHA256SUMS.txt"
)
foreach ($staleArtifactName in $staleArtifactNames) {
    $staleArtifactPath = Join-Path $artifactRoot $staleArtifactName
    Assert-ChildPath -Parent $artifactRoot -Child $staleArtifactPath
    if (Test-Path -LiteralPath $staleArtifactPath -PathType Leaf) {
        Remove-Item -LiteralPath $staleArtifactPath -Force
    }
}

$commit = $null
if ($null -ne $git) {
    $commitOutput = @(& $git.Source -C $repoRoot rev-parse HEAD 2>$null)
    $commitExitCode = $LASTEXITCODE
    if ($commitExitCode -eq 0 -and $commitOutput.Count -gt 0) {
        $commit = [string]$commitOutput[0]
    }
}
if ([string]::IsNullOrWhiteSpace($commit)) {
    $commit = $env:GITHUB_SHA
}
if ([string]::IsNullOrWhiteSpace($commit)) {
    $commit = "unknown"
}
$commit = $commit.Trim()
if ($RequireSignature -and $commit -ceq "unknown") {
    throw "A signed release requires an attributable source commit."
}
if ($RequireSignature -and $commit -notmatch '^[0-9a-f]{40}(?:[0-9a-f]{24})?$') {
    throw "A signed release requires a full 40- or 64-character Git commit id."
}

$sourceDateEpoch = $env:SOURCE_DATE_EPOCH
if (-not [string]::IsNullOrWhiteSpace($sourceDateEpoch)) {
    [long]$epochSeconds = 0
    if (-not [long]::TryParse($sourceDateEpoch, [ref]$epochSeconds)) {
        throw "SOURCE_DATE_EPOCH must contain Unix epoch seconds."
    }
    $buildTimestamp = [DateTimeOffset]::FromUnixTimeSeconds($epochSeconds)
    $timestampSource = "SOURCE_DATE_EPOCH"
}
else {
    if ($RequireSignature) {
        throw "A signed release requires SOURCE_DATE_EPOCH for traceable build metadata."
    }
    $buildTimestamp = [DateTimeOffset]::UtcNow
    $timestampSource = "current UTC time"
}

Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $publishDirectory "LICENSE.txt") -Force
Copy-Item -LiteralPath $releaseNotesPath -Destination (Join-Path $publishDirectory "RELEASE_NOTES.md") -Force
Copy-Item -LiteralPath (Join-Path $windowsRoot "README.md") -Destination (Join-Path $publishDirectory "README.md") -Force

$dependenciesPath = Join-Path $publishDirectory "ClaudeUsage.Windows.deps.json"
New-ThirdPartyNotices `
    -DependenciesPath $dependenciesPath `
    -PackagesRoot (Join-Path $windowsRoot ".packages") `
    -WindowsSdkNetVersion $windowsSdkNetVersion `
    -DestinationPath (Join-Path $publishDirectory "THIRD-PARTY-NOTICES.txt")

$script:SigningCertificate = $null
$script:ResolvedSignTool = $null
if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    $normalizedThumbprint = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
    $certificatePath = "Cert:\CurrentUser\My\$normalizedThumbprint"
    $script:SigningCertificate = Get-Item -LiteralPath $certificatePath -ErrorAction SilentlyContinue
    if ($null -eq $script:SigningCertificate -or -not $script:SigningCertificate.HasPrivateKey) {
        throw "The signing certificate is not available with a private key in CurrentUser\\My: $normalizedThumbprint"
    }
    if ($script:SigningCertificate.Subject -cne $Publisher) {
        throw "The manifest publisher '$Publisher' does not exactly match the certificate subject '$($script:SigningCertificate.Subject)'."
    }
    $script:ResolvedSignTool = if ([string]::IsNullOrWhiteSpace($SignToolPath)) {
        Find-WindowsSdkTool -Name "signtool.exe"
    }
    else {
        [System.IO.Path]::GetFullPath($SignToolPath)
    }
    if ([string]::IsNullOrWhiteSpace($script:ResolvedSignTool) -or
        -not (Test-Path -LiteralPath $script:ResolvedSignTool -PathType Leaf)) {
        throw "SignTool.exe was not found. Install the Windows SDK or pass -SignToolPath."
    }
}

$buildInfo = [ordered]@{
    product = "ClaudeUsage for Windows"
    version = $version
    msixVersion = $resolvedPackageVersion
    previousPublicMsixVersion = $resolvedPreviousPublicPackageVersion
    versionMonotonicity = $versionMonotonicity
    runtime = $Runtime
    selfContained = $true
    dotnetSdkVersion = $actualSdkVersion
    webView2Runtime = "Evergreen required for Claude login"
    sourceCommit = $commit
    builtAtUtc = $buildTimestamp.ToUniversalTime().ToString("O")
    timestampSource = $timestampSource
    packageIdentity = $PackageName
    publisher = $Publisher
    windowsSdkNetVersion = $windowsSdkNetVersion
    signed = $null -ne $script:SigningCertificate
}
$buildInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $publishDirectory "build-info.json") -Encoding utf8

if ($null -ne $script:SigningCertificate) {
    foreach ($binaryName in @(
        "ClaudeUsage.Windows.exe",
        "ClaudeUsage.Windows.dll",
        "ClaudeUsage.Core.dll",
        "ClaudeUsage.Startup.exe",
        "ClaudeUsage.Startup.dll")) {
        Invoke-SignFile -Path (Join-Path $publishDirectory $binaryName)
    }
}

$sbomInPackage = Join-Path $publishDirectory "SBOM.spdx.json"
& $sbomScript `
    -PublishDirectory $publishDirectory `
    -Version $version `
    -Runtime $Runtime `
    -SourceCommit $commit `
    -WindowsSdkNetVersion $windowsSdkNetVersion `
    -CreatedAtUtc $buildTimestamp `
    -OutputPath $sbomInPackage | Out-Null
# PowerShell scripts do not reset $LASTEXITCODE. Checking it here can report a
# stale failure from an earlier native tool even when SBOM generation succeeded.
if (-not $?) {
    throw "SBOM generation failed."
}

$zipPath = Join-Path $artifactRoot "$artifactBaseName.zip"
$sbomPath = Join-Path $artifactRoot "$artifactBaseName.spdx.json"
Copy-Item -LiteralPath $sbomInPackage -Destination $sbomPath -Force
New-DeterministicZip -SourceDirectory $publishDirectory -DestinationPath $zipPath -Timestamp $buildTimestamp

$createdArtifacts = [System.Collections.Generic.List[string]]::new()
$createdArtifacts.Add($zipPath)
$createdArtifacts.Add($sbomPath)
$msixPath = $null
$appInstallerPath = $null

if ($IncludeMsix) {
    $resolvedMakeAppx = if ([string]::IsNullOrWhiteSpace($MakeAppxPath)) {
        Find-WindowsSdkTool -Name "makeappx.exe"
    }
    else {
        [System.IO.Path]::GetFullPath($MakeAppxPath)
    }

    if ([string]::IsNullOrWhiteSpace($resolvedMakeAppx) -or
        -not (Test-Path -LiteralPath $resolvedMakeAppx -PathType Leaf)) {
        if ($RequireMsix) {
            throw "MakeAppx.exe was not found. Install the Windows SDK or pass -MakeAppxPath."
        }
        Write-Warning "MakeAppx.exe was not found; ZIP/SBOM artifacts were produced without an MSIX."
    }
    else {
        New-Item -ItemType Directory -Force -Path $msixLayoutDirectory | Out-Null
        Copy-Item -Path (Join-Path $publishDirectory "*") -Destination $msixLayoutDirectory -Recurse -Force
        $manifestPath = Join-Path $msixLayoutDirectory "AppxManifest.xml"
        Expand-Template -TemplatePath $manifestTemplate -DestinationPath $manifestPath -Values @{
            PACKAGE_NAME = $PackageName
            PUBLISHER = $Publisher
            PACKAGE_VERSION = $resolvedPackageVersion
            DISPLAY_NAME = "ClaudeUsage"
            PUBLISHER_DISPLAY_NAME = $PublisherDisplayName
            DESCRIPTION = "Claude and Codex usage in the Windows notification area and floating widgets."
        }
        & $assetScript -OutputDirectory (Join-Path $msixLayoutDirectory "Assets") | Out-Null
        if (-not $?) {
            throw "MSIX asset generation failed."
        }

        Get-ChildItem -LiteralPath $msixLayoutDirectory -Recurse -File | ForEach-Object {
            $_.LastWriteTimeUtc = $buildTimestamp.UtcDateTime
        }

        $msixPath = Join-Path $artifactRoot "$artifactBaseName.msix"
        if (Test-Path -LiteralPath $msixPath) {
            Remove-Item -LiteralPath $msixPath -Force
        }
        Invoke-NativeTool -Tool $resolvedMakeAppx pack /o /h SHA256 /d $msixLayoutDirectory /p $msixPath
        Set-ZipContainerTimestamp -Path $msixPath -Timestamp $buildTimestamp
        if ($null -ne $script:SigningCertificate) {
            Invoke-SignFile -Path $msixPath
        }
        elseif ($RequireSignature) {
            throw "The MSIX was created but no release signature was applied."
        }
        $createdArtifacts.Add($msixPath)

        if (-not [string]::IsNullOrWhiteSpace($AppInstallerUri)) {
            $appInstallerPath = Join-Path $artifactRoot "ClaudeUsage.appinstaller"
            Expand-Template -TemplatePath $appInstallerTemplate -DestinationPath $appInstallerPath -Values @{
                PACKAGE_NAME = $PackageName
                PUBLISHER = $Publisher
                PACKAGE_VERSION = $resolvedPackageVersion
                APPINSTALLER_URI = $AppInstallerUri
                PACKAGE_URI = $PackageUri
            }
            $createdArtifacts.Add($appInstallerPath)
        }
    }
}

$checksumManifestPath = Join-Path $artifactRoot "SHA256SUMS.txt"
$checksumLines = [System.Collections.Generic.List[string]]::new()
foreach ($artifact in $createdArtifacts | Sort-Object { [System.IO.Path]::GetFileName($_) }) {
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileName = [System.IO.Path]::GetFileName($artifact)
    $checksumLine = "$hash  $fileName"
    $checksumLines.Add($checksumLine)
    Set-Content -LiteralPath "$artifact.sha256" -Value $checksumLine -Encoding ascii
}
Set-Content -LiteralPath $checksumManifestPath -Value $checksumLines -Encoding ascii

if (Test-Path -LiteralPath $msixLayoutDirectory) {
    Remove-Item -LiteralPath $msixLayoutDirectory -Recurse -Force
}

Write-Output "Version: $version (MSIX $resolvedPackageVersion)"
foreach ($artifact in $createdArtifacts) {
    Write-Output "Artifact: $artifact"
}
Write-Output "Checksums: $checksumManifestPath"
