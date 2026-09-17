[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$PublishDirectory,
    [Parameter(Mandatory)] [string]$Version,
    [Parameter(Mandatory)] [string]$Runtime,
    [Parameter(Mandatory)] [string]$SourceCommit,
    [Parameter(Mandatory)] [string]$WindowsSdkNetVersion,
    [Parameter(Mandatory)] [DateTimeOffset]$CreatedAtUtc,
    [Parameter(Mandatory)] [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$publishPath = [System.IO.Path]::GetFullPath($PublishDirectory)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $publishPath -PathType Container)) {
    throw "Publish directory does not exist: $publishPath"
}

function Get-StringSha1 {
    param([Parameter(Mandatory)] [string]$Value)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha1.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha1.Dispose()
    }
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

$fileRecords = [System.Collections.Generic.List[object]]::new()
$sha1Values = [System.Collections.Generic.List[string]]::new()
$files = Get-ChildItem -LiteralPath $publishPath -Recurse -File |
    Where-Object { [System.IO.Path]::GetFullPath($_.FullName) -ne $outputFullPath } |
    Sort-Object { Get-RelativePath -BaseDirectory $publishPath -Path $_.FullName }

$fileIndex = 0
foreach ($file in $files) {
    $fileIndex++
    $relativePath = (Get-RelativePath -BaseDirectory $publishPath -Path $file.FullName).Replace('\', '/')
    $sha1 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA1).Hash.ToLowerInvariant()
    $sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $sha1Values.Add($sha1)
    $fileRecords.Add([ordered]@{
        fileName = "./$relativePath"
        SPDXID = "SPDXRef-File-$fileIndex"
        checksums = @(
            [ordered]@{ algorithm = "SHA1"; checksumValue = $sha1 },
            [ordered]@{ algorithm = "SHA256"; checksumValue = $sha256 }
        )
        licenseConcluded = "NOASSERTION"
        licenseInfoInFiles = @("NOASSERTION")
        copyrightText = "NOASSERTION"
    })
}

$verificationInput = ($sha1Values | Sort-Object) -join ''
$verificationCode = Get-StringSha1 -Value $verificationInput
$rootPackageId = "SPDXRef-Package-ClaudeUsage-Windows"
$packages = [System.Collections.Generic.List[object]]::new()
$packages.Add([ordered]@{
    name = "ClaudeUsage for Windows"
    SPDXID = $rootPackageId
    versionInfo = $Version
    packageFileName = "ClaudeUsage-Windows-$Version-$Runtime.zip"
    downloadLocation = "NOASSERTION"
    filesAnalyzed = $true
    packageVerificationCode = [ordered]@{ packageVerificationCodeValue = $verificationCode }
    licenseConcluded = "MIT"
    licenseDeclared = "MIT"
    copyrightText = "Copyright (c) 2026 Jaewoo Lee"
    supplier = "Person: Jaewoo Lee"
    externalRefs = @(
        [ordered]@{
            referenceCategory = "OTHER"
            referenceType = "vcs"
            referenceLocator = "git+https://github.com/jaewoo4200/ClaudeUsage.git@$SourceCommit"
        }
    )
})

$depsPath = Join-Path $publishPath "ClaudeUsage.Windows.deps.json"
$dependencyRecords = [System.Collections.Generic.List[object]]::new()
$dependencyRecords.Add([pscustomobject]@{
    Name = "Microsoft.Windows.SDK.NET.Ref"
    Version = $WindowsSdkNetVersion
    License = "NOASSERTION"
})
if (Test-Path -LiteralPath $depsPath) {
    $deps = Get-Content -LiteralPath $depsPath -Raw | ConvertFrom-Json
    foreach ($library in $deps.libraries.PSObject.Properties | Sort-Object Name) {
        $parts = $library.Name.Split('/', 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $name = $parts[0]
        $dependencyVersion = $parts[1]
        if ($name -eq "Microsoft.Web.WebView2") {
            $dependencyRecords.Add([pscustomobject]@{
                Name = $name
                Version = $dependencyVersion
                License = "BSD-3-Clause"
            })
        }
        elseif ($name.StartsWith("runtimepack.Microsoft.NETCore.App.Runtime.", [StringComparison]::Ordinal) -or
                $name.StartsWith("runtimepack.Microsoft.WindowsDesktop.App.Runtime.", [StringComparison]::Ordinal)) {
            $dependencyRecords.Add([pscustomobject]@{
                Name = $name.Substring("runtimepack.".Length)
                Version = $dependencyVersion
                License = "MIT"
            })
        }
    }
}

$relationships = [System.Collections.Generic.List[object]]::new()
$relationships.Add([ordered]@{
    spdxElementId = "SPDXRef-DOCUMENT"
    relationshipType = "DESCRIBES"
    relatedSpdxElement = $rootPackageId
})

$dependencyIndex = 0
foreach ($dependency in $dependencyRecords | Sort-Object Name -Unique) {
    $dependencyIndex++
    $dependencyId = "SPDXRef-Package-Dependency-$dependencyIndex"
    $packages.Add([ordered]@{
        name = $dependency.Name
        SPDXID = $dependencyId
        versionInfo = $dependency.Version
        downloadLocation = "https://www.nuget.org/packages/$($dependency.Name)/$($dependency.Version)"
        filesAnalyzed = $false
        licenseConcluded = $dependency.License
        licenseDeclared = $dependency.License
        copyrightText = "NOASSERTION"
        supplier = "Organization: Microsoft Corporation"
        externalRefs = @(
            [ordered]@{
                referenceCategory = "PACKAGE-MANAGER"
                referenceType = "purl"
                referenceLocator = "pkg:nuget/$($dependency.Name)@$($dependency.Version)"
            }
        )
    })
    $relationships.Add([ordered]@{
        spdxElementId = $rootPackageId
        relationshipType = "DEPENDS_ON"
        relatedSpdxElement = $dependencyId
    })
}

for ($index = 1; $index -le $fileRecords.Count; $index++) {
    $relationships.Add([ordered]@{
        spdxElementId = $rootPackageId
        relationshipType = "CONTAINS"
        relatedSpdxElement = "SPDXRef-File-$index"
    })
}

$namespaceVersion = [Uri]::EscapeDataString($Version)
$namespaceCommit = [Uri]::EscapeDataString($SourceCommit)
$document = [ordered]@{
    spdxVersion = "SPDX-2.3"
    dataLicense = "CC0-1.0"
    SPDXID = "SPDXRef-DOCUMENT"
    name = "ClaudeUsage-Windows-$Version-$Runtime"
    documentNamespace = "https://github.com/jaewoo4200/ClaudeUsage/sbom/windows/$namespaceVersion/$namespaceCommit/$Runtime"
    creationInfo = [ordered]@{
        created = $CreatedAtUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        creators = @(
            "Tool: ClaudeUsage packaging scripts",
            "Organization: ClaudeUsage"
        )
        licenseListVersion = "3.25"
    }
    documentDescribes = @($rootPackageId)
    packages = @($packages)
    files = @($fileRecords)
    relationships = @($relationships)
}

$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$document | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputFullPath -Encoding utf8
Write-Output $outputFullPath
