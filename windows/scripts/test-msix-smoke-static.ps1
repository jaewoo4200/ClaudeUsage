[CmdletBinding()]
param(
    [string]$ScriptPath,
    [string]$BrokerScriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptPath = Join-Path $PSScriptRoot "test-msix-smoke.ps1"
}
$fullPath = [System.IO.Path]::GetFullPath($ScriptPath)
if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "MSIX lifecycle smoke script does not exist: $fullPath"
}
if ([string]::IsNullOrWhiteSpace($BrokerScriptPath)) {
    $BrokerScriptPath = Join-Path `
        ([System.IO.Path]::GetDirectoryName($fullPath)) `
        "test-msix-certificate-broker.ps1"
}
$brokerFullPath = [System.IO.Path]::GetFullPath($BrokerScriptPath)
if (-not (Test-Path -LiteralPath $brokerFullPath -PathType Leaf)) {
    throw "MSIX certificate broker script does not exist: $brokerFullPath"
}

$tokens = $null
$parseErrors = $null
$parentAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $fullPath,
    [ref]$tokens,
    [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    $details = ($parseErrors | ForEach-Object { $_.Message }) -join "; "
    throw "MSIX lifecycle smoke script has PowerShell parse errors: $details"
}

$brokerTokens = $null
$brokerParseErrors = $null
$brokerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $brokerFullPath,
    [ref]$brokerTokens,
    [ref]$brokerParseErrors)
if ($brokerParseErrors.Count -gt 0) {
    $details = ($brokerParseErrors | ForEach-Object { $_.Message }) -join "; "
    throw "MSIX certificate broker script has PowerShell parse errors: $details"
}

# PowerShell variable names are case-insensitive. Reject any assignment whose
# left-hand variable collides with a broker script parameter, even if casing
# differs; otherwise a local initialization can erase an immutable payload
# value before validation (for example CertificateRawDataBase64).
$brokerParameterNames = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($brokerParameter in $brokerAst.ParamBlock.Parameters) {
    [void]$brokerParameterNames.Add($brokerParameter.Name.VariablePath.UserPath)
}
$brokerAssignments = @($brokerAst.FindAll(
        {
            param($node)
            return $node -is
                [System.Management.Automation.Language.AssignmentStatementAst]
        },
        $true))
foreach ($brokerAssignment in $brokerAssignments) {
    $assignedVariables = @($brokerAssignment.Left.FindAll(
            {
                param($node)
                return $node -is
                    [System.Management.Automation.Language.VariableExpressionAst]
            },
            $true))
    foreach ($assignedVariable in $assignedVariables) {
        $assignedName = $assignedVariable.VariablePath.UserPath
        if ($brokerParameterNames.Contains($assignedName)) {
            throw "MSIX certificate broker reassigns immutable script parameter '$assignedName'."
        }
    }
}

