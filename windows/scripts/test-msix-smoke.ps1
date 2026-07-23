[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$BaseMsixPath,
    [string]$UpgradeMsixPath,
    [string]$TestCertificatePath,
    [string]$PortableExecutablePath,
    [int]$LaunchTimeoutSeconds = 15,
    [switch]$IUnderstandThisInstallsAndRemovesPackages
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $IUnderstandThisInstallsAndRemovesPackages) {
    throw "This existing-user lifecycle smoke changes the current user's installed packages and legacy startup value. Re-run with -IUnderstandThisInstallsAndRemovesPackages only on a dedicated test account. The clean-machine release gate is a separate VM run."
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (Test-IsAdministrator) {
    throw "Run this lifecycle smoke from a standard-user PowerShell session. When TestCertificatePath is supplied, a narrowly scoped UAC broker elevates only the exact LocalMachine\TrustedPeople certificate import and removal."
}

$certificateBrokerReadyTimeoutSeconds = 45
$certificateBrokerCleanupTimeoutSeconds = 45
$certificateBrokerLeaseTimeoutSeconds = 900
$certificateBrokerMaximumEncodedCommandLength = 30000

function Get-RawDataSha256 {
    param([Parameter(Mandatory)] [byte[]]$RawData)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($RawData))).Replace("-", "")
    }
    finally {
        $sha256.Dispose()
    }
}

function New-CertificateLeaseEventSecurity {
    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($null -eq $currentUserSid) {
        throw "The current Windows identity does not expose a user SID."
    }
    $administratorsSid = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,
        $null)
    $systemSid = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::LocalSystemSid,
        $null)
    $brokerRights = [Security.AccessControl.EventWaitHandleRights](
        [Security.AccessControl.EventWaitHandleRights]::Synchronize -bor
        [Security.AccessControl.EventWaitHandleRights]::Modify)

    $eventSecurity = [Security.AccessControl.EventWaitHandleSecurity]::new()
    $eventSecurity.SetOwner($currentUserSid)
    # Do not inherit an ambient default DACL. OTS UAC may run the broker under a
    # different administrator account, so grant only the kernel-event rights
    # needed to open, signal, and wait to explicit principals.
    $eventSecurity.SetAccessRuleProtection($true, $false)
    $eventSecurity.AddAccessRule(
        [Security.AccessControl.EventWaitHandleAccessRule]::new(
            $currentUserSid,
            [Security.AccessControl.EventWaitHandleRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow))
    foreach ($brokerSid in @($administratorsSid, $systemSid)) {
        $eventSecurity.AddAccessRule(
            [Security.AccessControl.EventWaitHandleAccessRule]::new(
                $brokerSid,
                $brokerRights,
                [Security.AccessControl.AccessControlType]::Allow))
    }
    return $eventSecurity
}

function New-CertificateLeaseMutexSecurity {
    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($null -eq $currentUserSid) {
        throw "The current Windows identity does not expose a user SID."
    }
    $administratorsSid = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,
        $null)
    $systemSid = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::LocalSystemSid,
        $null)
    $brokerRights = [Security.AccessControl.MutexRights](
        [Security.AccessControl.MutexRights]::Synchronize -bor
        [Security.AccessControl.MutexRights]::Modify)

    $mutexSecurity = [Security.AccessControl.MutexSecurity]::new()
    $mutexSecurity.SetOwner($currentUserSid)
    $mutexSecurity.SetAccessRuleProtection($true, $false)
    $mutexSecurity.AddAccessRule(
        [Security.AccessControl.MutexAccessRule]::new(
            $currentUserSid,
            [Security.AccessControl.MutexRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow))
    foreach ($brokerSid in @($administratorsSid, $systemSid)) {
        $mutexSecurity.AddAccessRule(
            [Security.AccessControl.MutexAccessRule]::new(
                $brokerSid,
                $brokerRights,
                [Security.AccessControl.AccessControlType]::Allow))
    }
    return $mutexSecurity
}

