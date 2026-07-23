[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern("^[A-Za-z0-9+/]+={0,2}$")]
    [string]$CertificateRawDataBase64,
    [Parameter(Mandatory)]
    [ValidatePattern("^[0-9A-Fa-f]{40}$")]
    [string]$ExpectedThumbprint,
    [Parameter(Mandatory)]
    [ValidatePattern("^[0-9A-Fa-f]{64}$")]
    [string]$ExpectedRawDataSha256,
    [Parameter(Mandatory)]
    [ValidatePattern("^[0-9A-Fa-f]{32}$")]
    [string]$LeaseNonce,
    [Parameter(Mandatory)]
    [ValidateRange(60, 3600)]
    [int]$LeaseTimeoutSeconds
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

function Get-StoreMatches {
    param(
        [Parameter(Mandatory)]
        [Security.Cryptography.X509Certificates.X509Store]$Store,
        [Parameter(Mandatory)] [string]$Thumbprint
    )

    return @($Store.Certificates.Find(
            [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $Thumbprint,
            $false))
}

function Dispose-Certificates {
    param([AllowEmptyCollection()] [object[]]$Certificates)

    foreach ($candidate in @($Certificates)) {
        if ($null -ne $candidate) {
            $candidate.Dispose()
        }
    }
}

$certificate = $null
$readyEvent = $null
$completeEvent = $null
$finishedEvent = $null
$failedEvent = $null
$parentLeaseMutex = $null
$parentLeaseMutexAcquired = $false
$thumbprintMutex = $null
$thumbprintMutexAcquired = $false
$cleanupAuthorized = $false
$certificateThumbprint = $null
$certificateSnapshotRawDataBase64 = $null
$operationFailure = $null
$cleanupFailure = $null
$statusSignalFailure = $null

try {
    # Open the explicitly ACLed status channel before validation so every
    # broker-side failure after launch can be reported without querying the
    # elevated process. Failed is opened before Finished so a partial status
    # setup can never expose Finished as a false success.
    $canonicalNonce = $LeaseNonce.ToLowerInvariant()
    $failedEvent = [Threading.EventWaitHandle]::OpenExisting(
        "Local\ClaudeUsage.MsixCert.$canonicalNonce.Failed")
    $finishedEvent = [Threading.EventWaitHandle]::OpenExisting(
        "Local\ClaudeUsage.MsixCert.$canonicalNonce.Finished")
    $readyEvent = [Threading.EventWaitHandle]::OpenExisting(
        "Local\ClaudeUsage.MsixCert.$canonicalNonce.Ready")
    $completeEvent = [Threading.EventWaitHandle]::OpenExisting(
        "Local\ClaudeUsage.MsixCert.$canonicalNonce.Complete")
    $parentLeaseMutex = [Threading.Mutex]::OpenExisting(
        "Local\ClaudeUsage.MsixCert.$canonicalNonce.Lease")

    if (-not (Test-IsAdministrator)) {
        throw "The certificate lease broker must be started through UAC elevation."
    }

    # The standard-user parent snapshots the public CER before requesting UAC
    # and embeds the bytes and this broker source in one immutable
    # -EncodedCommand payload. Decode exactly once and never depend on the
    # original CER path during either import or cleanup.
    [byte[]]$certificateRawData = [Convert]::FromBase64String($CertificateRawDataBase64)
    if ($certificateRawData.Length -eq 0) {
        throw "The certificate snapshot is empty."
    }
    $actualRawDataSha256 = Get-RawDataSha256 -RawData $certificateRawData
    if ($actualRawDataSha256 -cne $ExpectedRawDataSha256.ToUpperInvariant()) {
        throw "The certificate snapshot SHA-256 does not match ExpectedRawDataSha256."
    }

    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $certificateRawData)
    if ($certificate.HasPrivateKey) {
        throw "The certificate lease broker refuses certificates that contain a private key."
    }
    $certificateThumbprint = ($certificate.Thumbprint -replace "\s", "").ToUpperInvariant()
    $certificateSnapshotRawDataBase64 =
        [Convert]::ToBase64String($certificate.RawData)
    if ($certificateThumbprint -cne $ExpectedThumbprint.ToUpperInvariant()) {
        throw "The certificate snapshot thumbprint does not match ExpectedThumbprint."
    }
    if ((Get-RawDataSha256 -RawData $certificate.RawData) -cne $actualRawDataSha256) {
        throw "The parsed certificate raw data differs from the supplied snapshot."
    }

    # The standard-user parent owns this mutex before UAC. Its explicit ACL
    # permits an over-the-shoulder administrator to wait on the same kernel
    # object without granting access to either user's process. If the owner
    # thread/process has already ended, WaitOne acquires an unowned/abandoned
    # mutex and the broker must refuse to import.
    if ($completeEvent.WaitOne(0)) {
        throw "The certificate lease parent ended before broker initialization."
    }
    $parentEndedBeforeInitialization = $false
    try {
        $parentLeaseMutexAcquired = $parentLeaseMutex.WaitOne(0)
        $parentEndedBeforeInitialization = $parentLeaseMutexAcquired
    }
    catch [Threading.AbandonedMutexException] {
        $parentLeaseMutexAcquired = $true
        $parentEndedBeforeInitialization = $true
    }
    if ($parentEndedBeforeInitialization) {
        throw "The certificate lease parent ended before broker initialization."
    }

    # LocalMachine trust is shared across sessions. Serialize this harness by
    # thumbprint so two elevated brokers cannot both pass an absent-then-add
    # check for the same certificate.
    $mutexCreated = $false
    $thumbprintMutex = [Threading.Mutex]::new(
        $false,
        "Global\ClaudeUsage.MsixCert.$certificateThumbprint",
        [ref]$mutexCreated)
    try {
        $thumbprintMutexAcquired = $thumbprintMutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        $thumbprintMutexAcquired = $true
    }
    if (-not $thumbprintMutexAcquired) {
        throw "Another certificate lease broker already owns this thumbprint."
    }

    $store = [Security.Cryptography.X509Certificates.X509Store]::new(
        [Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,
        [Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
    $matches = @()
    try {
        $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $matches = @(Get-StoreMatches -Store $store -Thumbprint $certificateThumbprint)
        if ($matches.Count -gt 0) {
            throw "Refusing to import over a pre-existing trust entry."
        }

        # Authorize exact cleanup before Add so a partially successful store
        # mutation is still reclaimed by the same elevated process.
        $cleanupAuthorized = $true
        $store.Add($certificate)
        Dispose-Certificates -Certificates $matches
        $matches = @(Get-StoreMatches -Store $store -Thumbprint $certificateThumbprint)
        $exactCount = 0
        foreach ($candidate in $matches) {
            if ([Convert]::ToBase64String($candidate.RawData) -cne
                $certificateSnapshotRawDataBase64) {
                throw "The TrustedPeople entry raw data differs after import."
            }
            $exactCount++
        }
        if ($exactCount -eq 0) {
            throw "The exact TrustedPeople entry is absent after import."
        }
    }
    finally {
        Dispose-Certificates -Certificates $matches
        $store.Close()
        $store.Dispose()
    }

    # Signal readiness only after the exact store entry is verified. The same
    # broker then remains elevated as a bounded watchdog until normal parent
    # completion, parent mutex abandonment, or the hard lease deadline.
    [void]$readyEvent.Set()
    try {
        $leaseResult = [Threading.WaitHandle]::WaitAny(
            [Threading.WaitHandle[]]@($completeEvent, $parentLeaseMutex),
            $LeaseTimeoutSeconds * 1000)
        if ($leaseResult -eq [Threading.WaitHandle]::WaitTimeout) {
            throw [TimeoutException]::new(
                "The certificate lease exceeded its hard $LeaseTimeoutSeconds second deadline.")
        }
        if ($leaseResult -eq 1) {
            $parentLeaseMutexAcquired = $true
        }
    }
    catch [Threading.AbandonedMutexException] {
        # WaitAny transfers ownership of an abandoned mutex before throwing.
        # Treat abandonment as parent death and continue directly to cleanup.
        $parentLeaseMutexAcquired = $true
    }
}
catch {
    $operationFailure = $_.Exception
}
finally {
    if ($cleanupAuthorized) {
        try {
            $cleanupStore = [Security.Cryptography.X509Certificates.X509Store]::new(
                [Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,
                [Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
            $cleanupMatches = @()
            try {
                $cleanupStore.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                $cleanupMatches = @(Get-StoreMatches `
                        -Store $cleanupStore `
                        -Thumbprint $certificateThumbprint)
                foreach ($candidate in $cleanupMatches) {
                    if ([Convert]::ToBase64String($candidate.RawData) -cne
                        $certificateSnapshotRawDataBase64) {
                        throw "Refusing to remove a TrustedPeople entry whose raw data differs from the broker snapshot."
                    }
                }
                foreach ($candidate in $cleanupMatches) {
                    $cleanupStore.Remove($candidate)
                }
            }
            finally {
                Dispose-Certificates -Certificates $cleanupMatches
                $cleanupStore.Close()
                $cleanupStore.Dispose()
            }

            $verifyStore = [Security.Cryptography.X509Certificates.X509Store]::new(
                [Security.Cryptography.X509Certificates.StoreName]::TrustedPeople,
                [Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
            $remainingMatches = @()
            try {
                $verifyStore.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
                $remainingMatches = @(Get-StoreMatches `
                        -Store $verifyStore `
                        -Thumbprint $certificateThumbprint)
                if ($remainingMatches.Count -gt 0) {
                    throw "The exact TrustedPeople entry remains after lease cleanup."
                }
            }
            finally {
                Dispose-Certificates -Certificates $remainingMatches
                $verifyStore.Close()
                $verifyStore.Dispose()
            }
        }
        catch {
            $cleanupFailure = $_.Exception
        }
    }

    if ($thumbprintMutexAcquired) {
        try {
            $thumbprintMutex.ReleaseMutex()
        }
        catch {
            if ($null -eq $cleanupFailure) {
                $cleanupFailure = $_.Exception
            }
        }
    }
    if ($null -ne $thumbprintMutex) {
        $thumbprintMutex.Dispose()
    }
    if ($parentLeaseMutexAcquired) {
        try {
            $parentLeaseMutex.ReleaseMutex()
        }
        catch {
            if ($null -eq $cleanupFailure) {
                $cleanupFailure = $_.Exception
            }
        }
    }
    if ($null -ne $parentLeaseMutex) {
        $parentLeaseMutex.Dispose()
    }
    if ($null -ne $certificate) {
        $certificate.Dispose()
    }

    # Failed is set for every operation or exact-cleanup failure. Finished is
    # the final status signal and is emitted only after cleanup and all mutex
    # ownership have been settled. If Failed itself cannot be signaled, omit
    # Finished so the parent times out instead of observing a false success.
    $canSignalFinished = $true
    if ($null -ne $operationFailure -or $null -ne $cleanupFailure) {
        if ($null -eq $failedEvent) {
            $canSignalFinished = $false
        }
        else {
            try {
                [void]$failedEvent.Set()
            }
            catch {
                $statusSignalFailure = $_.Exception
                $canSignalFinished = $false
            }
        }
    }
    if ($canSignalFinished -and $null -ne $finishedEvent) {
        try {
            [void]$finishedEvent.Set()
        }
        catch {
            $statusSignalFailure = $_.Exception
        }
    }

    if ($null -ne $completeEvent) {
        $completeEvent.Dispose()
    }
    if ($null -ne $readyEvent) {
        $readyEvent.Dispose()
    }
    if ($null -ne $failedEvent) {
        $failedEvent.Dispose()
    }
    if ($null -ne $finishedEvent) {
        $finishedEvent.Dispose()
    }
}

if ($null -ne $statusSignalFailure) {
    [Console]::Error.WriteLine(
        "Certificate lease status signaling failed: $($statusSignalFailure.Message)")
    exit 1
}
if ($null -ne $operationFailure -and $null -ne $cleanupFailure) {
    [Console]::Error.WriteLine(
        "Certificate lease failed: $($operationFailure.Message) Exact cleanup also failed: $($cleanupFailure.Message)")
    exit 1
}
if ($null -ne $operationFailure) {
    [Console]::Error.WriteLine($operationFailure.Message)
    exit 1
}
if ($null -ne $cleanupFailure) {
    [Console]::Error.WriteLine("Certificate lease cleanup failed: $($cleanupFailure.Message)")
    exit 1
}

exit 0
