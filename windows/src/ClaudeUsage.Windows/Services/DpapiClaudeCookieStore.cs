using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace ClaudeUsage.Windows.Services;

public sealed class DpapiClaudeCookieStore : IClaudeCookieStore
{
    private const int MaximumCookieBytes = 128 * 1024;
    private const int MaximumProtectedBytes = 1024 * 1024;

    private static readonly byte[] OptionalEntropy =
        Encoding.UTF8.GetBytes("ClaudeUsage.Windows/claude.ai-cookie/v1");

    private readonly SemaphoreSlim _ioGate = new(1, 1);

    public DpapiClaudeCookieStore(string? storagePath = null)
    {
        StoragePath = Path.GetFullPath(storagePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ClaudeUsage",
            "claude-session.dat"));
        CleanupTemporaryFilesBestEffort();
    }

    public string StoragePath { get; }

    public async Task<string?> LoadAsync(CancellationToken cancellationToken = default)
    {
        await _ioGate.WaitAsync(cancellationToken);
        try
        {
            return await LoadCoreAsync(cancellationToken);
        }
        finally
        {
            _ioGate.Release();
        }
    }

    private async Task<string?> LoadCoreAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(StoragePath))
        {
            return null;
        }

        var fileInfo = new FileInfo(StoragePath);
        if (fileInfo.Length is <= 0 or > MaximumProtectedBytes)
        {
            throw new CryptographicException("The saved Claude session has an invalid size.");
        }

        var protectedBytes = await File.ReadAllBytesAsync(StoragePath, cancellationToken);
        byte[]? plaintextBytes = null;
        try
        {
            plaintextBytes = ProtectedData.Unprotect(
                protectedBytes,
                OptionalEntropy,
                DataProtectionScope.CurrentUser);
            if (plaintextBytes.Length is <= 0 or > MaximumCookieBytes)
            {
                throw new CryptographicException("The saved Claude session has an invalid payload.");
            }

            var cookieHeader = Encoding.UTF8.GetString(plaintextBytes);
            ValidateCookieHeader(cookieHeader);
            return cookieHeader;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(protectedBytes);
            if (plaintextBytes is not null)
            {
                CryptographicOperations.ZeroMemory(plaintextBytes);
            }
        }
    }

    public async Task SaveAsync(
        string cookieHeader,
        CancellationToken cancellationToken = default)
    {
        ValidateCookieHeader(cookieHeader);

        await _ioGate.WaitAsync(cancellationToken);
        try
        {
            await SaveCoreAsync(cookieHeader, cancellationToken);
        }
        finally
        {
            _ioGate.Release();
        }
    }

    private async Task SaveCoreAsync(
        string cookieHeader,
        CancellationToken cancellationToken)
    {

        var plaintextBytes = Encoding.UTF8.GetBytes(cookieHeader);
        if (plaintextBytes.Length > MaximumCookieBytes)
        {
            CryptographicOperations.ZeroMemory(plaintextBytes);
            throw new ArgumentException("The Claude cookie header is too large.", nameof(cookieHeader));
        }

        byte[]? protectedBytes = null;
        string? temporaryPath = null;
        try
        {
            protectedBytes = ProtectedData.Protect(
                plaintextBytes,
                OptionalEntropy,
                DataProtectionScope.CurrentUser);

            var directory = Path.GetDirectoryName(StoragePath);
            if (string.IsNullOrEmpty(directory))
            {
                directory = Directory.GetCurrentDirectory();
            }

            Directory.CreateDirectory(directory);
            temporaryPath = Path.Combine(
                directory,
                $".{Path.GetFileName(StoragePath)}.{Guid.NewGuid():N}.tmp");

            await using (var stream = new FileStream(
                             temporaryPath,
                             FileMode.CreateNew,
                             FileAccess.Write,
                             FileShare.None,
                             bufferSize: 16 * 1024,
                             FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await stream.WriteAsync(protectedBytes, cancellationToken);
                await stream.FlushAsync(cancellationToken);
            }

            File.Move(temporaryPath, StoragePath, overwrite: true);
            temporaryPath = null;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintextBytes);
            if (protectedBytes is not null)
            {
                CryptographicOperations.ZeroMemory(protectedBytes);
            }

            if (temporaryPath is not null)
            {
                try
                {
                    File.Delete(temporaryPath);
                }
                catch (IOException)
                {
                    // Best effort after a cancelled or failed atomic write.
                }
                catch (UnauthorizedAccessException)
                {
                    // Best effort after a cancelled or failed atomic write.
                }
            }
        }
    }

    public async Task ClearAsync(CancellationToken cancellationToken = default)
    {
        await _ioGate.WaitAsync(cancellationToken);
        try
        {
            ClearCore();
        }
        finally
        {
            _ioGate.Release();
        }
    }

    public async Task<bool> ClearIfMatchesAsync(
        string expectedCookieHeader,
        CancellationToken cancellationToken = default)
    {
        ValidateCookieHeader(expectedCookieHeader);
        await _ioGate.WaitAsync(cancellationToken);
        try
        {
            var currentCookieHeader = await LoadCoreAsync(cancellationToken);
            if (!string.Equals(
                    currentCookieHeader,
                    expectedCookieHeader,
                    StringComparison.Ordinal))
            {
                return false;
            }

            ClearCore();
            return true;
        }
        finally
        {
            _ioGate.Release();
        }
    }

    private void ClearCore()
    {
        try
        {
            File.Delete(StoragePath);
            DeleteTemporaryFilesStrict();
            if (File.Exists(StoragePath) || Directory.Exists(StoragePath))
            {
                throw new IOException("The Claude session path remains after deletion.");
            }
        }
        catch (DirectoryNotFoundException)
        {
            // Already clear.
        }
        catch (Exception exception) when (exception is IOException
                                               or UnauthorizedAccessException
                                               or System.Security.SecurityException)
        {
            throw new IOException(
                "The saved Claude session could not be deleted completely.",
                exception);
        }
    }

    private void CleanupTemporaryFilesBestEffort()
    {
        try
        {
            DeleteTemporaryFilesStrict();
        }
        catch (Exception exception) when (exception is IOException
                                               or UnauthorizedAccessException
                                               or System.Security.SecurityException)
        {
            // A later startup or explicit logout retries the bounded cleanup.
        }
    }

    private void DeleteTemporaryFilesStrict()
    {
        var directory = Path.GetDirectoryName(StoragePath);
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
        {
            return;
        }

        var pattern = $".{Path.GetFileName(StoragePath)}.*.tmp";
        foreach (var temporaryPath in Directory.EnumerateFiles(
                     directory,
                     pattern,
                     SearchOption.TopDirectoryOnly))
        {
            File.Delete(temporaryPath);
        }

        if (Directory.EnumerateFiles(directory, pattern, SearchOption.TopDirectoryOnly).Any())
        {
            throw new IOException("One or more temporary Claude session files remain after deletion.");
        }
    }

    private static void ValidateCookieHeader(string cookieHeader)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(cookieHeader);
        if (cookieHeader.Contains('\r') || cookieHeader.Contains('\n'))
        {
            throw new ArgumentException("The Claude cookie header contains an invalid line break.", nameof(cookieHeader));
        }
    }
}