function New-CertificateBrokerEncodedCommand {
    param(
        [Parameter(Mandatory)] [string]$BrokerSource,
        [Parameter(Mandatory)] [string]$CertificateRawDataBase64,
        [Parameter(Mandatory)] [string]$ExpectedThumbprint,
        [Parameter(Mandatory)] [string]$ExpectedRawDataSha256,
        [Parameter(Mandatory)] [string]$LeaseNonce,
        [Parameter(Mandatory)] [int]$LeaseTimeoutSeconds
    )

    # Every interpolated string is base64, hexadecimal, or a bounded integer.
    # Compressing and embedding the already-read broker source plus CER
    # snapshot in one encoded command removes the UAC-delay file/path TOCTOU
    # window while staying below CreateProcess' command-line limit.
    $brokerSourceBytes = [Text.Encoding]::UTF8.GetBytes($BrokerSource)
    $compressedOutput = [IO.MemoryStream]::new()
    try {
        $compressor = [IO.Compression.DeflateStream]::new(
            $compressedOutput,
            [IO.Compression.CompressionMode]::Compress,
            $true)
        try {
            $compressor.Write($brokerSourceBytes, 0, $brokerSourceBytes.Length)
        }
        finally {
            $compressor.Dispose()
        }
        $compressedBrokerSourceBase64 =
            [Convert]::ToBase64String($compressedOutput.ToArray())
    }
    finally {
        $compressedOutput.Dispose()
    }

    $parameterSource = @(
        '$brokerParameters = @{',
        "    CertificateRawDataBase64 = '$CertificateRawDataBase64'",
        "    ExpectedThumbprint = '$ExpectedThumbprint'",
        "    ExpectedRawDataSha256 = '$ExpectedRawDataSha256'",
        "    LeaseNonce = '$LeaseNonce'",
        "    LeaseTimeoutSeconds = $LeaseTimeoutSeconds",
        '}'
    ) -join "`r`n"
    $bootstrapSource = @(
        "`$compressedBrokerSourceBase64 = '$compressedBrokerSourceBase64'",
        '$compressedBrokerSource = [Convert]::FromBase64String($compressedBrokerSourceBase64)',
        '$compressedInput = [IO.MemoryStream]::new($compressedBrokerSource)',
        '$decompressor = [IO.Compression.DeflateStream]::new($compressedInput, [IO.Compression.CompressionMode]::Decompress)',
        '$sourceReader = [IO.StreamReader]::new($decompressor, [Text.Encoding]::UTF8)',
        'try { $brokerSource = $sourceReader.ReadToEnd() } finally { $sourceReader.Dispose(); $decompressor.Dispose(); $compressedInput.Dispose() }',
        '& ([ScriptBlock]::Create($brokerSource)) @brokerParameters'
    ) -join "`r`n"
    $payload = $parameterSource + "`r`n" + $bootstrapSource
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    if ($encodedCommand.Length -gt $certificateBrokerMaximumEncodedCommandLength) {
        throw "The immutable certificate broker -EncodedCommand is $($encodedCommand.Length) characters, exceeding the safe $certificateBrokerMaximumEncodedCommandLength character command-line budget."
    }
    return $encodedCommand
}

function Start-ElevatedCertificateLease {
    param(
        [Parameter(Mandatory)] [string]$CertificateRawDataBase64,
        [Parameter(Mandatory)] [string]$ExpectedThumbprint,
        [Parameter(Mandatory)] [string]$ExpectedRawDataSha256,
        [Parameter(Mandatory)] [string]$LeaseNonce
    )

    $brokerPath = Join-Path $PSScriptRoot "test-msix-certificate-broker.ps1"
    if (-not (Test-Path -LiteralPath $brokerPath -PathType Leaf)) {
        throw "The narrowly scoped certificate lease broker does not exist: $brokerPath"
    }
    $brokerSource = [IO.File]::ReadAllText($brokerPath, [Text.Encoding]::UTF8)

    $windowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw "Windows PowerShell 5.1 is required for the certificate broker: $windowsPowerShell"
    }

    $encodedCommand = New-CertificateBrokerEncodedCommand `
        -BrokerSource $brokerSource `
        -CertificateRawDataBase64 $CertificateRawDataBase64 `
        -ExpectedThumbprint $ExpectedThumbprint `
        -ExpectedRawDataSha256 $ExpectedRawDataSha256 `
        -LeaseNonce $LeaseNonce `
        -LeaseTimeoutSeconds $certificateBrokerLeaseTimeoutSeconds
    $brokerArguments = @(
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-EncodedCommand",
        $encodedCommand
    )

    try {
        [void](Start-Process `
                -FilePath $windowsPowerShell `
                -ArgumentList $brokerArguments `
                -Verb RunAs `
                -WindowStyle Hidden)
    }
    catch {
        throw [InvalidOperationException]::new(
            "The one-time UAC certificate lease broker was not started. Consent may have been cancelled: $($_.Exception.Message)",
            $_.Exception)
    }
}