$source = Get-Content -LiteralPath $fullPath -Raw
$requiredSafetyMarkers = @(
    'IUnderstandThisInstallsAndRemovesPackages',
    '[AllowEmptyCollection()]',
    'Remove-TestPackageRegistrations -PackageName $baseIdentity.Name',
    'assert no tested packages remain',
    'assert no app processes remain',
    'assert no legacy Run value remains',
    'assert no ephemeral test certificate remains',
    'complete ephemeral certificate lease',
    'test-msix-certificate-broker.ps1',
    '-Verb RunAs',
    '-EncodedCommand',
    'Start-ElevatedCertificateLease',
    'Wait-CertificateLeaseReady',
    'Complete-CertificateLease',
    '[Threading.WaitHandle[]]@($ReadyEvent, $FinishedEvent)',
    '$FinishedEvent.WaitOne(',
    '$FailedEvent.WaitOne(0)',
    'New-CertificateLeaseEventSecurity',
    'EventWaitHandleSecurity]::new()',
    'EventWaitHandleAccessRule]::new(',
    'WellKnownSidType]::BuiltinAdministratorsSid',
    'WellKnownSidType]::LocalSystemSid',
    'EventWaitHandleRights]::Synchronize',
    'EventWaitHandleRights]::Modify',
    'New-CertificateLeaseMutexSecurity',
    'MutexSecurity]::new()',
    'MutexAccessRule]::new(',
    'MutexRights]::Synchronize',
    'MutexRights]::Modify',
    'SetAccessRuleProtection($true, $false)',
    '$certificateLeaseEventSecurity)',
    '$certificateLeaseMutexSecurity)',
    'Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Ready',
    'Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Complete',
    'Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Finished',
    'Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Failed',
    'Local\ClaudeUsage.MsixCert.$certificateLeaseNonce.Lease',
    '$certificateLeaseParentMutex.ReleaseMutex()',
    'certificateBrokerReadyTimeoutSeconds',
    'certificateBrokerCleanupTimeoutSeconds',
    'certificateBrokerLeaseTimeoutSeconds',
    'certificateBrokerMaximumEncodedCommandLength',
    'Run this lifecycle smoke from a standard-user PowerShell session',
    'Refusing to remove a pre-existing trust entry',
    'PrimaryErrorRecord',
    'never recursively delete it'
)
foreach ($marker in $requiredSafetyMarkers) {
    if ($source.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "MSIX lifecycle smoke script is missing safety marker: $marker"
    }
}

$forbiddenParentMutations = @(
    'Import-Certificate',
    'Remove-Item -LiteralPath $testCertificateStorePath',
    '-Operation Remove',
    '-Operation Import',
    'ParentProcessId',
    'ParentStartTimeUtcTicks',
    '$BrokerProcess',
    '$certificateBrokerProcess',
    '$certificateLeaseFinishedEvent.Set',
    '$certificateLeaseFailedEvent.Set'
)
foreach ($marker in $forbiddenParentMutations) {
    if ($source.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Standard-user lifecycle parent contains a privileged certificate mutation: $marker"
    }
}

