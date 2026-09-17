using System.Text.Json;
using System.Text.Json.Serialization;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Core.History;

/// <summary>
/// Local-only, bounded usage history. The store never uploads data and writes atomically.
/// </summary>
public sealed class UsageHistoryStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    private readonly object _gate = new();
    private readonly string _filePath;
    private readonly UsageHistoryOptions _options;
    private List<UsageHistorySample> _samples;

    public UsageHistoryStore(string? filePath = null, UsageHistoryOptions? options = null)
    {
        _filePath = Path.GetFullPath(filePath ?? DefaultFilePath);
        _options = options ?? new UsageHistoryOptions();
        _options.Validate();
        CleanupTemporaryFiles(_filePath);
        _samples = Load(_filePath);
        var loadedCount = _samples.Count;
        Prune(DateTimeOffset.Now);
        if (_samples.Count != loadedCount)
        {
            PersistUnderLock();
        }
    }

    public event EventHandler? Changed;

    public static string DefaultFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ClaudeUsage",
        "usage-history.json");

    public string FilePath => _filePath;

    public bool HasSamples
    {
        get
        {
            lock (_gate)
            {
                return _samples.Count != 0;
            }
        }
    }

    public IReadOnlyList<UsageHistorySample> Samples
    {
        get
        {
            lock (_gate)
            {
                return Array.AsReadOnly(_samples.ToArray());
            }
        }
    }

    /// <summary>
    /// The most recent persistence failure, if any. Recording remains available in memory.
    /// </summary>
    public Exception? LastPersistenceError { get; private set; }

    /// <returns>True when a sample was appended, including a reset-forced sample.</returns>
    public bool Record(
        UsageHistorySnapshot snapshot,
        DateTimeOffset? timestamp = null,
        bool force = false)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (!snapshot.HasUsage)
        {
            return false;
        }

        var recordedAt = timestamp ?? DateTimeOffset.Now;
        var sample = new UsageHistorySample(recordedAt, snapshot);

        lock (_gate)
        {
            if (_samples.Count != 0 && !force)
            {
                var last = _samples[^1];
                var elapsed = recordedAt - last.Timestamp;
                var resetDetected = IsReset(last.Snapshot, sample.Snapshot, _options.ResetDropThreshold);
                if (elapsed < _options.MinimumSampleInterval && !resetDetected)
                {
                    return false;
                }
            }

            _samples.Add(sample);
            if (_samples.Count > 1 && _samples[^2].Timestamp > recordedAt)
            {
                _samples.Sort(static (left, right) => left.Timestamp.CompareTo(right.Timestamp));
            }

            Prune(recordedAt);
            PersistUnderLock();
        }

        Changed?.Invoke(this, EventArgs.Empty);
        return true;
    }

    public void Clear()
    {
        IOException? deletionFailure = null;
        lock (_gate)
        {
            _samples = [];
            LastPersistenceError = null;
            try
            {
                DeleteHistoryFilesStrict(_filePath);
            }
            catch (Exception exception) when (IsFileSystemException(exception))
            {
                LastPersistenceError = exception;
                deletionFailure = new IOException(
                    "The local usage history could not be deleted completely.",
                    exception);
            }
        }

        Changed?.Invoke(this, EventArgs.Empty);
        if (deletionFailure is not null)
        {
            throw deletionFailure;
        }
    }

    public UsageTrend Trend(
        DateTimeOffset? now = null,
        TimeSpan? window = null,
        TimeZoneInfo? calendarTimeZone = null)
    {
        var current = now ?? DateTimeOffset.Now;
        var selectedWindow = window ?? _options.TrendWindow;
        if (selectedWindow <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(window));
        }

        UsageHistorySample[] recent;
        lock (_gate)
        {
            var cutoff = current - selectedWindow;
            recent = _samples
                .Where(sample => sample.Timestamp >= cutoff && sample.Timestamp <= current)
                .OrderBy(sample => sample.Timestamp)
                .ToArray();
        }

        if (recent.Length == 0)
        {
            return UsageTrend.Empty;
        }

        DateTimeOffset? latestReset = null;
        var segmentStart = 0;
        for (var index = 1; index < recent.Length; index++)
        {
            if (IsReset(recent[index - 1].Snapshot, recent[index].Snapshot, _options.ResetDropThreshold))
            {
                latestReset = recent[index].Timestamp;
                segmentStart = index;
            }
        }

        var segment = recent[segmentStart..];
        var pressureSamples = segment
            .Select(sample => (sample.Timestamp, Pressure: sample.Snapshot.Pressure))
            .Where(sample => sample.Pressure is not null)
            .Select(sample => (sample.Timestamp, Pressure: sample.Pressure!.Value))
            .ToArray();

        var points = pressureSamples
            .TakeLast(_options.MaximumTrendPoints)
            .Select(sample => sample.Pressure)
            .ToArray();

        double? deltaPercent = null;
        double? percentPerHour = null;
        if (pressureSamples.Length != 0)
        {
            var first = pressureSamples[0];
            var last = pressureSamples[^1];
            var duration = last.Timestamp - first.Timestamp;
            if (duration >= TimeSpan.FromMinutes(1))
            {
                var delta = Math.Max(0, last.Pressure - first.Pressure);
                deltaPercent = delta;
                percentPerHour = Math.Min(100, delta / duration.TotalHours);
            }
        }

        var tokenSamples = segment
            .Select(sample => (sample.Timestamp, Tokens: sample.Snapshot.TodayTokens))
            .Where(sample => sample.Tokens is not null)
            .Select(sample => (sample.Timestamp, Tokens: sample.Tokens!.Value))
            .ToArray();

        long? recentTokenDelta = null;
        if (tokenSamples.Length != 0)
        {
            var first = tokenSamples[0];
            var last = tokenSamples[^1];
            var timeZone = calendarTimeZone ?? TimeZoneInfo.Local;
            var firstDay = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(first.Timestamp, timeZone).DateTime);
            var lastDay = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(last.Timestamp, timeZone).DateTime);
            if (firstDay == lastDay && last.Tokens >= first.Tokens)
            {
                recentTokenDelta = last.Tokens - first.Tokens;
            }
        }

        return new UsageTrend(
            points,
            deltaPercent,
            percentPerHour,
            recentTokenDelta,
            latestReset is { } resetAt && current - resetAt <= _options.RefreshedDuration);
    }

    public static bool IsReset(
        UsageHistorySnapshot previous,
        UsageHistorySnapshot current,
        double threshold = 15)
    {
        ArgumentNullException.ThrowIfNull(previous);
        ArgumentNullException.ThrowIfNull(current);
        return previous.Pressure is { } previousPressure
               && current.Pressure is { } currentPressure
               && previousPressure - currentPressure >= threshold;
    }

    private static List<UsageHistorySample> Load(string filePath)
    {
        try
        {
            if (!File.Exists(filePath))
            {
                return [];
            }

            using var stream = new FileStream(
                filePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 64 * 1024,
                FileOptions.SequentialScan);
            return (JsonSerializer.Deserialize<List<UsageHistorySample?>>(stream, SerializerOptions) ?? [])
                .OfType<UsageHistorySample>()
                .OrderBy(sample => sample.Timestamp)
                .ToList();
        }
        catch (Exception exception) when (exception is JsonException || IsFileSystemException(exception))
        {
            return [];
        }
    }

    private static void CleanupTemporaryFiles(string filePath)
    {
        var directory = Path.GetDirectoryName(filePath);
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
        {
            return;
        }

        var pattern = $".{Path.GetFileName(filePath)}.*.tmp";
        try
        {
            foreach (var temporaryPath in Directory.EnumerateFiles(directory, pattern, SearchOption.TopDirectoryOnly))
            {
                try
                {
                    File.Delete(temporaryPath);
                }
                catch (Exception exception) when (IsFileSystemException(exception))
                {
                    // Keep checking other remnants. A later clear/load can retry this path.
                }
            }
        }
        catch (Exception exception) when (IsFileSystemException(exception))
        {
            // History remains usable in memory when cleanup is not permitted.
        }
    }

    private static void DeleteHistoryFilesStrict(string filePath)
    {
        File.Delete(filePath);

        var directory = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrWhiteSpace(directory) && Directory.Exists(directory))
        {
            var pattern = $".{Path.GetFileName(filePath)}.*.tmp";
            foreach (var temporaryPath in Directory.EnumerateFiles(
                         directory,
                         pattern,
                         SearchOption.TopDirectoryOnly))
            {
                File.Delete(temporaryPath);
            }

            if (Directory.EnumerateFiles(directory, pattern, SearchOption.TopDirectoryOnly).Any())
            {
                throw new IOException("One or more temporary history files remain after deletion.");
            }
        }

        if (File.Exists(filePath) || Directory.Exists(filePath))
        {
            throw new IOException("The usage history path remains after deletion.");
        }
    }

    private void Prune(DateTimeOffset now)
    {
        var cutoff = now - _options.RetentionInterval;
        _samples.RemoveAll(sample => sample.Timestamp < cutoff);
        if (_samples.Count > _options.MaximumSamples)
        {
            _samples.RemoveRange(0, _samples.Count - _options.MaximumSamples);
        }
    }

    private void PersistUnderLock()
    {
        string? temporaryPath = null;
        try
        {
            var directory = Path.GetDirectoryName(_filePath)
                            ?? throw new InvalidOperationException("History path has no parent directory.");
            Directory.CreateDirectory(directory);
            temporaryPath = Path.Combine(
                directory,
                $".{Path.GetFileName(_filePath)}.{Guid.NewGuid():N}.tmp");

            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 64 * 1024,
                       FileOptions.SequentialScan))
            {
                JsonSerializer.Serialize(stream, _samples, SerializerOptions);
                stream.Flush(flushToDisk: true);
            }

            File.Move(temporaryPath, _filePath, overwrite: true);
            temporaryPath = null;
            LastPersistenceError = null;
        }
        catch (Exception exception) when (exception is JsonException || IsFileSystemException(exception))
        {
            LastPersistenceError = exception;
        }
        finally
        {
            if (temporaryPath is not null)
            {
                try
                {
                    File.Delete(temporaryPath);
                }
                catch (Exception exception) when (IsFileSystemException(exception))
                {
                    // Best-effort cleanup only. The original persistence error remains authoritative.
                }
            }
        }
    }

    private static bool IsFileSystemException(Exception exception) => exception is
        IOException or
        UnauthorizedAccessException or
        NotSupportedException or
        System.Security.SecurityException;
}