function Wait-CertificateLeaseReady {
    param(
        [Parameter(Mandatory)] [Threading.EventWaitHandle]$ReadyEvent,
        [Parameter(Mandatory)] [Threading.EventWaitHandle]$CompleteEvent,
        [Parameter(Mandatory)] [Threading.EventWaitHandle]$FinishedEvent,
        [Parameter(Mandatory)] [Threading.EventWaitHandle]$FailedEvent
    )

    # Do not query the elevated process. With over-the-shoulder UAC it may run
    # as a different administrator, while these explicitly ACLed events remain
    # the narrow cross-account status channel.
    $readyResult = [Threading.WaitHandle]::WaitAny(
        [Threading.WaitHandle[]]@($ReadyEvent, $FinishedEvent),
        $certificateBrokerReadyTimeoutSeconds * 1000)
    if ($readyResult -eq [Threading.WaitHandle]::WaitTimeout) {
        [void]$CompleteEvent.Set()
        $finishedAfterTimeout =
            $FinishedEvent.WaitOne($certificateBrokerCleanupTimeoutSeconds * 1000)
        if ($finishedAfterTimeout -and $FailedEvent.WaitOne(0)) {
            throw "The certificate lease broker failed before readiness."
        }
        if ($finishedAfterTimeout) {
            throw "The certificate lease broker finished without reporting readiness."
        }
        throw "The certificate lease broker did not become ready within $certificateBrokerReadyTimeoutSeconds seconds and did not acknowledge completion within $certificateBrokerCleanupTimeoutSeconds seconds. Verify LocalMachine\\TrustedPeople before continuing; the hard lease begins only after broker readiness."
    }
    if ($readyResult -eq 1 -or $FinishedEvent.WaitOne(0)) {
        if ($FailedEvent.WaitOne(0)) {
            throw "The certificate lease broker failed before readiness."
        }
        throw "The certificate lease broker finished without reporting readiness."
    }
}

function Complete-CertificateLease {
    param(
        [Parameter(Mandatory)] [Threading.EventWaitHandle]$CompleteEvent,
        [Parameter(Mandatory)] [Threading.EventWaitHandle]$FinishedEvent,
        [Parameter(Mandatory)] [Threading.EventWaitHandle]$FailedEvent,
        [Parameter(Mandatory)] [string]$ExpectedThumbprint
    )

    [void]$CompleteEvent.Set()
    if (-not $FinishedEvent.WaitOne($certificateBrokerCleanupTimeoutSeconds * 1000)) {
        throw "Certificate lease broker cleanup exceeded $certificateBrokerCleanupTimeoutSeconds seconds. Verify LocalMachine\\TrustedPeople\\$ExpectedThumbprint before continuing; the readiness-phase hard lease does not bound a cleanup operation already in progress."
    }
    if ($FailedEvent.WaitOne(0)) {
        throw "Certificate lease broker reported an operation or cleanup failure; verify LocalMachine\\TrustedPeople\\$ExpectedThumbprint."
    }
}

function Get-MsixIdentity {
    param([Parameter(Mandatory)] [string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "MSIX does not exist: $fullPath"
    }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($fullPath)
    try {
        $entry = $archive.GetEntry("AppxManifest.xml")
        if ($null -eq $entry) {
            throw "MSIX manifest is missing: $fullPath"
        }
        $stream = $entry.Open()
        try {
            $document = [System.Xml.XmlDocument]::new()
            $document.Load($stream)
        }
        finally {
            $stream.Dispose()
        }
        $namespace = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
        $namespace.AddNamespace("f", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
        $identity = $document.SelectSingleNode("/f:Package/f:Identity", $namespace)
        if ($null -eq $identity) {
            throw "MSIX identity is missing: $fullPath"
        }
        return [pscustomobject]@{
            Path = $fullPath
            Name = $identity.Name
            Publisher = $identity.Publisher
            Version = [Version]$identity.Version
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Wait-ForProcess {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$TimeoutSeconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $process = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $process) {
            return $process
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    return $null
}

function Get-RegistryValueIfPresent {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )

    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $null
    }
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Wait-ForRegistryValueRemoval {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$TimeoutSeconds
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $value = Get-RegistryValueIfPresent -Path $Path -Name $Name
        if ($null -eq $value) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    return $false
}

function Assert-MsixSignature {
    param(
        [Parameter(Mandatory)] [pscustomobject]$Identity,
        [string]$ExpectedSignerThumbprint
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Identity.Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate) {
        throw "MSIX signature validation failed for '$($Identity.Path)': $($signature.Status) $($signature.StatusMessage)"
    }
    if ($signature.SignerCertificate.Subject -cne $Identity.Publisher) {
        throw "MSIX signer '$($signature.SignerCertificate.Subject)' does not match manifest publisher '$($Identity.Publisher)'."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSignerThumbprint) -and
        $signature.SignerCertificate.Thumbprint -cne $ExpectedSignerThumbprint) {
        throw "Base and upgrade MSIX files are not signed by the same certificate."
    }

    return $signature.SignerCertificate.Thumbprint
}

function Stop-TestProcess {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process -or $Process.HasExited) {
        return
    }
    Stop-Process -Id $Process.Id -Force
    Wait-Process -Id $Process.Id -ErrorAction SilentlyContinue
}

function Stop-AllClaudeUsageProcesses {
    $stopFailures = [System.Collections.Generic.List[Exception]]::new()
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $processes = @(Get-Process -Name "ClaudeUsage.Windows" -ErrorAction SilentlyContinue)
        if ($processes.Count -eq 0) {
            return
        }
        foreach ($process in $processes) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Wait-Process -Id $process.Id -ErrorAction SilentlyContinue
            }
            catch {
                [void]$stopFailures.Add($_.Exception)
            }
        }
        Start-Sleep -Milliseconds 200
    }

    $remaining = @(Get-Process -Name "ClaudeUsage.Windows" -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        $ids = ($remaining | ForEach-Object { $_.Id }) -join ", "
        $message = "ClaudeUsage process cleanup left PID(s): $ids."
        if ($stopFailures.Count -gt 0) {
            throw [System.AggregateException]::new($message, $stopFailures)
        }
        throw $message
    }
}

