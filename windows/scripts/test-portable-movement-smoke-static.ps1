[CmdletBinding()]
param(
    [string]$ScriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptPath = Join-Path $PSScriptRoot "test-portable-movement-smoke.ps1"
}
$fullPath = [System.IO.Path]::GetFullPath($ScriptPath)
if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Portable movement smoke script does not exist: $fullPath"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $fullPath,
    [ref]$tokens,
    [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    $details = ($parseErrors | ForEach-Object { $_.Message }) -join "; "
    throw "Portable movement smoke has PowerShell parse errors: $details"
}

$source = Get-Content -LiteralPath $fullPath -Raw
$requiredMarkers = @(
    '[CmdletBinding(DefaultParameterSetName = "Zip")]',
    '[Parameter(Mandatory, ParameterSetName = "Zip")]',
    '[Parameter(Mandatory, ParameterSetName = "Executable")]',
    'Run the portable movement smoke from a standard-user PowerShell session',
    'Assert-SafeSessionRoot',
    'Assert-SafeZipEntries',
    'ClaudeUsage-portable-movement-',
    'UseShellExecute = $false',
    'EnvironmentVariables["APPDATA"]',
    'EnvironmentVariables["LOCALAPPDATA"]',
    'EnvironmentVariables["TEMP"]',
    'GetProcessImagePath',
    'QueryFullProcessImageName',
    'GetWindowThreadProcessId',
    'SendInput',
    'ReleaseLeftButton',
    'RestoreCursor',
    'RestoreForeground',
    '--screenshot-settings',
    '--screenshot-history',
    '--screenshot-widget',
    'Claude + Codex Usage',
    'Usage history',
    'ClaudeUsage Widget',
    'actualDeltaX',
    'Test-InsideWorkArea',
    'Assert-FileStateUnchanged',
    'Stop-ExactTestProcess',
    'Remove-Item -LiteralPath $sessionRoot -Recurse',
    'Temporary movement session remains',
    '[AllowEmptyCollection()]'
)
foreach ($marker in $requiredMarkers) {
    if ($source.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Portable movement smoke is missing safety marker: $marker"
    }
}

$forbiddenCapabilities = @(
    'Add-AppxPackage',
    'Remove-AppxPackage',
    'Get-AppxPackage',
    'Import-Certificate',
    'Cert:\',
    '-Verb RunAs',
    'HKCU:',
    'HKLM:',
    'RegistryKey',
    'New-ItemProperty',
    'Remove-ItemProperty',
    'Set-ItemProperty',
    'reg.exe',
    'Invoke-WebRequest',
    'Invoke-RestMethod',
    'Start-BitsTransfer',
    'Start-Process',
    'Remove-Item -LiteralPath $ExecutablePath',
    'Remove-Item -LiteralPath $ZipPath'
)
foreach ($marker in $forbiddenCapabilities) {
    if ($source.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Portable movement smoke contains a forbidden capability: $marker"
    }
}

$recursiveDeleteMatches = [regex]::Matches(
    $source,
    'Remove-Item\s+-LiteralPath\s+\$sessionRoot\s+-Recurse',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if ($recursiveDeleteMatches.Count -ne 1) {
    throw "Portable movement smoke must contain exactly one bounded recursive delete."
}

$commandAsts = @($ast.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.CommandAst] },
        $true))
$nativeMutationCommands = @(
    "Add-AppxPackage",
    "Remove-AppxPackage",
    "Import-Certificate",
    "New-ItemProperty",
    "Remove-ItemProperty",
    "Set-ItemProperty"
)
foreach ($commandAst in $commandAsts) {
    $commandName = $commandAst.GetCommandName()
    if ($null -ne $commandName -and $nativeMutationCommands -contains $commandName) {
        throw "Portable movement smoke AST contains forbidden command: $commandName"
    }
}

# Exercise the empty cleanup binder and collection constructors used by the
# target without launching an app, sending input, or changing the filesystem.
function Test-EmptyFailureBinding {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[Exception]]$Failures
    )
    return $Failures.Count
}

$emptyFailures = [System.Collections.Generic.List[Exception]]::new()
if ((Test-EmptyFailureBinding -Failures $emptyFailures) -ne 0) {
    throw "Empty cleanup collection binding failed."
}
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
if ($processes.Count -ne 0) {
    throw "Empty process ownership collection construction failed."
}

Write-Output "Portable movement smoke passed Windows PowerShell 5.1 static safety checks; no app, input, package, certificate, registry, or filesystem mutation was authorized."
