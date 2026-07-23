using System.IO;

namespace ClaudeUsage.Windows.Services;

public static class ClaudeLoginProfileCleanup
{
    private const string ActiveLeaseFileName = ".active-profile";
    private static readonly SemaphoreSlim CleanupGate = new(1, 1);

    public static string ProfileRoot { get; } = Path.Combine(
        Path.GetTempPath(),
        "ClaudeUsage",
        "WebView2");

    public static Task CleanupStaleProfilesAsync(
        CancellationToken cancellationToken = default) =>
        CleanupStaleProfilesAsync(ProfileRoot, cancellationToken);

    internal static async Task CleanupStaleProfilesAsync(
        string profileRoot,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(profileRoot);
        await CleanupGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            string[] directories;
            try
            {
                if (!Directory.Exists(profileRoot))
                {
                    return;
                }

                directories = Directory.GetDirectories(profileRoot, "login-*");
            }
            catch (Exception exception) when (
                exception is IOException
                    or UnauthorizedAccessException
                    or System.Security.SecurityException)
            {
                // Cleanup is best effort. A later normal startup retries it.
                return;
            }

            foreach (var directory in directories)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (IsActivelyLeased(directory))
                {
                    continue;
                }

                await DeleteProfileCoreAsync(
                        directory,
                        attempts: 1,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
        }
        finally
        {
            CleanupGate.Release();
        }
    }

    public static Task<bool> DeleteProfileWithRetryAsync(
        string path,
        int attempts = 5,
        CancellationToken cancellationToken = default) =>
        DeleteProfileWithRetryAsync(ProfileRoot, path, attempts, cancellationToken);

    internal static async Task<bool> DeleteProfileWithRetryAsync(
        string profileRoot,
        string path,
        int attempts = 5,
        CancellationToken cancellationToken = default)
    {
        var target = ValidateProfilePath(profileRoot, path);
        await CleanupGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await DeleteProfileCoreAsync(target, attempts, cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            CleanupGate.Release();
        }
    }

    internal static FileStream AcquireProfileLease(string path) =>
        AcquireProfileLease(ProfileRoot, path);

    internal static FileStream AcquireProfileLease(string profileRoot, string path)
    {
        var target = ValidateProfilePath(profileRoot, path);
        Directory.CreateDirectory(target);
        return new FileStream(
            Path.Combine(target, ActiveLeaseFileName),
            FileMode.OpenOrCreate,
            FileAccess.ReadWrite,
            FileShare.None,
            bufferSize: 1,
            FileOptions.DeleteOnClose);
    }

    private static async Task<bool> DeleteProfileCoreAsync(
        string target,
        int attempts,
        CancellationToken cancellationToken)
    {
        var attemptCount = Math.Max(1, attempts);
        for (var attempt = 0; attempt < attemptCount; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                if (Directory.Exists(target))
                {
                    Directory.Delete(target, recursive: true);
                }

                return true;
            }
            catch (DirectoryNotFoundException)
            {
                // Another serialized or external cleanup already completed it.
                return true;
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                if (attempt + 1 >= attemptCount)
                {
                    return false;
                }

                await Task.Delay(
                        TimeSpan.FromMilliseconds(150 * (attempt + 1)),
                        cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        return false;
    }

    private static string ValidateProfilePath(string profileRoot, string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(profileRoot);
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var root = Path.GetFullPath(profileRoot)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var target = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var parent = Path.GetDirectoryName(target);
        var name = Path.GetFileName(target);
        if (!string.Equals(parent, root, StringComparison.OrdinalIgnoreCase)
            || !name.StartsWith("login-", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException(
                "Only direct ClaudeUsage temporary login profiles can be removed.",
                nameof(path));
        }

        return target;
    }

    private static bool IsActivelyLeased(string directory)
    {
        var leasePath = Path.Combine(directory, ActiveLeaseFileName);
        if (!File.Exists(leasePath))
        {
            return false;
        }

        try
        {
            using var leaseProbe = new FileStream(
                leasePath,
                FileMode.Open,
                FileAccess.ReadWrite,
                FileShare.None,
                bufferSize: 1,
                FileOptions.None);
            return false;
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or System.Security.SecurityException)
        {
            return true;
        }
    }
}
