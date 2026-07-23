[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$DestinationRoot,
    [string]$Version = "10.0.26100.6901",
    [string]$ExpectedSha256 = "40109fe95b6ccd449327edfbf91a8eef4838e6982e66a6a90a1d6d9eb7d98747"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Windows SDK BuildTools version must contain four numeric parts."
}
if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw "ExpectedSha256 must be a 64-character SHA-256 value."
}

$root = [System.IO.Path]::GetFullPath($DestinationRoot)
New-Item -ItemType Directory -Force -Path $root | Out-Null
$packageId = "microsoft.windows.sdk.buildtools"
$packageFile = Join-Path $root "$packageId.$Version.nupkg"
$extractDirectory = Join-Path $root "$packageId.$Version"
$uri = "https://api.nuget.org/v3-flatcontainer/$packageId/$Version/$packageId.$Version.nupkg"

Invoke-WebRequest -Uri $uri -OutFile $packageFile -UseBasicParsing
$actualHash = (Get-FileHash -LiteralPath $packageFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -cne $ExpectedSha256.ToLowerInvariant()) {
    throw "Windows SDK BuildTools package hash mismatch: $actualHash"
}

if (Test-Path -LiteralPath $extractDirectory) {
    Remove-Item -LiteralPath $extractDirectory -Recurse -Force
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($packageFile, $extractDirectory)

$makeAppx = @(Get-ChildItem -LiteralPath $extractDirectory -Recurse -File -Filter makeappx.exe |
    Where-Object { $_.FullName -match '[\\/]x64[\\/]makeappx\.exe$' })
$signTool = @(Get-ChildItem -LiteralPath $extractDirectory -Recurse -File -Filter signtool.exe |
    Where-Object { $_.FullName -match '[\\/]x64[\\/]signtool\.exe$' })
if ($makeAppx.Count -ne 1 -or $signTool.Count -ne 1) {
    throw "Expected one x64 MakeAppx.exe and SignTool.exe in the pinned SDK package."
}

foreach ($tool in @($makeAppx[0], $signTool[0])) {
    $signature = Get-AuthenticodeSignature -LiteralPath $tool.FullName
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "Pinned SDK tool does not have a valid Microsoft signature: $($tool.FullName)"
    }
}

[pscustomobject]@{
    MakeAppxPath = $makeAppx[0].FullName
    SignToolPath = $signTool[0].FullName
    Version = $Version
    PackageSha256 = $actualHash
}