$runAsCount = [regex]::Matches(
    $source,
    [regex]::Escape('-Verb RunAs'),
    [Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
if ($runAsCount -ne 1) {
    throw "The lifecycle parent must contain exactly one UAC RunAs launch; found $runAsCount."
}
$elevationFunctions = @($parentAst.FindAll(
        {
            param($node)
            return $node -is
                [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Start-ElevatedCertificateLease'
        },
        $true))
if ($elevationFunctions.Count -ne 1 -or
    $elevationFunctions[0].Extent.Text.IndexOf(
        '-PassThru',
        [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "The elevated certificate broker launch must not retain a Process object."
}

$brokerSource = Get-Content -LiteralPath $brokerFullPath -Raw
$requiredBrokerMarkers = @(
    '[ValidatePattern("^[0-9A-Fa-f]{40}$")]',
    '[ValidatePattern("^[0-9A-Fa-f]{64}$")]',
    'CertificateRawDataBase64',
    'ExpectedRawDataSha256',
    'LeaseTimeoutSeconds',
    'The certificate lease broker must be started through UAC elevation',
    'Refusing to import over a pre-existing trust entry',
    'StoreName]::TrustedPeople',
    'StoreLocation]::LocalMachine',
    '$store.Add($certificate)',
    '$cleanupStore.Remove($candidate)',
    'certificate.HasPrivateKey',
    'certificateSnapshotRawDataBase64',
    'cleanupAuthorized',
    'Local\ClaudeUsage.MsixCert.$canonicalNonce.Ready',
    'Local\ClaudeUsage.MsixCert.$canonicalNonce.Complete',
    'Local\ClaudeUsage.MsixCert.$canonicalNonce.Finished',
    'Local\ClaudeUsage.MsixCert.$canonicalNonce.Failed',
    'Local\ClaudeUsage.MsixCert.$canonicalNonce.Lease',
    'Global\ClaudeUsage.MsixCert.$certificateThumbprint',
    '[Threading.Mutex]::OpenExisting(',
    '[Threading.WaitHandle]::WaitAny(',
    '[Threading.WaitHandle[]]@($completeEvent, $parentLeaseMutex)',
    'catch [Threading.AbandonedMutexException]',
    '$parentLeaseMutexAcquired = $true',
    '$completeEvent.WaitOne(0)',
    '[void]$failedEvent.Set()',
    '[void]$finishedEvent.Set()',
    '$canSignalFinished',
    'hard $LeaseTimeoutSeconds second deadline',
    'whose raw data differs from the broker snapshot'
)
foreach ($marker in $requiredBrokerMarkers) {
    if ($brokerSource.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "MSIX certificate broker is missing safety marker: $marker"
    }
}
$failedSignalMarker = '[void]$failedEvent.Set()'
$finishedSignalMarker = '[void]$finishedEvent.Set()'
$failedSignalIndex = $brokerSource.IndexOf(
    $failedSignalMarker,
    [StringComparison]::Ordinal)
$finishedSignalIndex = $brokerSource.IndexOf(
    $finishedSignalMarker,
    [StringComparison]::Ordinal)
if ($failedSignalIndex -lt 0 -or
    $finishedSignalIndex -le $failedSignalIndex -or
    $brokerSource.IndexOf(
        '.Set()',
        $finishedSignalIndex + $finishedSignalMarker.Length,
        [StringComparison]::Ordinal) -ge 0) {
    throw "MSIX certificate broker must signal Failed before its final Finished status event."
}

$forbiddenBrokerCapabilities = @(
    'Add-AppxPackage',
    'Remove-AppxPackage',
    'Start-Process',
    'HKCU:',
    'ClaudeUsage.Windows',
    'Cert:\LocalMachine\Root',
    'Remove-Item -Recurse',
    'Set-Content',
    'Out-File',
    'Import-Certificate',
    'CertificatePath',
    '[ValidateSet("Import", "Remove")]',
    'ParentProcessId',
    'ParentStartTimeUtcTicks',
    'GetProcessById',
    '$parentProcess',
    '$parentProcess.HasExited'
)
foreach ($marker in $forbiddenBrokerCapabilities) {
    if ($brokerSource.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "MSIX certificate broker contains an out-of-scope capability: $marker"
    }
}
if ([regex]::IsMatch(
        $brokerSource,
        '\$Operation\b',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    throw "MSIX certificate broker still exposes a split Import/Remove operation parameter."
}

# Reproduce the immutable broker payload with a deliberately larger-than-usual
# 4 KiB public certificate snapshot. This protects the Windows CreateProcess
# command-line budget and verifies that Windows PowerShell 5.1 can parse the
# compressed -EncodedCommand bootstrap without starting an elevated process.
$syntheticCertificateRawDataBase64 =
    [Convert]::ToBase64String((New-Object byte[] 4096))
$brokerSourceBytes = [Text.Encoding]::UTF8.GetBytes($brokerSource)
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

$roundTripInput = [IO.MemoryStream]::new(
    [Convert]::FromBase64String($compressedBrokerSourceBase64))
$roundTripDecompressor = [IO.Compression.DeflateStream]::new(
    $roundTripInput,
    [IO.Compression.CompressionMode]::Decompress)
$roundTripReader = [IO.StreamReader]::new(
    $roundTripDecompressor,
    [Text.Encoding]::UTF8)
try {
    $roundTripBrokerSource = $roundTripReader.ReadToEnd()
}
finally {
    $roundTripReader.Dispose()
    $roundTripDecompressor.Dispose()
    $roundTripInput.Dispose()
}
if ($roundTripBrokerSource -cne $brokerSource) {
    throw "Compressed immutable broker source did not round-trip exactly."
}

$parameterSource = @(
    '$brokerParameters = @{',
    "    CertificateRawDataBase64 = '$syntheticCertificateRawDataBase64'",
    "    ExpectedThumbprint = '$('A' * 40)'",
    "    ExpectedRawDataSha256 = '$('B' * 64)'",
    "    LeaseNonce = '$('c' * 32)'",
    '    LeaseTimeoutSeconds = 900',
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
$encodedPayloadSource = $parameterSource + "`r`n" + $bootstrapSource
$encodedPayload = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($encodedPayloadSource))
if ($encodedPayload.Length -gt 30000) {
    throw "Worst-case static certificate broker payload is $($encodedPayload.Length) encoded characters; the parent budget is 30000."
}
if (($encodedPayload.Length + 256) -ge 32767) {
    throw "Worst-case static certificate broker command line can exceed the Windows CreateProcess limit."
}
$decodedPayload = [Text.Encoding]::Unicode.GetString(
    [Convert]::FromBase64String($encodedPayload))
if ($decodedPayload -cne $encodedPayloadSource) {
    throw "Certificate broker -EncodedCommand did not round-trip exactly."
}
$encodedTokens = $null
$encodedParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput(
    $decodedPayload,
    [ref]$encodedTokens,
    [ref]$encodedParseErrors)
if ($encodedParseErrors.Count -gt 0) {
    $details = ($encodedParseErrors | ForEach-Object { $_.Message }) -join "; "
    throw "Certificate broker -EncodedCommand has PowerShell parse errors: $details"
}

# Exercise the explicit kernel-object ACLs and mutex-abandonment watchdog used
# by the one-UAC lease without touching packages, certificate stores, or user
# state. In particular, the access rules must let an over-the-shoulder
# administrator open only the four lease events and parent lease mutex.
$staticCurrentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
if ($null -eq $staticCurrentUserSid) {
    throw "The static-test Windows identity does not expose a user SID."
}
$staticAdministratorsSid = [Security.Principal.SecurityIdentifier]::new(
    [Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,
    $null)
$staticSystemSid = [Security.Principal.SecurityIdentifier]::new(
    [Security.Principal.WellKnownSidType]::LocalSystemSid,
    $null)
$staticEventBrokerRights = [Security.AccessControl.EventWaitHandleRights](
    [Security.AccessControl.EventWaitHandleRights]::Synchronize -bor
    [Security.AccessControl.EventWaitHandleRights]::Modify)
$staticEventSecurity = [Security.AccessControl.EventWaitHandleSecurity]::new()
$staticEventSecurity.SetOwner($staticCurrentUserSid)
$staticEventSecurity.SetAccessRuleProtection($true, $false)
$staticEventSecurity.AddAccessRule(
    [Security.AccessControl.EventWaitHandleAccessRule]::new(
        $staticCurrentUserSid,
        [Security.AccessControl.EventWaitHandleRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow))
foreach ($staticBrokerSid in @($staticAdministratorsSid, $staticSystemSid)) {
    $staticEventSecurity.AddAccessRule(
        [Security.AccessControl.EventWaitHandleAccessRule]::new(
            $staticBrokerSid,
            $staticEventBrokerRights,
            [Security.AccessControl.AccessControlType]::Allow))
}

$staticNonce = [Guid]::NewGuid().ToString("N")
$staticEventName = "Local\ClaudeUsage.MsixCert.$staticNonce.Static"
$staticEventCreated = $false
$staticEvent = [Threading.EventWaitHandle]::new(
    $false,
    [Threading.EventResetMode]::ManualReset,
    $staticEventName,
    [ref]$staticEventCreated,
    $staticEventSecurity)
$staticFinishedEventCreated = $false
$staticFinishedEvent = [Threading.EventWaitHandle]::new(
    $false,
    [Threading.EventResetMode]::ManualReset,
    "Local\ClaudeUsage.MsixCert.$staticNonce.StaticFinished",
    [ref]$staticFinishedEventCreated,
    $staticEventSecurity)
$staticFailedEventCreated = $false
$staticFailedEvent = [Threading.EventWaitHandle]::new(
    $false,
    [Threading.EventResetMode]::ManualReset,
    "Local\ClaudeUsage.MsixCert.$staticNonce.StaticFailed",
    [ref]$staticFailedEventCreated,
    $staticEventSecurity)
$openedStaticEvent = $null
try {
    if (-not $staticEventCreated -or
        -not $staticFinishedEventCreated -or
        -not $staticFailedEventCreated) {
        throw "A unique static named status event unexpectedly already existed."
    }
    $actualEventSecurity = $staticEvent.GetAccessControl()
    if (-not $actualEventSecurity.AreAccessRulesProtected) {
        throw "Static named event inherited an ambient DACL."
    }
    $actualEventRules = @($actualEventSecurity.GetAccessRules(
            $true,
            $false,
            [Security.Principal.SecurityIdentifier]))
    $expectedEventRules = @(
        [pscustomobject]@{
            Sid = $staticCurrentUserSid
            Rights = [Security.AccessControl.EventWaitHandleRights]::FullControl
        },
        [pscustomobject]@{
            Sid = $staticAdministratorsSid
            Rights = $staticEventBrokerRights
        },
        [pscustomobject]@{
            Sid = $staticSystemSid
            Rights = $staticEventBrokerRights
        })
    if ($actualEventRules.Count -ne $expectedEventRules.Count) {
        throw "Static named event has an unexpected explicit access-rule count."
    }
    foreach ($expectedRule in $expectedEventRules) {
        $matchingRules = @($actualEventRules | Where-Object {
                $_.IdentityReference.Value -eq $expectedRule.Sid.Value
            })
        if ($matchingRules.Count -ne 1 -or
            $matchingRules[0].AccessControlType -ne
                [Security.AccessControl.AccessControlType]::Allow -or
            $matchingRules[0].IsInherited -or
            $matchingRules[0].EventWaitHandleRights -ne $expectedRule.Rights) {
            throw "Static named event ACL does not contain the exact expected rule for $($expectedRule.Sid.Value)."
        }
    }

    $openedStaticEvent = [Threading.EventWaitHandle]::OpenExisting($staticEventName)
    [void]$staticEvent.Set()
    if (-not $openedStaticEvent.WaitOne(0)) {
        throw "Named event did not signal across independent handles."
    }
    [void]$staticEvent.Reset()
    [void]$staticFailedEvent.Set()
    [void]$staticFinishedEvent.Set()
    $staticStatusResult = [Threading.WaitHandle]::WaitAny(
        [Threading.WaitHandle[]]@($staticEvent, $staticFinishedEvent),
        0)
    if ($staticStatusResult -ne 1 -or -not $staticFailedEvent.WaitOne(0)) {
        throw "Finished/Failed status events did not preserve broker outcome ordering."
    }
}
finally {
    if ($null -ne $openedStaticEvent) {
        $openedStaticEvent.Dispose()
    }
    $staticFailedEvent.Dispose()
    $staticFinishedEvent.Dispose()
    $staticEvent.Dispose()
}

$staticMutexBrokerRights = [Security.AccessControl.MutexRights](
    [Security.AccessControl.MutexRights]::Synchronize -bor
    [Security.AccessControl.MutexRights]::Modify)
$staticMutexSecurity = [Security.AccessControl.MutexSecurity]::new()
$staticMutexSecurity.SetOwner($staticCurrentUserSid)
$staticMutexSecurity.SetAccessRuleProtection($true, $false)
$staticMutexSecurity.AddAccessRule(
    [Security.AccessControl.MutexAccessRule]::new(
        $staticCurrentUserSid,
        [Security.AccessControl.MutexRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow))
foreach ($staticBrokerSid in @($staticAdministratorsSid, $staticSystemSid)) {
    $staticMutexSecurity.AddAccessRule(
        [Security.AccessControl.MutexAccessRule]::new(
            $staticBrokerSid,
            $staticMutexBrokerRights,
            [Security.AccessControl.AccessControlType]::Allow))
}

$staticMutexName = "Local\ClaudeUsage.MsixCert.$staticNonce.StaticMutex"
$staticMutexCreated = $false
$staticMutex = [Threading.Mutex]::new(
    $true,
    $staticMutexName,
    [ref]$staticMutexCreated,
    $staticMutexSecurity)
$staticMutexOwned = $staticMutexCreated
$openedStaticMutex = $null
try {
    if (-not $staticMutexCreated) {
        throw "Unique static named mutex unexpectedly already existed."
    }
    $actualMutexSecurity = $staticMutex.GetAccessControl()
    if (-not $actualMutexSecurity.AreAccessRulesProtected) {
        throw "Static named mutex inherited an ambient DACL."
    }
    $actualMutexRules = @($actualMutexSecurity.GetAccessRules(
            $true,
            $false,
            [Security.Principal.SecurityIdentifier]))
    $expectedMutexRules = @(
        [pscustomobject]@{
            Sid = $staticCurrentUserSid
            Rights = [Security.AccessControl.MutexRights]::FullControl
        },
        [pscustomobject]@{
            Sid = $staticAdministratorsSid
            Rights = $staticMutexBrokerRights
        },
        [pscustomobject]@{
            Sid = $staticSystemSid
            Rights = $staticMutexBrokerRights
        })
    if ($actualMutexRules.Count -ne $expectedMutexRules.Count) {
        throw "Static named mutex has an unexpected explicit access-rule count."
    }
    foreach ($expectedRule in $expectedMutexRules) {
        $matchingRules = @($actualMutexRules | Where-Object {
                $_.IdentityReference.Value -eq $expectedRule.Sid.Value
            })
        if ($matchingRules.Count -ne 1 -or
            $matchingRules[0].AccessControlType -ne
                [Security.AccessControl.AccessControlType]::Allow -or
            $matchingRules[0].IsInherited -or
            $matchingRules[0].MutexRights -ne $expectedRule.Rights) {
            throw "Static named mutex ACL does not contain the exact expected rule for $($expectedRule.Sid.Value)."
        }
    }
    $openedStaticMutex = [Threading.Mutex]::OpenExisting($staticMutexName)
}
finally {
    if ($null -ne $openedStaticMutex) {
        $openedStaticMutex.Dispose()
    }
    if ($staticMutexOwned) {
        $staticMutex.ReleaseMutex()
    }
    $staticMutex.Dispose()
}

# A helper thread acquires a separate named mutex and exits without releasing
# it. WaitAny must surface AbandonedMutexException at index 1 and transfer
# ownership, matching the elevated broker's parent-death path.
if ($null -eq ('ClaudeUsageMsixSmokeStaticMutexAbandoner' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Threading;

public static class ClaudeUsageMsixSmokeStaticMutexAbandoner
{
    public static Exception Failure { get; private set; }

    public static Thread Start(string mutexName)
    {
        Failure = null;
        Thread thread = new Thread(delegate()
        {
            Mutex mutex = null;
            try
            {
                mutex = Mutex.OpenExisting(mutexName);
                mutex.WaitOne();
            }
            catch (Exception exception)
            {
                Failure = exception;
            }
            finally
            {
                if (mutex != null)
                {
                    mutex.Dispose();
                }
            }
        });
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }
}
'@
}

$staticAbandonedMutexName =
    "Local\ClaudeUsage.MsixCert.$staticNonce.StaticAbandonedMutex"
$staticAbandonedMutexCreated = $false
$staticAbandonedMutex = [Threading.Mutex]::new(
    $false,
    $staticAbandonedMutexName,
    [ref]$staticAbandonedMutexCreated,
    $staticMutexSecurity)
$staticAbandonWaitEvent = [Threading.ManualResetEvent]::new($false)
$staticAbandonedMutexAcquired = $false
try {
    if (-not $staticAbandonedMutexCreated) {
        throw "Unique static abandonment mutex unexpectedly already existed."
    }
    $abandoningThread =
        [ClaudeUsageMsixSmokeStaticMutexAbandoner]::Start(
            $staticAbandonedMutexName)
    if (-not $abandoningThread.Join(5000)) {
        throw "Static abandonment helper thread did not terminate."
    }
    if ($null -ne [ClaudeUsageMsixSmokeStaticMutexAbandoner]::Failure) {
        throw [InvalidOperationException]::new(
            "Static abandonment helper failed.",
            [ClaudeUsageMsixSmokeStaticMutexAbandoner]::Failure)
    }

    $abandonmentObserved = $false
    try {
        [void][Threading.WaitHandle]::WaitAny(
            [Threading.WaitHandle[]]@(
                $staticAbandonWaitEvent,
                $staticAbandonedMutex),
            1000)
    }
    catch [Threading.AbandonedMutexException] {
        if ($_.Exception.MutexIndex -ne 1) {
            throw "Static WaitAny reported abandonment at an unexpected index."
        }
        $staticAbandonedMutexAcquired = $true
        $abandonmentObserved = $true
    }
    if (-not $abandonmentObserved) {
        throw "Static WaitAny did not surface abandoned parent mutex ownership."
    }
}
finally {
    if ($staticAbandonedMutexAcquired) {
        $staticAbandonedMutex.ReleaseMutex()
    }
    $staticAbandonWaitEvent.Dispose()
    $staticAbandonedMutex.Dispose()
}

# Windows PowerShell 5.1 rejects a mandatory empty collection unless the
# parameter explicitly permits it. The real cleanup accumulator is empty on
# the normal success path, so exercise that binder shape without mutating the
# machine or dot-sourcing the lifecycle script.
function Test-EmptyCleanupAccumulatorBinding {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[Exception]]$Failures
    )

    return $Failures.Count
}

$emptyCleanupFailures = [System.Collections.Generic.List[Exception]]::new()
if ((Test-EmptyCleanupAccumulatorBinding -Failures $emptyCleanupFailures) -ne 0) {
    throw 'Empty cleanup accumulator binding returned an unexpected count.'
}

# Exercise the generic collection and AggregateException constructor shapes
# used by the cleanup path so Windows PowerShell 5.1 fails here, without any
# external mutation, if a runtime overload is incompatible.
$constructorFailures = [System.Collections.Generic.List[Exception]]::new()
[void]$constructorFailures.Add([InvalidOperationException]::new('static test'))
$constructorAggregate = [System.AggregateException]::new(
    'static aggregate test',
    $constructorFailures)
if ($constructorAggregate.InnerExceptions.Count -ne 1) {
    throw "AggregateException constructor static check failed."
}
$constructorSet = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
[void]$constructorSet.Add('ClaudeUsage')
if (-not $constructorSet.Contains('claudeusage')) {
    throw "HashSet comparer constructor static check failed."
}

# This invocation intentionally omits the destructive acknowledgement. The
# guard is the first executable check in the target script, so no package,
# process, registry, certificate, or user-state mutation can occur.
$guardFailure = $null
try {
    & $fullPath -BaseMsixPath (Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid()).msix")
}
catch {
    $guardFailure = $_
}
if ($null -eq $guardFailure -or
    $guardFailure.Exception.Message.IndexOf(
        'existing-user lifecycle smoke changes',
        [StringComparison]::Ordinal) -lt 0) {
    throw "Destructive acknowledgement guard did not fail before artifact inspection."
}

Write-Output "MSIX lifecycle parent and one-UAC certificate lease watchdog passed Windows PowerShell 5.1 static safety checks; no mutation was authorized."
