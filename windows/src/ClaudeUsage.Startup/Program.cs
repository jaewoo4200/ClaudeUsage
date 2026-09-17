using System.Diagnostics;

namespace ClaudeUsage.Startup;

internal static class Program
{
    [STAThread]
    private static int Main()
    {
        try
        {
            var applicationDirectory = AppContext.BaseDirectory;
            var applicationPath = Path.Combine(applicationDirectory, "ClaudeUsage.Windows.exe");
            if (!File.Exists(applicationPath))
            {
                return 2;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = applicationPath,
                // Packaged startup helpers live under the read-only WindowsApps
                // tree. Never make that directory the main app's inherited CWD.
                WorkingDirectory = ResolveWritableWorkingDirectory(),
                UseShellExecute = false,
            };
            startInfo.ArgumentList.Add("--background");

            return Process.Start(startInfo) is null ? 3 : 0;
        }
        catch
        {
            // A login startup helper must fail silently; the main app remains
            // available from Start and can repair registration on next launch.
            return 1;
        }
    }

    private static string ResolveWritableWorkingDirectory()
    {
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return !string.IsNullOrWhiteSpace(userProfile) && Directory.Exists(userProfile)
            ? userProfile
            : Path.GetTempPath();
    }
}