function Remove-TestPackageRegistrations {
    param([Parameter(Mandatory)] [string]$PackageName)

    $removeFailures = [System.Collections.Generic.List[Exception]]::new()
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $packages = @(Get-AppxPackage -Name $PackageName -ErrorAction Stop)
        if ($packages.Count -eq 0) {
            return
        }
        foreach ($package in $packages) {
            try {
                Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
            }
            catch {
                [void]$removeFailures.Add($_.Exception)
            }
        }
        Start-Sleep -Milliseconds 250
    }

    $remaining = @(Get-AppxPackage -Name $PackageName -ErrorAction Stop)
    if ($remaining.Count -gt 0) {
        $fullNames = ($remaining | ForEach-Object { $_.PackageFullName }) -join ", "
        $message = "Package cleanup left registration(s): $fullNames."
        if ($removeFailures.Count -gt 0) {
            throw [System.AggregateException]::new($message, $removeFailures)
        }
        throw $message
    }
}

function Invoke-CleanupStep {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[Exception]]$Failures,
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [scriptblock]$Action
    )

    try {
        & $Action
    }
    catch {
        [void]$Failures.Add(
            [InvalidOperationException]::new(
                "Cleanup/postcondition '$Label' failed: $($_.Exception.Message)",
                $_.Exception))
    }
}

function Assert-ProcessInstallLocation {
    param(
        [Parameter(Mandatory)] [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)] [string]$InstallLocation
    )

    $processPath = $Process.Path
    $expectedRoot = [System.IO.Path]::GetFullPath($InstallLocation).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ([string]::IsNullOrWhiteSpace($processPath) -or
        -not [System.IO.Path]::GetFullPath($processPath).StartsWith(
            $expectedRoot,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "ClaudeUsage launched outside the registered package location: '$processPath'."
    }
}

$baseIdentity = Get-MsixIdentity -Path $BaseMsixPath
$upgradeIdentity = $null
if (-not [string]::IsNullOrWhiteSpace($UpgradeMsixPath)) {
    $upgradeIdentity = Get-MsixIdentity -Path $UpgradeMsixPath
    if ($upgradeIdentity.Name -cne $baseIdentity.Name -or
        $upgradeIdentity.Publisher -cne $baseIdentity.Publisher) {
        throw "Base and upgrade packages do not have the same Name and Publisher identity."
    }
    if ($upgradeIdentity.Version -le $baseIdentity.Version) {
        throw "Upgrade MSIX version must be greater than the base version."
    }
}

$portableExecutable = $null
if (-not [string]::IsNullOrWhiteSpace($PortableExecutablePath)) {
    $portableExecutable = [System.IO.Path]::GetFullPath($PortableExecutablePath)
    if (-not (Test-Path -LiteralPath $portableExecutable -PathType Leaf) -or
        [System.IO.Path]::GetFileName($portableExecutable) -cne "ClaudeUsage.Windows.exe") {
        throw "PortableExecutablePath must identify an existing ClaudeUsage.Windows.exe."
    }
}

$testCertificateFullPath = $null
$testCertificateThumbprint = $null
$testCertificateRawDataBase64 = $null
$testCertificateRawDataSha256 = $null
$testCertificateStorePath = $null
$certificateLeaseNonce = $null
$certificateLeaseReadyEvent = $null
$certificateLeaseCompleteEvent = $null
$certificateLeaseFinishedEvent = $null
$certificateLeaseFailedEvent = $null
$certificateLeaseParentMutex = $null
$certificateLeaseParentMutexOwned = $false
$certificateBrokerStarted = $false
$testCertificateRequested = -not [string]::IsNullOrWhiteSpace($TestCertificatePath)
if ($testCertificateRequested) {
    $testCertificateFullPath = [System.IO.Path]::GetFullPath($TestCertificatePath)
    if (-not (Test-Path -LiteralPath $testCertificateFullPath -PathType Leaf)) {
        throw "Test certificate does not exist: $testCertificateFullPath"
    }
    if (-not [string]::Equals(
            [System.IO.Path]::GetExtension($testCertificateFullPath),
            ".cer",
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "TestCertificatePath must be a public .cer file. Private-key certificate formats are not accepted."
    }
    [byte[]]$certificateRawData = [IO.File]::ReadAllBytes($testCertificateFullPath)
    $certificateInfo = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $certificateRawData)
    try {
        if ($certificateInfo.HasPrivateKey) {
            throw "TestCertificatePath must not contain a private key. Export only the public .cer certificate."
        }
        $testCertificateThumbprint = ($certificateInfo.Thumbprint -replace "\s", "").ToUpperInvariant()
        $testCertificateRawDataBase64 = [Convert]::ToBase64String($certificateRawData)
        if ([Convert]::ToBase64String($certificateInfo.RawData) -cne
            $testCertificateRawDataBase64) {
            throw "The parsed public certificate differs from the CER byte snapshot."
        }
        $testCertificateRawDataSha256 = Get-RawDataSha256 -RawData $certificateRawData
    }
    finally {
        $certificateInfo.Dispose()
    }
    if ($testCertificateThumbprint -notmatch "^[0-9A-F]{40}$") {
        throw "The supplied test certificate did not produce a valid SHA-1 certificate thumbprint."
    }
    $testCertificateStorePath = "Cert:\LocalMachine\TrustedPeople\$testCertificateThumbprint"
    if (Test-Path -LiteralPath $testCertificateStorePath) {
        throw "The supplied test certificate is already trusted. Refusing to remove a pre-existing trust entry."
    }
    $certificateLeaseNonce = [Guid]::NewGuid().ToString("N")
}

