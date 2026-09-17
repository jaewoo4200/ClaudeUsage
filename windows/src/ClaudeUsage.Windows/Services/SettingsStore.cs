using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClaudeUsage.Windows.Services;

public static class SettingsStore
{
    private static readonly object SyncRoot = new();
    private static readonly HashSet<string> PendingCorruptPaths = new(
        StringComparer.OrdinalIgnoreCase);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static string SettingsDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ClaudeUsage");

    public static string SettingsPath => Path.Combine(SettingsDirectory, "settings.json");

    public static AppSettings Load() => Load(SettingsPath, DateTimeOffset.UtcNow);

    internal static AppSettings Load(
        string settingsPath,
        DateTimeOffset quarantineTimestamp)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(settingsPath);
        var fullSettingsPath = Path.GetFullPath(settingsPath);

        lock (SyncRoot)
        {
            try
            {
                if (!File.Exists(fullSettingsPath))
                {
                    PendingCorruptPaths.Remove(fullSettingsPath);
                    return CreateDefaults();
                }

                AppSettings? settings;
                using (var stream = new FileStream(
                           fullSettingsPath,
                           FileMode.Open,
                           FileAccess.Read,
                           FileShare.Read))
                {
                    settings = JsonSerializer.Deserialize<AppSettings>(stream, JsonOptions);
                }

                if (settings is null)
                {
                    QuarantineOrRemember(fullSettingsPath, quarantineTimestamp);
                    return CreateDefaults();
                }

                PendingCorruptPaths.Remove(fullSettingsPath);
                settings.Normalize();
                return settings;
            }
            catch (Exception exception) when (
                exception is JsonException or NotSupportedException)
            {
                QuarantineOrRemember(fullSettingsPath, quarantineTimestamp);
                return CreateDefaults();
            }
            catch (Exception exception) when (
                exception is IOException
                    or UnauthorizedAccessException
                    or System.Security.SecurityException)
            {
                return CreateDefaults();
            }
        }
    }

    /// <returns>True only when the complete settings file was replaced atomically.</returns>
    public static bool Save(AppSettings settings) =>
        Save(settings, SettingsPath, DateTimeOffset.UtcNow);

    internal static bool Save(
        AppSettings settings,
        string settingsPath,
        DateTimeOffset quarantineTimestamp)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentException.ThrowIfNullOrWhiteSpace(settingsPath);
        var fullSettingsPath = Path.GetFullPath(settingsPath);
        var settingsDirectory = Path.GetDirectoryName(fullSettingsPath)
            ?? throw new ArgumentException("A settings directory is required.", nameof(settingsPath));

        lock (SyncRoot)
        {
            settings.Normalize();
            var temporaryPath = fullSettingsPath + ".tmp";
            try
            {
                if (PendingCorruptPaths.Contains(fullSettingsPath))
                {
                    if (File.Exists(fullSettingsPath)
                        && !TryQuarantineCorruptFile(
                            fullSettingsPath,
                            quarantineTimestamp))
                    {
                        // Never overwrite an unreadable original that could not
                        // first be preserved for recovery.
                        return false;
                    }

                    PendingCorruptPaths.Remove(fullSettingsPath);
                }

                Directory.CreateDirectory(settingsDirectory);
                using (var stream = new FileStream(
                           temporaryPath,
                           FileMode.Create,
                           FileAccess.Write,
                           FileShare.None,
                           bufferSize: 4096,
                           FileOptions.WriteThrough))
                {
                    JsonSerializer.Serialize(stream, settings, JsonOptions);
                    stream.Flush(flushToDisk: true);
                }

                ReplaceAtomically(temporaryPath, fullSettingsPath);
                return true;
            }
            catch (Exception exception) when (
                exception is IOException
                    or UnauthorizedAccessException
                    or NotSupportedException
                    or System.Security.SecurityException)
            {
                // The caller keeps the in-memory value for this session, but must
                // not claim persistence succeeded (especially for privacy opt-outs).
                return false;
            }
            finally
            {
                TryDelete(temporaryPath);
            }
        }
    }

    private static AppSettings CreateDefaults()
    {
        var settings = new AppSettings();
        settings.Normalize();
        return settings;
    }

    private static void QuarantineOrRemember(
        string settingsPath,
        DateTimeOffset quarantineTimestamp)
    {
        if (TryQuarantineCorruptFile(settingsPath, quarantineTimestamp))
        {
            PendingCorruptPaths.Remove(settingsPath);
        }
        else if (File.Exists(settingsPath))
        {
            PendingCorruptPaths.Add(settingsPath);
        }
    }

    private static bool TryQuarantineCorruptFile(
        string settingsPath,
        DateTimeOffset quarantineTimestamp)
    {
        try
        {
            if (!File.Exists(settingsPath))
            {
                return true;
            }

            var directory = Path.GetDirectoryName(settingsPath)
                ?? throw new IOException("The settings directory could not be resolved.");
            var stem = Path.GetFileNameWithoutExtension(settingsPath);
            var extension = Path.GetExtension(settingsPath);
            var timestamp = quarantineTimestamp.UtcDateTime.ToString(
                "yyyyMMdd'T'HHmmssfffffff'Z'",
                CultureInfo.InvariantCulture);
            var candidate = Path.Combine(
                directory,
                $"{stem}.corrupt-{timestamp}{extension}");
            for (var suffix = 1; File.Exists(candidate); suffix++)
            {
                candidate = Path.Combine(
                    directory,
                    $"{stem}.corrupt-{timestamp}-{suffix}{extension}");
            }

            File.Move(settingsPath, candidate);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or NotSupportedException
                or System.Security.SecurityException)
        {
            return false;
        }
    }

    private static void ReplaceAtomically(string temporaryPath, string settingsPath)
    {
        if (!File.Exists(settingsPath))
        {
            File.Move(temporaryPath, settingsPath);
            return;
        }

        try
        {
            File.Replace(temporaryPath, settingsPath, destinationBackupFileName: null);
        }
        catch (Exception exception) when (exception is IOException or PlatformNotSupportedException)
        {
            // Move with overwrite is the same-volume fallback for file systems that
            // do not implement ReplaceFile. The temporary file is in the same folder.
            File.Move(temporaryPath, settingsPath, overwrite: true);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Best-effort cleanup only.
        }
    }
}
