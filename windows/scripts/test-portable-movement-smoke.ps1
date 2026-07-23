[CmdletBinding(DefaultParameterSetName = "Zip")]
param(
    [Parameter(Mandatory, ParameterSetName = "Zip")]
    [string]$ZipPath,
    [Parameter(Mandatory, ParameterSetName = "Executable")]
    [string]$ExecutablePath,
    [ValidateRange(5, 60)]
    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (Test-IsAdministrator) {
    throw "Run the portable movement smoke from a standard-user PowerShell session."
}

function Assert-SafeSessionRoot {
    param([Parameter(Mandatory)] [string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not [string]::Equals(
            [System.IO.Path]::GetDirectoryName($fullPath),
            $tempRoot,
            [StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.Path]::GetFileName($fullPath).StartsWith(
            "ClaudeUsage-portable-movement-",
            [StringComparison]::Ordinal)) {
        throw "Refusing to use an unsafe portable movement session root: $fullPath"
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

$nativeSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace ClaudeUsageMovementSmoke
{
    [StructLayout(LayoutKind.Sequential)]
    public struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MonitorInfo
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect Work;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Input
    {
        public uint Type;
        public InputUnion Union;
    }

    public static class NativeMethods
    {
        private const uint InputMouse = 0;
        private const uint MouseMove = 0x0001;
        private const uint LeftDown = 0x0002;
        private const uint LeftUp = 0x0004;
        private const uint Absolute = 0x8000;
        private const uint VirtualDesk = 0x4000;
        private const int VirtualLeft = 76;
        private const int VirtualTop = 77;
        private const int VirtualWidth = 78;
        private const int VirtualHeight = 79;
        private const uint MonitorDefaultToNearest = 2;
        private const uint ProcessQueryLimitedInformation = 0x1000;

        private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindow(IntPtr window);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr window, out NativeRect rectangle);
        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo information);
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool BringWindowToTop(IntPtr window);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindowAsync(IntPtr window, int command);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetCursorPos(out NativePoint point);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, Input[] inputs, int size);
        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool PostMessage(IntPtr window, uint message, IntPtr word, IntPtr data);
        [DllImport("user32.dll")]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool QueryFullProcessImageName(
            IntPtr process,
            uint flags,
            StringBuilder executableName,
            ref int size);
        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        public static void TryEnablePerMonitorDpiAwareness()
        {
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
            catch (EntryPointNotFoundException) { }
        }

        public static IntPtr[] EnumerateProcessWindows(int processId)
        {
            var matches = new List<IntPtr>();
            EnumWindows(delegate(IntPtr window, IntPtr ignored)
            {
                uint owner;
                GetWindowThreadProcessId(window, out owner);
                if (owner == (uint)processId) matches.Add(window);
                return true;
            }, IntPtr.Zero);
            return matches.ToArray();
        }

        public static int GetProcessId(IntPtr window)
        {
            uint processId;
            GetWindowThreadProcessId(window, out processId);
            return unchecked((int)processId);
        }

        public static string GetProcessImagePath(int processId)
        {
            var process = OpenProcess(ProcessQueryLimitedInformation, false, processId);
            if (process == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try
            {
                var path = new StringBuilder(32768);
                var size = path.Capacity;
                if (!QueryFullProcessImageName(process, 0, path, ref size))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return path.ToString();
            }
            finally
            {
                CloseHandle(process);
            }
        }

        public static string GetTitle(IntPtr window)
        {
            var text = new StringBuilder(1024);
            GetWindowText(window, text, text.Capacity);
            return text.ToString();
        }

        public static NativeRect GetBounds(IntPtr window)
        {
            NativeRect rectangle;
            if (!GetWindowRect(window, out rectangle)) throw new Win32Exception();
            return rectangle;
        }

        public static NativeRect GetWorkArea(IntPtr window)
        {
            var monitor = MonitorFromWindow(window, MonitorDefaultToNearest);
            var information = new MonitorInfo();
            information.Size = Marshal.SizeOf(typeof(MonitorInfo));
            if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref information))
                throw new Win32Exception();
            return information.Work;
        }

        public static NativePoint GetCursorPosition()
        {
            NativePoint point;
            if (!GetCursorPos(out point)) throw new Win32Exception();
            return point;
        }

        public static bool RestoreCursor(NativePoint point)
        {
            if (!SetCursorPos(point.X, point.Y)) return false;
            var current = GetCursorPosition();
            return current.X == point.X && current.Y == point.Y;
        }

        public static bool Activate(IntPtr window)
        {
            ShowWindowAsync(window, 9);
            BringWindowToTop(window);
            for (var attempt = 0; attempt < 20; attempt++)
            {
                SetForegroundWindow(window);
                if (GetForegroundWindow() == window) return true;
                Thread.Sleep(50);
            }
            return false;
        }

        public static bool RestoreForeground(IntPtr window)
        {
            if (window == IntPtr.Zero || !IsWindow(window)) return true;
            for (var attempt = 0; attempt < 20; attempt++)
            {
                SetForegroundWindow(window);
                if (GetForegroundWindow() == window) return true;
                Thread.Sleep(50);
            }
            return false;
        }

        private static void SendMouse(uint flags, int screenX, int screenY)
        {
            var input = new Input();
            input.Type = InputMouse;
            input.Union.Mouse.Flags = flags;
            if ((flags & MouseMove) != 0)
            {
                var left = GetSystemMetrics(VirtualLeft);
                var top = GetSystemMetrics(VirtualTop);
                var width = Math.Max(1, GetSystemMetrics(VirtualWidth) - 1);
                var height = Math.Max(1, GetSystemMetrics(VirtualHeight) - 1);
                var x = Math.Max(left, Math.Min(left + width, screenX));
                var y = Math.Max(top, Math.Min(top + height, screenY));
                input.Union.Mouse.X = (int)Math.Round((x - left) * 65535.0 / width);
                input.Union.Mouse.Y = (int)Math.Round((y - top) * 65535.0 / height);
            }
            if (SendInput(1, new[] { input }, Marshal.SizeOf(typeof(Input))) != 1)
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        public static void ReleaseLeftButton()
        {
            try { SendMouse(LeftUp, 0, 0); }
            catch (Win32Exception) { }
        }

        public static void Drag(int fromX, int fromY, int toX, int toY)
        {
            SendMouse(MouseMove | Absolute | VirtualDesk, fromX, fromY);
            Thread.Sleep(100);
            SendMouse(LeftDown, 0, 0);
            try
            {
                Thread.Sleep(100);
                const int steps = 18;
                for (var step = 1; step <= steps; step++)
                {
                    var x = fromX + ((toX - fromX) * step / steps);
                    var y = fromY + ((toY - fromY) * step / steps);
                    SendMouse(MouseMove | Absolute | VirtualDesk, x, y);
                    Thread.Sleep(16);
                }
            }
            finally
            {
                SendMouse(LeftUp, 0, 0);
                Thread.Sleep(150);
            }
        }

        public static void RequestClose(IntPtr window)
        {
            if (window != IntPtr.Zero && IsWindow(window)) PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
'@

Add-Type -TypeDefinition $nativeSource -Language CSharp
[ClaudeUsageMovementSmoke.NativeMethods]::TryEnablePerMonitorDpiAwareness()

function Get-FileState {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Length = $null; Hash = $null; LastWriteUtc = $null }
    }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{
        Exists = $true
        Length = $item.Length
        Hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        LastWriteUtc = $item.LastWriteTimeUtc.ToString("O")
    }
}

function Assert-FileStateUnchanged {
    param(
        [Parameter(Mandatory)] [pscustomobject]$Before,
        [Parameter(Mandatory)] [pscustomobject]$After,
        [Parameter(Mandatory)] [string]$Path
    )
    if ($Before.Exists -ne $After.Exists -or
        $Before.Length -ne $After.Length -or
        $Before.Hash -cne $After.Hash -or
        $Before.LastWriteUtc -cne $After.LastWriteUtc) {
        throw "User settings changed during portable movement smoke: $Path"
    }
}

function Assert-ExactTestProcess {
    param(
        [Parameter(Mandatory)] [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)] [string]$ExpectedExecutable
    )
    $Process.Refresh()
    if ($Process.HasExited) {
        throw "Portable movement test process $($Process.Id) exited unexpectedly with code $($Process.ExitCode)."
    }
    $actualPath = [System.IO.Path]::GetFullPath(
        [ClaudeUsageMovementSmoke.NativeMethods]::GetProcessImagePath($Process.Id))
    if (-not $actualPath.Equals(
            [System.IO.Path]::GetFullPath($ExpectedExecutable),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "PID $($Process.Id) does not belong to the exact test executable: $actualPath"
    }
}

function Assert-ExactWindow {
    param(
        [Parameter(Mandatory)] [IntPtr]$Handle,
        [Parameter(Mandatory)] [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)] [string]$ExpectedExecutable,
        [Parameter(Mandatory)] [string]$ExpectedTitle
    )
    Assert-ExactTestProcess -Process $Process -ExpectedExecutable $ExpectedExecutable
    if (-not [ClaudeUsageMovementSmoke.NativeMethods]::IsWindow($Handle) -or
        -not [ClaudeUsageMovementSmoke.NativeMethods]::IsWindowVisible($Handle) -or
        [ClaudeUsageMovementSmoke.NativeMethods]::GetProcessId($Handle) -ne $Process.Id -or
        [ClaudeUsageMovementSmoke.NativeMethods]::GetTitle($Handle) -cne $ExpectedTitle) {
        throw "HWND is no longer pinned to PID $($Process.Id) and exact title '$ExpectedTitle'."
    }
}

function Wait-ForExactWindow {
    param(
        [Parameter(Mandatory)] [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)] [string]$ExpectedExecutable,
        [Parameter(Mandatory)] [string]$ExpectedTitle,
        [Parameter(Mandatory)] [int]$TimeoutSeconds
    )
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Assert-ExactTestProcess -Process $Process -ExpectedExecutable $ExpectedExecutable
        $matches = @([ClaudeUsageMovementSmoke.NativeMethods]::EnumerateProcessWindows($Process.Id) |
            Where-Object {
                [ClaudeUsageMovementSmoke.NativeMethods]::IsWindowVisible($_) -and
                [ClaudeUsageMovementSmoke.NativeMethods]::GetTitle($_) -ceq $ExpectedTitle
            })
        if ($matches.Count -gt 1) {
            throw "PID $($Process.Id) exposed more than one exact '$ExpectedTitle' HWND."
        }
        if ($matches.Count -eq 1) {
            Assert-ExactWindow -Handle $matches[0] -Process $Process -ExpectedExecutable $ExpectedExecutable -ExpectedTitle $ExpectedTitle
            return [IntPtr]$matches[0]
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "Timed out waiting for exact '$ExpectedTitle' HWND from PID $($Process.Id)."
}

function Start-VisualTestProcess {
    param(
        [Parameter(Mandatory)] [string]$Executable,
        [Parameter(Mandatory)] [string]$WorkingDirectory,
        [Parameter(Mandatory)] [string]$Mode,
        [Parameter(Mandatory)] [string]$AppData,
        [Parameter(Mandatory)] [string]$LocalAppData,
        [Parameter(Mandatory)] [string]$TempPath
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.Arguments = "$Mode --theme=Daangn --appearance=Light --language=English --layout=Horizontal"
    $startInfo.EnvironmentVariables["APPDATA"] = $AppData
    $startInfo.EnvironmentVariables["LOCALAPPDATA"] = $LocalAppData
    $startInfo.EnvironmentVariables["TEMP"] = $TempPath
    $startInfo.EnvironmentVariables["TMP"] = $TempPath
    return [System.Diagnostics.Process]::Start($startInfo)
}

function Stop-ExactTestProcess {
    param(
        [Parameter(Mandatory)] [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)] [string]$ExpectedExecutable,
        [IntPtr]$WindowHandle = [IntPtr]::Zero
    )
    $Process.Refresh()
    if ($Process.HasExited) { return }
    Assert-ExactTestProcess -Process $Process -ExpectedExecutable $ExpectedExecutable
    [ClaudeUsageMovementSmoke.NativeMethods]::RequestClose($WindowHandle)
    if (-not $Process.WaitForExit(1200)) {
        Assert-ExactTestProcess -Process $Process -ExpectedExecutable $ExpectedExecutable
        $Process.Kill()
        if (-not $Process.WaitForExit(5000)) {
            throw "Exact test PID $($Process.Id) did not exit."
        }
    }
}

function Get-DragDelta {
    param(
        [Parameter(Mandatory)]$Bounds,
        [Parameter(Mandatory)]$WorkArea,
        [int]$Margin = 12
    )
    foreach ($candidate in @(
            [pscustomobject]@{ X = 180; Y = 100 },
            [pscustomobject]@{ X = -180; Y = 100 },
            [pscustomobject]@{ X = 180; Y = -100 },
            [pscustomobject]@{ X = -180; Y = -100 })) {
        if ($Bounds.Left + $candidate.X -ge $WorkArea.Left + $Margin -and
            $Bounds.Top + $candidate.Y -ge $WorkArea.Top + $Margin -and
            $Bounds.Right + $candidate.X -le $WorkArea.Right - $Margin -and
            $Bounds.Bottom + $candidate.Y -le $WorkArea.Bottom - $Margin) {
            return $candidate
        }
    }
    throw "No safe in-work-area drag delta is available for this window."
}

function Test-InsideWorkArea {
    param(
        [Parameter(Mandatory)]$Bounds,
        [Parameter(Mandatory)]$WorkArea,
        [int]$Margin = 8
    )
    return $Bounds.Left -ge $WorkArea.Left + $Margin -and
        $Bounds.Top -ge $WorkArea.Top + $Margin -and
        $Bounds.Right -le $WorkArea.Right - $Margin -and
        $Bounds.Bottom -le $WorkArea.Bottom - $Margin
}

function Format-Bounds {
    param([Parameter(Mandatory)]$Bounds)
    return "($($Bounds.Left),$($Bounds.Top),$($Bounds.Right - $Bounds.Left)x$($Bounds.Bottom - $Bounds.Top))"
}

function Invoke-MovementScenario {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Mode,
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [bool]$Widget,
        [Parameter(Mandatory)] [string]$Executable,
        [Parameter(Mandatory)] [string]$WorkingDirectory,
        [Parameter(Mandatory)] [string]$AppData,
        [Parameter(Mandatory)] [string]$LocalAppData,
        [Parameter(Mandatory)] [string]$TempPath,
        [Parameter(Mandatory)] [int]$TimeoutSeconds,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Diagnostics.Process]]$OwnedProcesses
    )
    $process = Start-VisualTestProcess -Executable $Executable -WorkingDirectory $WorkingDirectory -Mode $Mode -AppData $AppData -LocalAppData $LocalAppData -TempPath $TempPath
    [void]$OwnedProcesses.Add($process)
    $handle = [IntPtr]::Zero
    try {
        $handle = Wait-ForExactWindow -Process $process -ExpectedExecutable $Executable -ExpectedTitle $Title -TimeoutSeconds $TimeoutSeconds
        $before = [ClaudeUsageMovementSmoke.NativeMethods]::GetBounds($handle)
        $workArea = [ClaudeUsageMovementSmoke.NativeMethods]::GetWorkArea($handle)
        $delta = Get-DragDelta -Bounds $before -WorkArea $workArea
        $width = $before.Right - $before.Left
        $height = $before.Bottom - $before.Top
        $fromX = $before.Left + [int]($width / 2)
        $fromY = $before.Top + $(if ($Widget) { 18 } else { 15 })

        Assert-ExactWindow -Handle $handle -Process $process -ExpectedExecutable $Executable -ExpectedTitle $Title
        if (-not [ClaudeUsageMovementSmoke.NativeMethods]::Activate($handle)) {
            throw "Could not make exact '$Title' HWND foreground before SendInput."
        }
        Assert-ExactWindow -Handle $handle -Process $process -ExpectedExecutable $Executable -ExpectedTitle $Title
        [ClaudeUsageMovementSmoke.NativeMethods]::Drag(
            $fromX,
            $fromY,
            $fromX + $delta.X,
            $fromY + $delta.Y)

        Start-Sleep -Milliseconds 500
        Assert-ExactWindow -Handle $handle -Process $process -ExpectedExecutable $Executable -ExpectedTitle $Title
        $after = [ClaudeUsageMovementSmoke.NativeMethods]::GetBounds($handle)
        $afterWorkArea = [ClaudeUsageMovementSmoke.NativeMethods]::GetWorkArea($handle)
        $actualDeltaX = $after.Left - $before.Left
        $actualDeltaY = $after.Top - $before.Top
        if ($after.Right - $after.Left -ne $width -or $after.Bottom - $after.Top -ne $height) {
            throw "$Name HWND changed size during pointer drag."
        }
        if ($actualDeltaX -eq 0 -and $actualDeltaY -eq 0) {
            throw "$Name HWND did not move during pointer drag."
        }
        if ([Math]::Abs($actualDeltaX - $delta.X) -gt 8 -or
            [Math]::Abs($actualDeltaY - $delta.Y) -gt 8) {
            throw "$Name HWND moved by ($actualDeltaX,$actualDeltaY), expected approximately ($($delta.X),$($delta.Y))."
        }
        if (-not (Test-InsideWorkArea -Bounds $after -WorkArea $afterWorkArea)) {
            throw "$Name HWND ended outside its monitor work area."
        }
        return [pscustomobject]@{
            Name = $Name
            ProcessId = $process.Id
            Handle = $handle.ToInt64()
            Before = Format-Bounds -Bounds $before
            After = Format-Bounds -Bounds $after
            DeltaX = $actualDeltaX
            DeltaY = $actualDeltaY
            Width = $width
            Height = $height
            WorkArea = Format-Bounds -Bounds $afterWorkArea
        }
    }
    finally {
        Stop-ExactTestProcess -Process $process -ExpectedExecutable $Executable -WindowHandle $handle
        [void]$OwnedProcesses.Remove($process)
        $process.Dispose()
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
    try { & $Action }
    catch {
        [void]$Failures.Add([InvalidOperationException]::new(
            "Cleanup/postcondition '$Label' failed: $($_.Exception.Message)",
            $_.Exception))
    }
}