$existingPackages = @(Get-AppxPackage -Name $baseIdentity.Name -ErrorAction SilentlyContinue)
if ($existingPackages.Count -gt 0) {
    throw "Package '$($baseIdentity.Name)' is already installed. Use a dedicated test account so the smoke test cannot remove a real installation."
}
$existingProcesses = @(Get-Process -Name "ClaudeUsage.Windows" -ErrorAction SilentlyContinue)
if ($existingProcesses.Count -gt 0) {
    throw "A ClaudeUsage.Windows process is already running. Stop it before using this dedicated lifecycle-test account."
}
$runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runValueName = "ClaudeUsage"
$existingRunValue = Get-RegistryValueIfPresent -Path $runKeyPath -Name $runValueName
if ($null -ne $existingRunValue) {
    throw "A legacy ClaudeUsage Run value already exists. Use a dedicated test account so the smoke test cannot overwrite it."
}

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$stateDirectory = Join-Path $localAppData "ClaudeUsage"
$stateDirectoryExisted = Test-Path -LiteralPath $stateDirectory -PathType Container
$sentinelValue = [Guid]::NewGuid().ToString("D")
$sentinelPath = Join-Path $stateDirectory "packaging-smoke-retention-$sentinelValue.txt"

$providerPaths = @(
    (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) ".claude"),
    (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) ".codex")
)
$providerExistence = @{}
foreach ($providerPath in $providerPaths) {
    $providerExistence[$providerPath] = Test-Path -LiteralPath $providerPath
}

$runSentinel = "packaging-smoke-invalid-versioned-path-$sentinelValue"

