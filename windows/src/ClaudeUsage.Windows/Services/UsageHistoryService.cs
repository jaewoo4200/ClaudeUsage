using ClaudeUsage.Core.History;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Windows.Services;

public sealed record UsageHistorySampleResult(
    bool HistoryEnabled,
    bool Recorded,
    UsageHistorySnapshot Snapshot,
    UsageTrend Trend,
    ClaudeLocalTokenUsage? ClaudeLocalTokens);

/// <summary>
/// Opt-in coordinator for history sampling and the privacy-sensitive Claude Code log scan.
/// </summary>
public sealed class UsageHistoryService
{
    public static readonly TimeSpan DefaultLocalTokenScanInterval = TimeSpan.FromMinutes(5);

    private readonly SemaphoreSlim _sampleGate = new(1, 1);
    private readonly object _scanCancellationGate = new();
    private readonly UsageHistoryStore _store;
    private readonly IClaudeLocalTokenUsageService _localTokenService;
    private readonly TimeSpan _localTokenScanInterval;
    private DateTimeOffset? _lastLocalTokenScanAt;
    private ClaudeLocalTokenUsage? _lastLocalTokenUsage;
    private CancellationTokenSource? _activeScanCancellation;
    private volatile bool _isEnabled;

    public UsageHistoryService(
        UsageHistoryStore? store = null,
        IClaudeLocalTokenUsageService? localTokenService = null,
        TimeSpan? localTokenScanInterval = null)
    {
        _store = store ?? new UsageHistoryStore();
        _localTokenService = localTokenService ?? new ClaudeLocalTokenUsageService();
        _localTokenScanInterval = localTokenScanInterval ?? DefaultLocalTokenScanInterval;
        if (_localTokenScanInterval <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(localTokenScanInterval));
        }
    }

    public event EventHandler<UsageHistorySampleResult>? Sampled;

    /// <summary>
    /// False until the user's persisted opt-in setting is explicitly applied.
    /// </summary>
    public bool IsEnabled => _isEnabled;

    public UsageHistoryStore Store => _store;

    public IReadOnlyList<UsageHistorySample> Samples => _store.Samples;

    public ClaudeLocalTokenUsage? LastClaudeLocalTokenUsage => _lastLocalTokenUsage;

    public void SetEnabled(bool enabled)
    {
        _isEnabled = enabled;
        if (!enabled)
        {
            lock (_scanCancellationGate)
            {
                _activeScanCancellation?.Cancel();
            }
            _lastLocalTokenScanAt = null;
            _lastLocalTokenUsage = null;
        }
    }

    /// <summary>
    /// Samples only when opted in. Claude JSONL scanning is gated by the same setting and five-minute cadence.
    /// </summary>
    public async Task<UsageHistorySampleResult> SampleAsync(
        UsageHistorySnapshot snapshot,
        DateTimeOffset? now = null,
        bool force = false,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var sampledAt = now ?? DateTimeOffset.Now;

        if (!_isEnabled)
        {
            return new UsageHistorySampleResult(false, false, snapshot, UsageTrend.Empty, null);
        }

        await _sampleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        UsageHistorySampleResult result;
        try
        {
            if (!_isEnabled)
            {
                return new UsageHistorySampleResult(false, false, snapshot, UsageTrend.Empty, null);
            }

            if (ShouldScanLocalTokens(sampledAt))
            {
                using var scanCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                lock (_scanCancellationGate)
                {
                    if (!_isEnabled)
                    {
                        return new UsageHistorySampleResult(false, false, snapshot, UsageTrend.Empty, null);
                    }

                    _activeScanCancellation = scanCancellation;
                }

                ClaudeLocalTokenUsage? scannedUsage;
                try
                {
                    scannedUsage = await _localTokenService
                        .FetchAsync(sampledAt, scanCancellation.Token)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (
                    !cancellationToken.IsCancellationRequested
                    && scanCancellation.IsCancellationRequested)
                {
                    return new UsageHistorySampleResult(
                        _isEnabled,
                        false,
                        snapshot,
                        UsageTrend.Empty,
                        null);
                }
                finally
                {
                    lock (_scanCancellationGate)
                    {
                        if (ReferenceEquals(_activeScanCancellation, scanCancellation))
                        {
                            _activeScanCancellation = null;
                        }
                    }
                }

                if (!_isEnabled)
                {
                    return new UsageHistorySampleResult(false, false, snapshot, UsageTrend.Empty, null);
                }

                _lastLocalTokenScanAt = sampledAt;
                _lastLocalTokenUsage = scannedUsage;
            }

            if (!_isEnabled)
            {
                return new UsageHistorySampleResult(false, false, snapshot, UsageTrend.Empty, null);
            }

            var localUsage = IsCurrentCalendarDay(_lastLocalTokenUsage, sampledAt)
                ? _lastLocalTokenUsage
                : null;
            var enrichedSnapshot = localUsage is null
                ? snapshot
                : snapshot.WithClaudeTodayTokens(localUsage.TodayTokens);

            var recorded = _store.Record(enrichedSnapshot, sampledAt, force);
            result = new UsageHistorySampleResult(
                true,
                recorded,
                enrichedSnapshot,
                _store.Trend(sampledAt),
                localUsage);
        }
        finally
        {
            _sampleGate.Release();
        }

        Sampled?.Invoke(this, result);
        return result;
    }

    public UsageTrend Trend(DateTimeOffset? now = null) =>
        _isEnabled ? _store.Trend(now) : UsageTrend.Empty;

    public async Task ClearAsync(CancellationToken cancellationToken = default)
    {
        lock (_scanCancellationGate)
        {
            _activeScanCancellation?.Cancel();
        }

        await _sampleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            _store.Clear();
            _lastLocalTokenScanAt = null;
            _lastLocalTokenUsage = null;
        }
        finally
        {
            _sampleGate.Release();
        }
    }

    private bool ShouldScanLocalTokens(DateTimeOffset now) =>
        _lastLocalTokenScanAt is not { } previous
        || now < previous
        || now - previous >= _localTokenScanInterval;

    private static bool IsCurrentCalendarDay(ClaudeLocalTokenUsage? usage, DateTimeOffset now) =>
        usage is not null
        && DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(usage.UpdatedAt, TimeZoneInfo.Local).DateTime)
        == DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, TimeZoneInfo.Local).DateTime);
}
