[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LedgerPath,
    [Parameter(Mandatory)]
    [string]$PreviousPublicPackageVersion,
    [Parameter(Mandatory)]
    [string]$CandidatePackageVersion,
    [Parameter(Mandatory)]
    [string]$CandidateReleaseTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$windowsReleaseTagPattern = '^windows-v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'

if ($CandidateReleaseTag -notmatch $windowsReleaseTagPattern) {
    throw "CandidateReleaseTag must use the windows-v<semver> form: '$CandidateReleaseTag'."
}

function ConvertTo-LedgerVersion {
    param(
        [Parameter(Mandatory)] [string]$Value,
        [Parameter(Mandatory)] [string]$Description
    )

    if ($Value -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "$Description must contain four numeric parts: '$Value'."
    }

    $numericParts = [System.Collections.Generic.List[uint32]]::new()
    foreach ($part in $Value.Split('.')) {
        [uint32]$numericPart = 0
        if (-not [uint32]::TryParse($part, [ref]$numericPart) -or $numericPart -gt 65535) {
            throw "Every part of $Description must be between 0 and 65535: '$Value'."
        }
        $numericParts.Add($numericPart)
    }

    $canonicalValue = $numericParts -join '.'
    if ($Value -cne $canonicalValue) {
        throw "$Description must use canonical numeric parts without leading zeroes: '$Value'."
    }

    return [pscustomobject]@{
        Text = $canonicalValue
        Value = [Version]$canonicalValue
    }
}

if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) {
    throw "Public MSIX version ledger was not found: $LedgerPath"
}

try {
    $ledger = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
}
catch {
    throw "Public MSIX version ledger is not valid JSON: $($_.Exception.Message)"
}

if ($null -eq $ledger -or $ledger.PSObject.Properties.Name -notcontains 'schemaVersion' -or
    [int]$ledger.schemaVersion -ne 1) {
    throw "Public MSIX version ledger must use schemaVersion 1."
}
if ($ledger.PSObject.Properties.Name -notcontains 'latestPublicPackageVersion' -or
    $ledger.latestPublicPackageVersion -isnot [string]) {
    throw "Public MSIX version ledger must define latestPublicPackageVersion as a string."
}
if ($ledger.PSObject.Properties.Name -notcontains 'releases') {
    throw "Public MSIX version ledger must define a releases array."
}

$latest = ConvertTo-LedgerVersion `
    -Value $ledger.latestPublicPackageVersion `
    -Description "latestPublicPackageVersion"
$releaseEntries = @($ledger.releases)
$lastRecordedVersion = $null
$seenTags = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$seenVersions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

for ($index = 0; $index -lt $releaseEntries.Count; $index++) {
    $entry = $releaseEntries[$index]
    if ($null -eq $entry) {
        throw "Public MSIX version ledger release entry $index is null."
    }
    foreach ($propertyName in @('releaseTag', 'packageVersion', 'publishedAtUtc')) {
        if ($entry.PSObject.Properties.Name -notcontains $propertyName -or
            $entry.$propertyName -isnot [string] -or
            [string]::IsNullOrWhiteSpace($entry.$propertyName)) {
            throw "Public MSIX version ledger release entry $index must define non-empty '$propertyName'."
        }
    }
    if ($entry.releaseTag -notmatch $windowsReleaseTagPattern) {
        throw "Public MSIX version ledger release entry $index has an invalid Windows release tag: '$($entry.releaseTag)'."
    }
    if (-not $seenTags.Add($entry.releaseTag)) {
        throw "Public MSIX version ledger contains duplicate release tag '$($entry.releaseTag)'."
    }

    $entryVersion = ConvertTo-LedgerVersion `
        -Value $entry.packageVersion `
        -Description "release entry $index packageVersion"
    if (-not $seenVersions.Add($entryVersion.Text)) {
        throw "Public MSIX version ledger contains duplicate package version '$($entryVersion.Text)'."
    }
    if ($null -ne $lastRecordedVersion -and $entryVersion.Value -le $lastRecordedVersion.Value) {
        throw "Public MSIX package versions must increase in ledger order."
    }

    [DateTimeOffset]$publishedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
        $entry.publishedAtUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$publishedAt) -or $publishedAt.Offset -ne [TimeSpan]::Zero) {
        throw "Public MSIX version ledger release entry $index must use a UTC publishedAtUtc timestamp."
    }

    $lastRecordedVersion = $entryVersion
}

if ($releaseEntries.Count -eq 0) {
    if ($latest.Text -cne '0.0.0.0') {
        throw "An empty public MSIX release ledger must use latestPublicPackageVersion 0.0.0.0."
    }
}
elseif ($latest.Text -cne $lastRecordedVersion.Text) {
    throw "latestPublicPackageVersion '$($latest.Text)' does not match the last ledger entry '$($lastRecordedVersion.Text)'."
}

$previous = ConvertTo-LedgerVersion `
    -Value $PreviousPublicPackageVersion `
    -Description "previous_public_package_version"
if ($previous.Text -cne $latest.Text) {
    throw "previous_public_package_version '$($previous.Text)' does not match the checked-in public MSIX ledger '$($latest.Text)'."
}

$candidate = ConvertTo-LedgerVersion `
    -Value $CandidatePackageVersion `
    -Description "candidate package version"
if ($candidate.Value -le $latest.Value) {
    throw "Candidate MSIX version '$($candidate.Text)' must be greater than the public ledger version '$($latest.Text)'."
}
if ($seenTags.Contains($CandidateReleaseTag)) {
    throw "Candidate release tag '$CandidateReleaseTag' is already recorded as public."
}

Write-Output "Public MSIX ledger: VERIFIED ($($latest.Text) -> $($candidate.Text), $CandidateReleaseTag)."