$testedPackageFullNames = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$testProcess = $null
$portableProcess = $null
$primaryFailure = $null
$cleanupFailures = [System.Collections.Generic.List[Exception]]::new()
try {
    Write-Output "Running existing-user MSIX lifecycle smoke. Existing ClaudeUsage state is retained; clean-machine release validation remains a separate VM gate."
    if ($testCertificateRequested) {
        $certificateLeaseEventSecurity = New-CertificateLeaseEventSecurity
        $certificateLeaseMutexSecurity = New-CertificateLeaseMutexSecurity
        $readyEventCreated = $false
        $completeEventCreated = $false
        $finishedEventCreated = $false
        $failedEventCreated = $false
        $parentMutexCreated = $false
        $certificateLeaseReadyEvent = [Threading.EventWaitHandle]::new(
            $false,
            [Threading.EventResetMode]::ManualReset,
            "Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Ready",
            [ref]$readyEventCreated,
            $certificateLeaseEventSecurity)
        $certificateLeaseCompleteEvent = [Threading.EventWaitHandle]::new(
            $false,
            [Threading.EventResetMode]::ManualReset,
            "Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Complete",
            [ref]$completeEventCreated,
            $certificateLeaseEventSecurity)
        $certificateLeaseFinishedEvent = [Threading.EventWaitHandle]::new(
            $false,
            [Threading.EventResetMode]::ManualReset,
            "Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Finished",
            [ref]$finishedEventCreated,
            $certificateLeaseEventSecurity)
        $certificateLeaseFailedEvent = [Threading.EventWaitHandle]::new(
            $false,
            [Threading.EventResetMode]::ManualReset,
            "Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Failed",
            [ref]$failedEventCreated,
            $certificateLeaseEventSecurity)
        $certificateLeaseParentMutex = [Threading.Mutex]::new(
            $true,
            "Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Lease",
            [ref]$parentMutexCreated,
            $certificateLeaseMutexSecurity)
        $certificateLeaseParentMutexOwned = $parentMutexCreated
        if (-not $readyEventCreated -or
            -not $completeEventCreated -or
            -not $finishedEventCreated -or
            -not $failedEventCreated -or
            -not $parentMutexCreated) {
            throw "A unique certificate lease kernel-object name already existed."
        }

        Start-ElevatedCertificateLease `
            -CertificateRawDataBase64 $testCertificateRawDataBase64 `
            -ExpectedThumbprint $testCertificateThumbprint `
            -ExpectedRawDataSha256 $testCertificateRawDataSha256 `
            -LeaseNonce $certificateLeaseNonce
        $certificateBrokerStarted = $true
        Wait-CertificateLeaseReady `
            -ReadyEvent $certificateLeaseReadyEvent `
            -CompleteEvent $certificateLeaseCompleteEvent `
            -FinishedEvent $certificateLeaseFinishedEvent `
            -FailedEvent $certificateLeaseFailedEvent
        if (-not (Test-Path -LiteralPath $testCertificateStorePath -PathType Leaf)) {
            throw "The certificate lease broker reported readiness, but the expected TrustedPeople entry is absent."
        }
        $trustedCertificate = Get-Item -LiteralPath $testCertificateStorePath -ErrorAction Stop
        try {
            if ([Convert]::ToBase64String($trustedCertificate.RawData) -cne
                $testCertificateRawDataBase64) {
                throw "The TrustedPeople entry does not contain the exact supplied public certificate."
            }
        }
        finally {
            $trustedCertificate.Dispose()
        }
        Write-Output "Temporarily trusted test certificate $testCertificateThumbprint through one bounded UAC broker lease."
    }

    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
    Set-Content -LiteralPath $sentinelPath -Value $sentinelValue -Encoding ascii
    New-Item -Path $runKeyPath -Force | Out-Null
    New-ItemProperty `
        -LiteralPath $runKeyPath `
        -Name $runValueName `
        -Value $runSentinel `
        -PropertyType String `
        -Force | Out-Null

    $signerThumbprint = Assert-MsixSignature -Identity $baseIdentity
    if ($null -ne $upgradeIdentity) {
        [void](Assert-MsixSignature `
            -Identity $upgradeIdentity `
            -ExpectedSignerThumbprint $signerThumbprint)
    }
    Write-Output "MSIX signature and manifest publisher validation passed."

    Add-AppxPackage -Path $baseIdentity.Path -ForceApplicationShutdown
    $installed = Get-AppxPackage -Name $baseIdentity.Name -ErrorAction Stop
    [void]$testedPackageFullNames.Add($installed.PackageFullName)
    if ([Version]$installed.Version -ne $baseIdentity.Version) {
        throw "Installed version '$($installed.Version)' does not match base MSIX '$($baseIdentity.Version)'."
    }
    Write-Output "Installed $($installed.Name) $($installed.Version)."

    $applicationId = "$($installed.PackageFamilyName)!App"
    if ($null -ne $portableExecutable) {
        $portableProcess = Start-Process `
            -FilePath $portableExecutable `
            -ArgumentList "--background" `
            -WorkingDirectory ([System.IO.Path]::GetDirectoryName($portableExecutable)) `
            -PassThru
        $portableProcess = Wait-ForProcess `
            -Name "ClaudeUsage.Windows" `
            -TimeoutSeconds $LaunchTimeoutSeconds
        if ($null -eq $portableProcess -or
            [System.IO.Path]::GetFullPath($portableProcess.Path) -cne $portableExecutable) {
            throw "The owned portable migration process did not start from '$portableExecutable'."
        }

        # Portable startup synchronization may legitimately touch this value.
        # Recreate the unique legacy registration only after it is fully running,
        # then prove the packaged secondary migrates it before instance handoff.
        New-ItemProperty `
            -LiteralPath $runKeyPath `
            -Name $runValueName `
            -Value $runSentinel `
            -PropertyType String `
            -Force | Out-Null
        Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$applicationId"
        if (-not (Wait-ForRegistryValueRemoval `
            -Path $runKeyPath `
            -Name $runValueName `
            -TimeoutSeconds $LaunchTimeoutSeconds)) {
            throw "Packaged secondary launch did not migrate the legacy Run registration before instance handoff."
        }
        Start-Sleep -Seconds 3
        $claudeUsageProcesses = @(Get-Process -Name "ClaudeUsage.Windows" -ErrorAction SilentlyContinue)
        if ($claudeUsageProcesses.Count -ne 1 -or
            $claudeUsageProcesses[0].Id -ne $portableProcess.Id) {
            throw "ZIP-to-MSIX handoff left an unexpected second ClaudeUsage process."
        }
        Stop-TestProcess -Process $portableProcess
        $portableProcess = $null
        Write-Output "Running ZIP to MSIX startup migration and single-instance handoff passed."
    }

    Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$applicationId"
    $testProcess = Wait-ForProcess -Name "ClaudeUsage.Windows" -TimeoutSeconds $LaunchTimeoutSeconds
    if ($null -eq $testProcess) {
        throw "ClaudeUsage did not launch within $LaunchTimeoutSeconds seconds."
    }
    Assert-ProcessInstallLocation -Process $testProcess -InstallLocation $installed.InstallLocation
    Write-Output "Launch smoke passed from the registered package location (PID $($testProcess.Id))."
    if (-not (Wait-ForRegistryValueRemoval `
        -Path $runKeyPath `
        -Name $runValueName `
        -TimeoutSeconds $LaunchTimeoutSeconds)) {
        throw "Packaged launch did not remove the legacy path-based Run registration."
    }
    Write-Output "Packaged startup registration migration passed."
    Stop-TestProcess -Process $testProcess
    $testProcess = $null

    if ($null -ne $upgradeIdentity) {
        $basePackageFullName = $installed.PackageFullName
        Add-AppxPackage -Path $upgradeIdentity.Path -ForceUpdateFromAnyVersion -ForceApplicationShutdown
        $installed = Get-AppxPackage -Name $baseIdentity.Name -ErrorAction Stop
        [void]$testedPackageFullNames.Add($installed.PackageFullName)
        if ([Version]$installed.Version -ne $upgradeIdentity.Version) {
            throw "Upgrade left version '$($installed.Version)' instead of '$($upgradeIdentity.Version)'."
        }
        if ($installed.PackageFullName -ceq $basePackageFullName) {
            throw "Upgrade did not replace the versioned package registration."
        }

        $applicationId = "$($installed.PackageFamilyName)!App"
        Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$applicationId"
        $testProcess = Wait-ForProcess -Name "ClaudeUsage.Windows" -TimeoutSeconds $LaunchTimeoutSeconds
        if ($null -eq $testProcess) {
            throw "Upgraded ClaudeUsage did not launch within $LaunchTimeoutSeconds seconds."
        }
        Assert-ProcessInstallLocation -Process $testProcess -InstallLocation $installed.InstallLocation
        Stop-TestProcess -Process $testProcess
        $testProcess = $null
        Write-Output "Upgrade and relaunch smoke passed: $($baseIdentity.Version) -> $($upgradeIdentity.Version)."
    }

    Remove-AppxPackage -Package $installed.PackageFullName
    if ($null -ne (Get-AppxPackage -Name $baseIdentity.Name -ErrorAction SilentlyContinue)) {
        throw "Package is still registered after uninstall."
    }
    if (-not (Test-Path -LiteralPath $sentinelPath -PathType Leaf) -or
        (Get-Content -LiteralPath $sentinelPath -Raw).Trim() -cne $sentinelValue) {
        throw "Uninstall removed or changed data under %LOCALAPPDATA%\\ClaudeUsage."
    }
    foreach ($providerPath in $providerPaths) {
        if ($providerExistence[$providerPath] -and -not (Test-Path -LiteralPath $providerPath)) {
            throw "Uninstall removed provider-owned data: $providerPath"
        }
    }
    Write-Output "Uninstall and user/provider data retention smoke passed."
}
catch {
    $primaryFailure = $_
}
finally {
    Invoke-CleanupStep -Failures $cleanupFailures -Label "stop app processes before package removal" -Action {
        Stop-AllClaudeUsageProcesses
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "remove tested package registrations" -Action {
        Remove-TestPackageRegistrations -PackageName $baseIdentity.Name
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "stop late app processes" -Action {
        Stop-AllClaudeUsageProcesses
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "remove legacy Run value" -Action {
        if ($null -ne (Get-RegistryValueIfPresent -Path $runKeyPath -Name $runValueName)) {
            Remove-ItemProperty `
                -LiteralPath $runKeyPath `
                -Name $runValueName `
                -Force `
                -ErrorAction Stop
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "remove lifecycle sentinel" -Action {
        if (Test-Path -LiteralPath $sentinelPath -PathType Leaf) {
            Remove-Item -LiteralPath $sentinelPath -Force -ErrorAction Stop
        }
        # Existing contents are user-owned. Remove the directory only when the
        # test created it and it is still empty; never require user state to be
        # empty and never recursively delete it.
        if (-not $stateDirectoryExisted -and
            (Test-Path -LiteralPath $stateDirectory -PathType Container) -and
            @(Get-ChildItem -LiteralPath $stateDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $stateDirectory -Force -ErrorAction Stop
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "complete ephemeral certificate lease" -Action {
        try {
            if ($testCertificateRequested) {
                $leaseCompletionFailures =
                    [System.Collections.Generic.List[Exception]]::new()
                if ($null -ne $certificateLeaseCompleteEvent) {
                    try {
                        [void]$certificateLeaseCompleteEvent.Set()
                    }
                    catch {
                        [void]$leaseCompletionFailures.Add($_.Exception)
                    }
                }
                if ($certificateLeaseParentMutexOwned) {
                    try {
                        $certificateLeaseParentMutex.ReleaseMutex()
                    }
                    catch {
                        [void]$leaseCompletionFailures.Add($_.Exception)
                    }
                }
                if ($certificateBrokerStarted) {
                    try {
                        Complete-CertificateLease `
                            -CompleteEvent $certificateLeaseCompleteEvent `
                            -FinishedEvent $certificateLeaseFinishedEvent `
                            -FailedEvent $certificateLeaseFailedEvent `
                            -ExpectedThumbprint $testCertificateThumbprint
                    }
                    catch {
                        [void]$leaseCompletionFailures.Add($_.Exception)
                    }
                }
                if ($leaseCompletionFailures.Count -gt 0) {
                    throw [System.AggregateException]::new(
                        "Certificate lease completion reported one or more failures.",
                        $leaseCompletionFailures)
                }
            }
        }
        finally {
            if ($null -ne $certificateLeaseFailedEvent) {
                $certificateLeaseFailedEvent.Dispose()
                $certificateLeaseFailedEvent = $null
            }
            if ($null -ne $certificateLeaseFinishedEvent) {
                $certificateLeaseFinishedEvent.Dispose()
                $certificateLeaseFinishedEvent = $null
            }
            if ($null -ne $certificateLeaseCompleteEvent) {
                $certificateLeaseCompleteEvent.Dispose()
                $certificateLeaseCompleteEvent = $null
            }
            if ($null -ne $certificateLeaseParentMutex) {
                $certificateLeaseParentMutex.Dispose()
                $certificateLeaseParentMutex = $null
            }
            if ($null -ne $certificateLeaseReadyEvent) {
                $certificateLeaseReadyEvent.Dispose()
                $certificateLeaseReadyEvent = $null
            }
        }
    }

    Invoke-CleanupStep -Failures $cleanupFailures -Label "assert no tested packages remain" -Action {
        $remainingPackages = @(Get-AppxPackage -Name $baseIdentity.Name -ErrorAction Stop)
        if ($remainingPackages.Count -gt 0) {
            $remainingNames = ($remainingPackages | ForEach-Object { $_.PackageFullName }) -join ", "
            $trackedNames = if ($testedPackageFullNames.Count -gt 0) {
                ($testedPackageFullNames | Sort-Object) -join ", "
            }
            else {
                "none observed before the failure"
            }
            throw "Remaining package registration(s): $remainingNames. Test observed: $trackedNames."
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "assert no app processes remain" -Action {
        $remainingProcesses = @(Get-Process -Name "ClaudeUsage.Windows" -ErrorAction SilentlyContinue)
        if ($remainingProcesses.Count -gt 0) {
            throw "Remaining ClaudeUsage process PID(s): $(($remainingProcesses.Id) -join ', ')."
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "assert no legacy Run value remains" -Action {
        $remainingRunValue = Get-RegistryValueIfPresent -Path $runKeyPath -Name $runValueName
        if ($null -ne $remainingRunValue) {
            throw "Legacy Run value remains: '$remainingRunValue'."
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "assert no lifecycle sentinel remains" -Action {
        if (Test-Path -LiteralPath $sentinelPath) {
            throw "Lifecycle sentinel remains: $sentinelPath"
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "assert no ephemeral test certificate remains" -Action {
        if ($testCertificateRequested -and
            (Test-Path -LiteralPath $testCertificateStorePath)) {
            throw "Ephemeral test certificate remains in LocalMachine\TrustedPeople: $testCertificateThumbprint"
        }
    }
}

if ($cleanupFailures.Count -gt 0) {
    foreach ($cleanupFailure in $cleanupFailures) {
        Write-Warning $cleanupFailure.Message
    }
    if ($null -ne $primaryFailure) {
        $allFailures = [System.Collections.Generic.List[Exception]]::new()
        [void]$allFailures.Add($primaryFailure.Exception)
        foreach ($cleanupFailure in $cleanupFailures) {
            [void]$allFailures.Add($cleanupFailure)
        }
        $aggregate = [System.AggregateException]::new(
            "Existing-user MSIX lifecycle smoke failed. Primary failure: $($primaryFailure.Exception.Message) Cleanup/postcondition failure(s): $($cleanupFailures.Count).",
            $allFailures)
        $aggregate.Data["PrimaryErrorRecord"] = $primaryFailure.ToString()
        throw $aggregate
    }
    throw [System.AggregateException]::new(
        "Existing-user MSIX lifecycle smoke completed, but cleanup/postcondition failure(s) occurred: $($cleanupFailures.Count).",
        $cleanupFailures)
}

if ($null -ne $primaryFailure) {
    $PSCmdlet.ThrowTerminatingError($primaryFailure)
}

Write-Output "Existing-user MSIX lifecycle smoke and cleanup postconditions passed."
