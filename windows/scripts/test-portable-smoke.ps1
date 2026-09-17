[CmdletBinding(DefaultParameterSetName = "Executable")]
param(
    [Parameter(Mandatory, ParameterSetName = "Executable")] [string]$ExecutablePath,
    [Parameter(Mandatory, ParameterSetName = "Zip")] [string]$ZipPath,
    [ValidateRange(5, 120)] [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-SafeExtractionRoot {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$TempRoot
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $fullTempRoot = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    $name = [System.IO.Path]::GetFileName($fullPath)
    if (-not $parent.Equals($fullTempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not $name.StartsWith("ClaudeUsage-portable-smoke-", [StringComparison]::Ordinal)) {
        throw "Refusing to use unsafe portable smoke extraction path '$fullPath'."
    }
}

function Assert-SafeZipEntries {
    param(
        [Parameter(Mandatory)] [string]$ArchivePath,
        [Parameter(Mandatory)] [string]$DestinationRoot
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $rootPrefix = [System.IO.Path]::GetFullPath($DestinationRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $relativePath = $entry.FullName.Replace(
                [System.IO.Path]::AltDirectorySeparatorChar,
                [System.IO.Path]::DirectorySeparatorChar)
            if ([System.IO.Path]::IsPathRooted($relativePath)) {
                throw "Portable ZIP contains a rooted entry '$($entry.FullName)'."
            }

            $destination = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Combine($DestinationRoot, $relativePath))
            if (-not $destination.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Portable ZIP entry '$($entry.FullName)' escapes the extraction directory."
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

$resultPath = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    "ClaudeUsage-runtime-smoke-$([Guid]::NewGuid().ToString('N')).txt"
$process = $null
$extractionRoot = $null
try {
    if ($PSCmdlet.ParameterSetName -ceq "Zip") {
        $archivePath = [System.IO.Path]::GetFullPath($ZipPath)
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
            -not [System.IO.Path]::GetExtension($archivePath).Equals(
                ".zip",
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "ZipPath must identify an existing .zip file."
        }

        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $extractionRoot = Join-Path `
            $tempRoot `
            "ClaudeUsage-portable-smoke-$([Guid]::NewGuid().ToString('N'))"
        Assert-SafeExtractionRoot -Path $extractionRoot -TempRoot $tempRoot
        [System.IO.Directory]::CreateDirectory($extractionRoot) | Out-Null
        Assert-SafeZipEntries -ArchivePath $archivePath -DestinationRoot $extractionRoot
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractionRoot

        $executable = Join-Path $extractionRoot "ClaudeUsage.Windows.exe"
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "Portable ZIP must contain ClaudeUsage.Windows.exe at its root."
        }
    }
    else {
        $executable = [System.IO.Path]::GetFullPath($ExecutablePath)
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf) -or
            [System.IO.Path]::GetFileName($executable) -cne "ClaudeUsage.Windows.exe") {
            throw "ExecutablePath must identify an existing ClaudeUsage.Windows.exe."
        }
    }

    $arguments = @(
        "--runtime-smoke",
        "`"--runtime-smoke-result=$resultPath`"",
        "--theme=Daangn",
        "--appearance=Light",
        "--language=English",
        "--layout=Horizontal"
    )
    $process = Start-Process `
        -FilePath $executable `
        -ArgumentList $arguments `
        -WorkingDirectory ([System.IO.Path]::GetDirectoryName($executable)) `
        -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw "Portable runtime smoke timed out after $TimeoutSeconds seconds."
    }

    $process.Refresh()
    $result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        (Get-Content -LiteralPath $resultPath -Raw).Trim()
    }
    else {
        "No diagnostic result file was produced."
    }
    if ($process.ExitCode -ne 0) {
        throw "Portable runtime smoke exited with code $($process.ExitCode): $result"
    }
    if (-not $result.StartsWith("PASS:", [StringComparison]::Ordinal)) {
        throw "Portable runtime smoke did not report success: $result"
    }

    Write-Output $result
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $process.Id -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $extractionRoot) {
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        Assert-SafeExtractionRoot -Path $extractionRoot -TempRoot $tempRoot
        if (Test-Path -LiteralPath $extractionRoot) {
            Remove-Item -LiteralPath $extractionRoot -Recurse -Force
        }
    }
}