$archivePath = $null
$sourceExecutable = $null
if ($PSCmdlet.ParameterSetName -ceq "Zip") {
    $archivePath = [System.IO.Path]::GetFullPath($ZipPath)
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
        -not [string]::Equals([System.IO.Path]::GetExtension($archivePath), ".zip", [StringComparison]::OrdinalIgnoreCase)) {
        throw "ZipPath must identify an existing .zip file."
    }
}
else {
    $sourceExecutable = [System.IO.Path]::GetFullPath($ExecutablePath)
    if (-not (Test-Path -LiteralPath $sourceExecutable -PathType Leaf) -or
        [System.IO.Path]::GetFileName($sourceExecutable) -cne "ClaudeUsage.Windows.exe") {
        throw "ExecutablePath must identify an exact ClaudeUsage.Windows.exe."
    }
}

$sessionRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ClaudeUsage-portable-movement-$([Guid]::NewGuid().ToString('N'))"
Assert-SafeSessionRoot -Path $sessionRoot
$profileRoot = Join-Path $sessionRoot "profile"
$testAppData = Join-Path $profileRoot "AppData\Roaming"
$testLocalAppData = Join-Path $profileRoot "AppData\Local"
$testTemp = Join-Path $sessionRoot "temp"
$extractRoot = if ($PSCmdlet.ParameterSetName -ceq "Zip") {
    Join-Path $sessionRoot "app"
}
else {
    [System.IO.Path]::GetDirectoryName($sourceExecutable)
}
$executable = if ($PSCmdlet.ParameterSetName -ceq "Zip") {
    Join-Path $extractRoot "ClaudeUsage.Windows.exe"
}
else {
    $sourceExecutable
}

$realSettingsPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "ClaudeUsage\settings.json"
$realSettingsBefore = Get-FileState -Path $realSettingsPath
$originalForeground = [ClaudeUsageMovementSmoke.NativeMethods]::GetForegroundWindow()
$originalCursor = [ClaudeUsageMovementSmoke.NativeMethods]::GetCursorPosition()
$ownedProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$primaryFailure = $null
$cleanupFailures = [System.Collections.Generic.List[Exception]]::new()

try {
    [System.IO.Directory]::CreateDirectory($sessionRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($testAppData) | Out-Null
    [System.IO.Directory]::CreateDirectory($testLocalAppData) | Out-Null
    [System.IO.Directory]::CreateDirectory($testTemp) | Out-Null
    if ($PSCmdlet.ParameterSetName -ceq "Zip") {
        [System.IO.Directory]::CreateDirectory($extractRoot) | Out-Null
        Assert-SafeZipEntries -ArchivePath $archivePath -DestinationRoot $extractRoot
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf) -or
        [System.IO.Path]::GetFileName($executable) -cne "ClaudeUsage.Windows.exe") {
        throw "The selected artifact must contain an exact ClaudeUsage.Windows.exe."
    }

    foreach ($scenario in @(
            [pscustomobject]@{ Name = "Settings"; Mode = "--screenshot-settings"; Title = "Claude + Codex Usage"; Widget = $false },
            [pscustomobject]@{ Name = "History"; Mode = "--screenshot-history"; Title = "Usage history"; Widget = $false },
            [pscustomobject]@{ Name = "Widget"; Mode = "--screenshot-widget"; Title = "ClaudeUsage Widget"; Widget = $true })) {
        $result = Invoke-MovementScenario `
            -Name $scenario.Name `
            -Mode $scenario.Mode `
            -Title $scenario.Title `
            -Widget $scenario.Widget `
            -Executable $executable `
            -WorkingDirectory $extractRoot `
            -AppData $testAppData `
            -LocalAppData $testLocalAppData `
            -TempPath $testTemp `
            -TimeoutSeconds $TimeoutSeconds `
            -OwnedProcesses $ownedProcesses
        [void]$results.Add($result)
    }
}
catch {
    $primaryFailure = $_
}
finally {
    [ClaudeUsageMovementSmoke.NativeMethods]::ReleaseLeftButton()
    foreach ($ownedProcess in @($ownedProcesses)) {
        Invoke-CleanupStep -Failures $cleanupFailures -Label "stop exact PID $($ownedProcess.Id)" -Action {
            Stop-ExactTestProcess -Process $ownedProcess -ExpectedExecutable $executable
            $ownedProcess.Dispose()
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "restore cursor position" -Action {
        if (-not [ClaudeUsageMovementSmoke.NativeMethods]::RestoreCursor($originalCursor)) {
            throw "Cursor position was not restored."
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "restore foreground window" -Action {
        if (-not [ClaudeUsageMovementSmoke.NativeMethods]::RestoreForeground($originalForeground)) {
            throw "Foreground HWND was not restored."
        }
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "assert real settings unchanged" -Action {
        $realSettingsAfter = Get-FileState -Path $realSettingsPath
        Assert-FileStateUnchanged -Before $realSettingsBefore -After $realSettingsAfter -Path $realSettingsPath
    }
    Invoke-CleanupStep -Failures $cleanupFailures -Label "remove bounded temporary session" -Action {
        Assert-SafeSessionRoot -Path $sessionRoot
        for ($attempt = 0; $attempt -lt 5 -and (Test-Path -LiteralPath $sessionRoot); $attempt++) {
            Remove-Item -LiteralPath $sessionRoot -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $sessionRoot) { Start-Sleep -Milliseconds 250 }
        }
        if (Test-Path -LiteralPath $sessionRoot) {
            throw "Temporary movement session remains: $sessionRoot"
        }
    }
}

if ($cleanupFailures.Count -gt 0) {
    $allFailures = [System.Collections.Generic.List[Exception]]::new()
    if ($null -ne $primaryFailure) { [void]$allFailures.Add($primaryFailure.Exception) }
    foreach ($failure in $cleanupFailures) { [void]$allFailures.Add($failure) }
    throw [System.AggregateException]::new(
        "Portable movement smoke cleanup/postcondition failure(s): $($cleanupFailures.Count).",
        $allFailures)
}
if ($null -ne $primaryFailure) {
    $PSCmdlet.ThrowTerminatingError($primaryFailure)
}

foreach ($result in $results) {
    Write-Output "$($result.Name): $($result.Before) -> $($result.After), delta=($($result.DeltaX),$($result.DeltaY)), workArea=$($result.WorkArea)"
}
Write-Output "PASS: exact portable Settings, History, and Widget HWNDs moved through real SendInput pointer drags; sizes, work areas, user settings, input state, processes, and temporary files passed postconditions."
