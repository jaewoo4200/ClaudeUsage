using System.Diagnostics;
using System.IO;

namespace ClaudeUsage.Windows.Services;

public sealed class CodexExecutableLocator(AppSettings settings)
{
    public string? Resolve()
    {
        if (IsUsable(settings.CodexExecutablePath))
        {
            return Path.GetFullPath(settings.CodexExecutablePath!);
        }

        var fromPath = ResolveFromPath();
        if (IsUsable(fromPath))
        {
            return fromPath;
        }

        return ResolveFromCodexDesktopCache();
    }

    private static string? ResolveFromPath()
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return null;
        }

        foreach (var path in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(path.Trim().Trim('"'), "codex.exe");
            if (IsUsable(candidate))
            {
                return Path.GetFullPath(candidate);
            }
        }

        return null;
    }

    private static string? ResolveFromCodexDesktopCache()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var root = Path.Combine(localAppData, "OpenAI", "Codex", "bin");
        if (!Directory.Exists(root))
        {
            return null;
        }

        try
        {
            return Directory.EnumerateFiles(root, "codex.exe", SearchOption.AllDirectories)
                .Select(path => new FileInfo(path))
                .Where(file => file.Exists && file.Length > 0)
                .OrderByDescending(file => file.LastWriteTimeUtc)
                .Select(file => file.FullName)
                .FirstOrDefault();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static bool IsUsable(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        try
        {
            var fullPath = Path.GetFullPath(path);
            var protectedPackageRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "WindowsApps") + Path.DirectorySeparatorChar;
            if (fullPath.StartsWith(protectedPackageRoot, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return string.Equals(Path.GetFileName(fullPath), "codex.exe", StringComparison.OrdinalIgnoreCase)
                   && File.Exists(fullPath)
                   && new FileInfo(fullPath).Length > 0;
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Codex executable validation failed: {exception.GetType().Name}");
            return false;
        }
    }
}
