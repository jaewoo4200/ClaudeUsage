using System.Text;
using System.Text.Json;

namespace ClaudeUsage.Startup.TestApp;

internal static class Program
{
    internal const string ResultPathEnvironmentVariable = "CLAUDEUSAGE_STARTUP_TEST_RESULT";

    [STAThread]
    private static int Main(string[] args)
    {
        var resultPath = Environment.GetEnvironmentVariable(ResultPathEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(resultPath))
        {
            return 4;
        }

        try
        {
            var directory = Path.GetDirectoryName(resultPath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var result = new StartupProbeResult(
                Environment.ProcessId,
                Environment.ProcessPath ?? string.Empty,
                AppContext.BaseDirectory,
                Environment.CurrentDirectory,
                args);
            var temporaryPath = $"{resultPath}.{Environment.ProcessId}.tmp";
            File.WriteAllText(
                temporaryPath,
                JsonSerializer.Serialize(result),
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            File.Move(temporaryPath, resultPath, overwrite: true);
            return 0;
        }
        catch
        {
            return 5;
        }
    }

    private sealed record StartupProbeResult(
        int ProcessId,
        string ExecutablePath,
        string BaseDirectory,
        string WorkingDirectory,
        string[] Arguments);
}
