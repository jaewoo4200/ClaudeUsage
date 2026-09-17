using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class CodexAppServerClientIntegrationTests
{
    [Fact]
    public async Task FetchAsyncExchangesJsonlAndTerminatesTheFakeProcessTree()
    {
        var directory = CreateTemporaryDirectory();
        var scriptPath = Path.Combine(directory, "fake-codex-success.ps1");
        var processIdsPath = Path.Combine(directory, "process-ids.txt");
        var messagesPath = Path.Combine(directory, "messages.jsonl");
        var processIds = Array.Empty<int>();
        try
        {
            File.WriteAllText(scriptPath, SuccessScript, new UTF8Encoding(false));
            var diagnostics = new List<string>();
            var client = new CodexAppServerClient(
                diagnostics.Add,
                _ => CreatePowerShellStartInfo(
                    scriptPath,
                    processIdsPath,
                    messagesPath),
                TimeSpan.FromSeconds(10),
                TimeSpan.FromSeconds(1));

            var payload = await client.FetchAsync("fake-codex.exe", CancellationToken.None);

            Assert.Equal(
                12,
                payload.RateLimits
                    .GetProperty("rateLimits")
                    .GetProperty("primary")
                    .GetProperty("usedPercent")
                    .GetInt32());
            Assert.Equal(34, payload.TokenUsage?.GetProperty("inputTokens").GetInt32());
            var messages = File.ReadAllLines(messagesPath);
            Assert.Equal(4, messages.Length);
            using (var initialize = JsonDocument.Parse(messages[0]))
            {
                Assert.Equal("initialize", initialize.RootElement.GetProperty("method").GetString());
                Assert.Equal(0, initialize.RootElement.GetProperty("id").GetInt32());
            }
            using (var initialized = JsonDocument.Parse(messages[1]))
            {
                Assert.Equal("initialized", initialized.RootElement.GetProperty("method").GetString());
            }
            using (var rateLimits = JsonDocument.Parse(messages[2]))
            {
                Assert.Equal("account/rateLimits/read", rateLimits.RootElement.GetProperty("method").GetString());
                Assert.Equal(7, rateLimits.RootElement.GetProperty("id").GetInt32());
            }
            using (var usage = JsonDocument.Parse(messages[3]))
            {
                Assert.Equal("account/usage/read", usage.RootElement.GetProperty("method").GetString());
                Assert.Equal(8, usage.RootElement.GetProperty("id").GetInt32());
            }

            Assert.Contains("process-started", diagnostics);
            Assert.Contains("initialize-completed", diagnostics);
            Assert.Contains("response:7", diagnostics);
            Assert.DoesNotContain(diagnostics, message => message.Contains('{', StringComparison.Ordinal));

            processIds = ReadProcessIds(processIdsPath);
            Assert.Equal(2, processIds.Length);
            Assert.True(
                SpinWait.SpinUntil(
                    () => processIds.All(processId => !IsProcessRunning(processId)),
                    TimeSpan.FromSeconds(5)),
                "The fake Codex process tree was still running after FetchAsync returned.");
        }
        finally
        {
            StopProcesses(processIds);
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task FetchAsyncTimesOutAndTerminatesTheUnresponsiveProcess()
    {
        var directory = CreateTemporaryDirectory();
        var scriptPath = Path.Combine(directory, "fake-codex-timeout.ps1");
        var processIdsPath = Path.Combine(directory, "process-ids.txt");
        var processIds = Array.Empty<int>();
        try
        {
            File.WriteAllText(scriptPath, TimeoutScript, new UTF8Encoding(false));
            var client = new CodexAppServerClient(
                diagnosticObserver: null,
                _ => CreatePowerShellStartInfo(scriptPath, processIdsPath),
                TimeSpan.FromSeconds(2),
                TimeSpan.Zero);

            var exception = await Assert.ThrowsAsync<CodexRpcException>(
                () => client.FetchAsync("fake-codex.exe", CancellationToken.None));

            Assert.Equal(CodexRpcErrorKind.Timeout, exception.Kind);
            Assert.True(File.Exists(processIdsPath), "The fake server did not start before the timeout.");
            processIds = ReadProcessIds(processIdsPath);
            Assert.Single(processIds);
            Assert.True(
                SpinWait.SpinUntil(
                    () => !IsProcessRunning(processIds[0]),
                    TimeSpan.FromSeconds(5)),
                "The timed-out fake Codex process was still running.");
        }
        finally
        {
            StopProcesses(processIds);
            Directory.Delete(directory, recursive: true);
        }
    }

    private static ProcessStartInfo CreatePowerShellStartInfo(
        string scriptPath,
        params string[] scriptArguments)
    {
        var windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var powerShellPath = Path.Combine(
            windowsDirectory,
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        var startInfo = new ProcessStartInfo
        {
            FileName = powerShellPath,
            WorkingDirectory = Path.GetDirectoryName(scriptPath)!,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardInputEncoding = new UTF8Encoding(false),
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false),
        };
        foreach (var argument in new[]
                 {
                     "-NoLogo",
                     "-NoProfile",
                     "-NonInteractive",
                     "-ExecutionPolicy",
                     "Bypass",
                     "-File",
                     scriptPath,
                 }.Concat(scriptArguments))
        {
            startInfo.ArgumentList.Add(argument);
        }

        return startInfo;
    }

    private static int[] ReadProcessIds(string path) =>
        File.ReadAllLines(path)
            .Select(line => int.Parse(line, System.Globalization.CultureInfo.InvariantCulture))
            .ToArray();

    private static bool IsProcessRunning(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    private static void StopProcesses(IEnumerable<int> processIds)
    {
        foreach (var processId in processIds)
        {
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
    }

    private static string CreateTemporaryDirectory()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            $"claudeusage-fake-codex-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private const string SuccessScript = """
        param(
            [Parameter(Mandatory = $true)][string]$ProcessIdsPath,
            [Parameter(Mandatory = $true)][string]$MessagesPath
        )
        $ErrorActionPreference = "Stop"
        $child = Start-Process `
            -FilePath (Join-Path $PSHOME "powershell.exe") `
            -ArgumentList @("-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "Start-Sleep -Seconds 60") `
            -WindowStyle Hidden `
            -PassThru
        [IO.File]::WriteAllLines(
            $ProcessIdsPath,
            @([string]$PID, [string]$child.Id),
            [Text.UTF8Encoding]::new($false))
        for ($index = 0; $index -lt 4; $index++) {
            $line = [Console]::In.ReadLine()
            if ($null -eq $line) { exit 3 }
            [IO.File]::AppendAllText(
                $MessagesPath,
                $line + [Environment]::NewLine,
                [Text.UTF8Encoding]::new($false))
            if ($index -eq 0) {
                [Console]::Out.WriteLine('{"id":0,"result":{"server":"fake"}}')
                [Console]::Out.Flush()
            }
        }
        [Console]::Out.WriteLine('{"id":7,"result":{"rateLimits":{"primary":{"usedPercent":12}}}}')
        [Console]::Out.WriteLine('{"id":8,"result":{"inputTokens":34}}')
        [Console]::Out.Flush()
        Start-Sleep -Seconds 60
        """;

    private const string TimeoutScript = """
        param([Parameter(Mandatory = $true)][string]$ProcessIdsPath)
        [IO.File]::WriteAllText(
            $ProcessIdsPath,
            [string]$PID + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false))
        [void][Console]::In.ReadLine()
        Start-Sleep -Seconds 60
        """;
}
