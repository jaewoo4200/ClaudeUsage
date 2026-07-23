using System.Globalization;
using System.Text;
using System.Text.Json;

namespace ClaudeUsage.Core.History;

public sealed record ClaudeLocalTokenUsage(long TodayTokens, DateTimeOffset UpdatedAt);

/// <summary>
/// Aggregates numeric usage fields from Claude Code JSONL files without retaining log content.
/// </summary>
public static class ClaudeLocalTokenAggregator
{
    private static readonly string[] TokenFields =
    [
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    ];

    public static Task<ClaudeLocalTokenUsage?> ScanAsync(
        string rootDirectory,
        DateTimeOffset? now = null,
        TimeZoneInfo? calendarTimeZone = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(rootDirectory);
        var capturedNow = now ?? DateTimeOffset.Now;
        var timeZone = calendarTimeZone ?? TimeZoneInfo.Local;
        return Task.Run(
            () => ScanCoreAsync(rootDirectory, capturedNow, timeZone, cancellationToken),
            cancellationToken);
    }

    private static async Task<ClaudeLocalTokenUsage?> ScanCoreAsync(
        string rootDirectory,
        DateTimeOffset now,
        TimeZoneInfo calendarTimeZone,
        CancellationToken cancellationToken)
    {
        if (!Directory.Exists(rootDirectory))
        {
            return null;
        }

        var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, calendarTimeZone).DateTime);
        var seenMessages = new HashSet<string>(StringComparer.Ordinal);
        long total = 0;

        var enumerationOptions = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            ReturnSpecialDirectories = false,
            MatchCasing = MatchCasing.CaseInsensitive,
            AttributesToSkip = FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReparsePoint,
        };

        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(rootDirectory, "*.jsonl", enumerationOptions);
        }
        catch (Exception exception) when (IsFileSystemException(exception))
        {
            return null;
        }

        try
        {
            foreach (var file in files)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!WasModifiedOn(file, today, calendarTimeZone))
                {
                    continue;
                }

                try
                {
                    using var stream = new FileStream(
                        file,
                        FileMode.Open,
                        FileAccess.Read,
                        FileShare.ReadWrite | FileShare.Delete,
                        bufferSize: 64 * 1024,
                        FileOptions.Asynchronous | FileOptions.SequentialScan);
                    using var reader = new StreamReader(
                        stream,
                        Encoding.UTF8,
                        detectEncodingFromByteOrderMarks: true,
                        bufferSize: 64 * 1024,
                        leaveOpen: false);

                    while (await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false) is { } line)
                    {
                        if (line.Length == 0)
                        {
                            continue;
                        }

                        if (TryReadEntry(line, now, today, calendarTimeZone, seenMessages, out var tokens))
                        {
                            total = SaturatingAdd(total, tokens);
                        }
                    }
                }
                catch (Exception exception) when (IsFileSystemException(exception))
                {
                    // A live Claude session can rotate or briefly lock a file. Other files remain usable.
                }
            }
        }
        catch (Exception exception) when (IsFileSystemException(exception))
        {
            // Enumeration can still fail after it starts if a directory disappears. Keep the safe partial sum.
        }

        return new ClaudeLocalTokenUsage(total, now);
    }

    private static bool WasModifiedOn(string file, DateOnly day, TimeZoneInfo timeZone)
    {
        try
        {
            var modified = new DateTimeOffset(File.GetLastWriteTimeUtc(file), TimeSpan.Zero);
            return DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(modified, timeZone).DateTime) == day;
        }
        catch (Exception exception) when (IsFileSystemException(exception))
        {
            return false;
        }
    }

    private static bool TryReadEntry(
        string line,
        DateTimeOffset now,
        DateOnly today,
        TimeZoneInfo timeZone,
        ISet<string> seenMessages,
        out long tokens)
    {
        tokens = 0;
        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("timestamp", out var timestampElement)
                || timestampElement.ValueKind != JsonValueKind.String
                || !TryParseTimestamp(timestampElement.GetString(), out var timestamp)
                || timestamp > now
                || DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(timestamp, timeZone).DateTime) != today
                || !root.TryGetProperty("message", out var message)
                || message.ValueKind != JsonValueKind.Object
                || !message.TryGetProperty("usage", out var usage)
                || usage.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var timestampText = timestampElement.GetString()!;
            var requestId = ReadString(root, "requestId");
            var messageId = ReadString(message, "id");
            var identity = $"{requestId ?? string.Empty}|{messageId ?? string.Empty}|{timestampText}";
            if (!seenMessages.Add(identity))
            {
                return false;
            }

            foreach (var field in TokenFields)
            {
                if (usage.TryGetProperty(field, out var value) && TryReadNonNegativeInt64(value, out var amount))
                {
                    tokens = SaturatingAdd(tokens, amount);
                }
            }

            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static string? ReadString(JsonElement parent, string propertyName) =>
        parent.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static bool TryParseTimestamp(string? value, out DateTimeOffset timestamp) =>
        DateTimeOffset.TryParse(
            value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal,
            out timestamp);

    private static bool TryReadNonNegativeInt64(JsonElement value, out long number)
    {
        var parsed = value.ValueKind switch
        {
            JsonValueKind.Number => value.TryGetInt64(out var numeric) ? numeric : -1,
            JsonValueKind.String => long.TryParse(
                value.GetString(),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out var text) ? text : -1,
            _ => -1,
        };

        number = parsed;
        return parsed >= 0;
    }

    private static long SaturatingAdd(long left, long right) =>
        right > 0 && left > long.MaxValue - right ? long.MaxValue : left + right;

    private static bool IsFileSystemException(Exception exception) => exception is
        IOException or
        UnauthorizedAccessException or
        NotSupportedException or
        System.Security.SecurityException;
}
