using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace ClaudeUsage.Startup.Tests;

public sealed class StartupHelperBlackBoxTests
{
    private const string ResultPathEnvironmentVariable = "CLAUDEUSAGE_STARTUP_TEST_RESULT";
    private static readonly TimeSpan ProcessTimeout = TimeSpan.FromSeconds(10);

    [Fact]
    public void LaunchesMainExecutableBesideHelperWithBackgroundAndWritableWorkingDirectory()
    {
        var testDirectory = CreateTemporaryDirectory();
        var applicationDirectory = Path.Combine(testDirectory, "application");
        var callerDirectory = Path.Combine(testDirectory, "caller");
        var resultPath = Path.Combine(testDirectory, "startup-result.json");
        var helperProcessId = 0;
        var mainProcessId = 0;

        try
        {
            Directory.CreateDirectory(applicationDirectory);
            Directory.CreateDirectory(callerDirectory);
            CopyFixture("Startup", applicationDirectory);
            CopyFixture("TestApp", applicationDirectory);

            var helperPath = Path.Combine(applicationDirectory, "ClaudeUsage.Startup.exe");
            using var helper = StartHelper(helperPath, callerDirectory, resultPath);
            helperProcessId = helper.Id;

            AssertProcessExited(helper, expectedExitCode: 0);
            Assert.True(
                SpinWait.SpinUntil(() => File.Exists(resultPath), ProcessTimeout),
                "The fake main application did not report its launch contract.");

            var result = JsonSerializer.Deserialize<StartupProbeResult>(File.ReadAllText(resultPath));
            Assert.NotNull(result);
            mainProcessId = result.ProcessId;

            Assert.Equal(new[] { "--background" }, result.Arguments);
            AssertPathEqual(
                Path.Combine(applicationDirectory, "ClaudeUsage.Windows.exe"),
                result.ExecutablePath);
            AssertPathEqual(applicationDirectory, result.BaseDirectory);
            AssertPathEqual(ResolveExpectedWorkingDirectory(), result.WorkingDirectory);
            Assert.NotEqual(
                NormalizePath(callerDirectory),
                NormalizePath(result.WorkingDirectory),
                StringComparer.OrdinalIgnoreCase);
            Assert.False(IsProcessRunning(helperProcessId));
            Assert.True(
                SpinWait.SpinUntil(() => !IsProcessRunning(mainProcessId), ProcessTimeout),
                "The fake main application was left running after recording startup.");
        }
        finally
        {
            StopProcess(mainProcessId);
            StopProcess(helperProcessId);
            DeleteDirectory(testDirectory);
        }
    }

    [Fact]
    public void MissingMainExecutableReturnsSafeFailureWithoutLeavingHelperRunning()
    {
        var testDirectory = CreateTemporaryDirectory();
        var applicationDirectory = Path.Combine(testDirectory, "application");
        var callerDirectory = Path.Combine(testDirectory, "caller");
        var resultPath = Path.Combine(testDirectory, "unexpected-result.json");
        var helperProcessId = 0;

        try
        {
            Directory.CreateDirectory(applicationDirectory);
            Directory.CreateDirectory(callerDirectory);
            CopyFixture("Startup", applicationDirectory);

            var helperPath = Path.Combine(applicationDirectory, "ClaudeUsage.Startup.exe");
            using var helper = StartHelper(helperPath, callerDirectory, resultPath);
            helperProcessId = helper.Id;

            AssertProcessExited(helper, expectedExitCode: 2);
            Assert.False(File.Exists(resultPath));
            Assert.False(IsProcessRunning(helperProcessId));
        }
        finally
        {
            StopProcess(helperProcessId);
            DeleteDirectory(testDirectory);
        }
    }

    private static Process StartHelper(
        string helperPath,
        string callerDirectory,
        string resultPath)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = helperPath,
            WorkingDirectory = callerDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        startInfo.Environment[ResultPathEnvironmentVariable] = resultPath;
        ConfigurePrivateDotNetRuntime(startInfo);
        return Process.Start(startInfo)
            ?? throw new InvalidOperationException("The startup helper process could not be created.");
    }

    private static void ConfigurePrivateDotNetRuntime(ProcessStartInfo startInfo)
    {
        var runtimeDirectory = new DirectoryInfo(RuntimeEnvironment.GetRuntimeDirectory());
        var dotNetRoot = runtimeDirectory.Parent?.Parent?.Parent?.FullName;
        if (string.IsNullOrWhiteSpace(dotNetRoot) ||
            !File.Exists(Path.Combine(dotNetRoot, "dotnet.exe")))
        {
            throw new InvalidOperationException(
                $"Could not resolve the dotnet root from '{runtimeDirectory.FullName}'.");
        }

        startInfo.Environment["DOTNET_ROOT"] = dotNetRoot;
        startInfo.Environment[$"DOTNET_ROOT_{RuntimeInformation.ProcessArchitecture.ToString().ToUpperInvariant()}"] =
            dotNetRoot;
        startInfo.Environment["DOTNET_MULTILEVEL_LOOKUP"] = "0";
    }

    private static void AssertProcessExited(Process process, int expectedExitCode)
    {
        var exited = process.WaitForExit((int)ProcessTimeout.TotalMilliseconds);
        if (!exited)
        {
            StopProcess(process.Id);
        }

        Assert.True(exited, $"Process {process.Id} did not exit within {ProcessTimeout}.");
        Assert.Equal(expectedExitCode, process.ExitCode);
    }

    private static void CopyFixture(string fixtureName, string destinationDirectory)
    {
        var sourceDirectory = Path.Combine(
            AppContext.BaseDirectory,
            "BlackBoxFixtures",
            fixtureName);
        Assert.True(
            Directory.Exists(sourceDirectory),
            $"Black-box fixture directory is missing: {sourceDirectory}");

        foreach (var sourcePath in Directory.GetFiles(sourceDirectory))
        {
            File.Copy(
                sourcePath,
                Path.Combine(destinationDirectory, Path.GetFileName(sourcePath)),
                overwrite: true);
        }
    }

    private static string ResolveExpectedWorkingDirectory()
    {
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return !string.IsNullOrWhiteSpace(userProfile) && Directory.Exists(userProfile)
            ? userProfile
            : Path.GetTempPath();
    }

    private static void AssertPathEqual(string expected, string actual) =>
        Assert.Equal(
            NormalizePath(expected),
            NormalizePath(actual),
            StringComparer.OrdinalIgnoreCase);

    private static string NormalizePath(string path) =>
        Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

    private static bool IsProcessRunning(int processId)
    {
        if (processId <= 0)
        {
            return false;
        }

        try
        {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch (Exception exception) when (
            exception is ArgumentException or InvalidOperationException)
        {
            return false;
        }
    }

    private static void StopProcess(int processId)
    {
        if (processId <= 0)
        {
            return;
        }

        try
        {
            using var process = Process.GetProcessById(processId);
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(5_000);
            }
        }
        catch (Exception exception) when (
            exception is ArgumentException or InvalidOperationException)
        {
            // The process already exited.
        }
    }

    private static string CreateTemporaryDirectory()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            $"claudeusage-startup-blackbox-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static void DeleteDirectory(string path)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                if (Directory.Exists(path))
                {
                    Directory.Delete(path, recursive: true);
                }

                return;
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                Thread.Sleep(50);
            }
        }

        Directory.Delete(path, recursive: true);
    }

    private sealed record StartupProbeResult(
        int ProcessId,
        string ExecutablePath,
        string BaseDirectory,
        string WorkingDirectory,
        string[] Arguments);
}
