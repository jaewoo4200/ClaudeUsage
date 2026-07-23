using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;
using WpfApplication = System.Windows.Application;

namespace ClaudeUsage.Windows.ViewModels;

public enum UsageHistoryRange
{
    Hour,
    Day,
    Week,
    TwoWeeks,
}

public enum UsageHistoryProviderScope
{
    All,
    Claude,
    Codex,
}

public sealed record UsageHistoryOption<T>(T Value, string Label);

public sealed record UsageHistoryChartPoint(DateTimeOffset Timestamp, double Utilization);

public sealed record UsageHistoryChartSeries(
    string Id,
    string Label,
    UsageProvider Provider,
    Brush Brush,
    IReadOnlyList<UsageHistoryChartPoint> Points);

public sealed class UsageHistoryDashboardViewModel : INotifyPropertyChanged, IDisposable
{
    private static readonly string[] Palette =
    [
        "#FF0A84FF",
        "#FF2DBE60",
        "#FFFF8A26",
        "#FFC52DD7",
        "#FFFF3441",
        "#FF00A7A7",
        "#FFFFB000",
        "#FF6B68FF",
    ];

    private readonly UsageHistoryService _history;
    private readonly AppSettings _settings;
    private UsageHistoryRange _range = UsageHistoryRange.Day;
    private UsageHistoryProviderScope _scope = UsageHistoryProviderScope.All;
    private string _peakText = "—";
    private string _changeText = "—";
    private string _sampleCountText = "0";
    private string _resetCountText = "0";
    private bool _hasChartData;
    private bool _hasSamples;
    private bool _isChangeNonNegative = true;
    private bool _hasDetectedResets;
    private bool _disposed;

    public UsageHistoryDashboardViewModel(UsageHistoryService history, AppSettings settings)
    {
        _history = history ?? throw new ArgumentNullException(nameof(history));
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));
        _history.Store.Changed += OnHistoryStoreChanged;
        _settings.PropertyChanged += OnSettingsPropertyChanged;
        ThemeResourceManager.ResourcesChanged += OnResourcesChanged;
        RebuildOptions();
        Refresh();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<UsageHistoryOption<UsageHistoryRange>> RangeOptions { get; private set; } = [];

    public IReadOnlyList<UsageHistoryOption<UsageHistoryProviderScope>> ScopeOptions { get; private set; } = [];

    public IReadOnlyList<UsageHistoryChartSeries> Series { get; private set; } = [];

    public UsageHistoryRange Range
    {
        get => _range;
        set
        {
            if (!SetField(ref _range, value))
            {
                return;
            }

            Refresh();
        }
    }

    public UsageHistoryProviderScope Scope
    {
        get => _scope;
        set
        {
            if (!SetField(ref _scope, value))
            {
                return;
            }

            Refresh();
        }
    }

    public string PeakText
    {
        get => _peakText;
        private set => SetField(ref _peakText, value);
    }

    public string ChangeText
    {
        get => _changeText;
        private set => SetField(ref _changeText, value);
    }

    public string SampleCountText
    {
        get => _sampleCountText;
        private set => SetField(ref _sampleCountText, value);
    }

    public string ResetCountText
    {
        get => _resetCountText;
        private set => SetField(ref _resetCountText, value);
    }

    public bool HasChartData
    {
        get => _hasChartData;
        private set => SetField(ref _hasChartData, value);
    }

    public bool HasSamples
    {
        get => _hasSamples;
        private set => SetField(ref _hasSamples, value);
    }

    public bool IsChangeNonNegative
    {
        get => _isChangeNonNegative;
        private set => SetField(ref _isChangeNonNegative, value);
    }

    public bool HasDetectedResets
    {
        get => _hasDetectedResets;
        private set => SetField(ref _hasDetectedResets, value);
    }

    public bool IsTrackingDisabled => !_settings.UsageHistoryEnabled;

    public void Refresh()
    {
        var cutoff = DateTimeOffset.Now - RangeInterval(Range);
        var samples = _history.Samples
            .Where(sample => sample is not null && sample.Timestamp >= cutoff)
            .OrderBy(sample => sample.Timestamp)
            .ToArray();

        var pressures = samples
            .Select(sample => Pressure(sample, Scope))
            .OfType<double>()
            .ToArray();
        var peak = pressures.Length == 0 ? (double?)null : pressures.Max();
        var delta = pressures.Length > 1 ? pressures[^1] - pressures[0] : (double?)null;
        var resets = CountResets(samples, Scope);

        PeakText = peak is { } peakValue
            ? string.Format(T("History.PercentFormat", "{0:0}%"), peakValue)
            : "—";
        ChangeText = delta is { } deltaValue
            ? string.Format(CultureInfo.CurrentCulture, "{0:+0.0;-0.0;0.0}%p", deltaValue)
            : "—";
        IsChangeNonNegative = delta is null || delta >= 0;
        SampleCountText = samples.Length.ToString("N0", CultureInfo.CurrentCulture);
        ResetCountText = resets.ToString("N0", CultureInfo.CurrentCulture);
        HasDetectedResets = resets > 0;
        HasSamples = _history.Store.HasSamples;

        Series = BuildSeries(samples, Scope);
        HasChartData = Series.Any(series => series.Points.Count > 0);
        OnPropertyChanged(nameof(Series));
        OnPropertyChanged(nameof(IsTrackingDisabled));
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _history.Store.Changed -= OnHistoryStoreChanged;
        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        ThemeResourceManager.ResourcesChanged -= OnResourcesChanged;
        GC.SuppressFinalize(this);
    }

    private void RebuildOptions()
    {
        RangeOptions =
        [
            new(UsageHistoryRange.Hour, T("History.Range.Hour", "1 hour")),
            new(UsageHistoryRange.Day, T("History.Range.Day", "24 hours")),
            new(UsageHistoryRange.Week, T("History.Range.Week", "7 days")),
            new(UsageHistoryRange.TwoWeeks, T("History.Range.TwoWeeks", "14 days")),
        ];
        ScopeOptions =
        [
            new(UsageHistoryProviderScope.All, T("History.Scope.All", "All")),
            new(UsageHistoryProviderScope.Claude, "Claude"),
            new(UsageHistoryProviderScope.Codex, "Codex"),
        ];
        OnPropertyChanged(nameof(RangeOptions));
        OnPropertyChanged(nameof(ScopeOptions));
    }

    private IReadOnlyList<UsageHistoryChartSeries> BuildSeries(
        IReadOnlyList<UsageHistorySample> samples,
        UsageHistoryProviderScope scope)
    {
        var builders = new Dictionary<string, SeriesBuilder>(StringComparer.Ordinal);
        foreach (var sample in samples)
        {
            if (Includes(scope, UsageProvider.Claude))
            {
                Add(builders, sample.Timestamp, "claude-five-hour", T("History.Series.ClaudeFive", "Claude · 5 hours"), UsageProvider.Claude, sample.ClaudeFiveHour);
                Add(builders, sample.Timestamp, "claude-weekly", T("History.Series.ClaudeWeekly", "Claude · Weekly"), UsageProvider.Claude, sample.ClaudeWeekly);
            }

            if (Includes(scope, UsageProvider.Codex))
            {
                Add(builders, sample.Timestamp, "codex-five-hour", T("History.Series.CodexFive", "Codex · 5 hours"), UsageProvider.Codex, sample.OpenAIFiveHour);
                Add(builders, sample.Timestamp, "codex-weekly", T("History.Series.CodexWeekly", "Codex · Weekly"), UsageProvider.Codex, sample.OpenAIWeekly);
            }

            // Match the SwiftUI chart's palette order: the four provider
            // windows are inserted first, followed by model-specific series.
            if (Includes(scope, UsageProvider.Claude))
            {
                if (sample.ClaudeModelCounters is { Length: > 0 })
                {
                    foreach (var counter in sample.ClaudeModelCounters.Where(IsUsable))
                    {
                        Add(builders, sample.Timestamp, $"claude-{counter.Id}", counter.Label, UsageProvider.Claude, counter.Utilization);
                    }
                }
                else
                {
                    Add(builders, sample.Timestamp, "claude-model", T("History.Series.ClaudeModel", "Claude · Model"), UsageProvider.Claude, sample.ClaudeModelMaximum);
                }
            }

            if (Includes(scope, UsageProvider.Codex))
            {
                if (sample.OpenAIModelCounters is { Length: > 0 })
                {
                    foreach (var counter in sample.OpenAIModelCounters.Where(IsUsable))
                    {
                        Add(builders, sample.Timestamp, $"codex-{counter.Id}", counter.Label, UsageProvider.Codex, counter.Utilization);
                    }
                }
                else
                {
                    Add(builders, sample.Timestamp, "codex-model", T("History.Series.CodexModel", "Codex · Model"), UsageProvider.Codex, sample.OpenAIModelMaximum);
                }
            }
        }

        var index = 0;
        return builders.Values
            .Select(builder => new UsageHistoryChartSeries(
                builder.Id,
                builder.Label,
                builder.Provider,
                FrozenBrush(Palette[index++ % Palette.Length]),
                builder.Points.AsReadOnly()))
            .ToArray();
    }

    private static void Add(
        IDictionary<string, SeriesBuilder> builders,
        DateTimeOffset timestamp,
        string id,
        string label,
        UsageProvider provider,
        double? value)
    {
        if (value is not { } utilization || !double.IsFinite(utilization))
        {
            return;
        }

        if (!builders.TryGetValue(id, out var builder))
        {
            builder = new SeriesBuilder(id, label, provider);
            builders.Add(id, builder);
        }

        builder.Points.Add(new UsageHistoryChartPoint(timestamp, Math.Clamp(utilization, 0, 100)));
    }

    private static double? Pressure(UsageHistorySample sample, UsageHistoryProviderScope scope)
    {
        var values = new List<double>();
        var snapshot = sample.Snapshot;
        if (Includes(scope, UsageProvider.Claude))
        {
            Append(values, snapshot.ClaudeFiveHour, snapshot.ClaudeWeekly);
            if (snapshot.ClaudeModelCounters.Count > 0)
            {
                values.AddRange(snapshot.ClaudeModelCounters.Where(IsUsable).Select(counter => counter.Utilization));
            }
            else
            {
                Append(values, snapshot.ClaudeModelMaximum);
            }
        }

        if (Includes(scope, UsageProvider.Codex))
        {
            Append(values, snapshot.OpenAIFiveHour, snapshot.OpenAIWeekly);
            if (snapshot.OpenAIModelCounters.Count > 0)
            {
                values.AddRange(snapshot.OpenAIModelCounters.Where(IsUsable).Select(counter => counter.Utilization));
            }
            else
            {
                Append(values, snapshot.OpenAIModelMaximum);
            }
        }

        return values.Count == 0 ? null : values.Max();
    }

    private static int CountResets(IReadOnlyList<UsageHistorySample> samples, UsageHistoryProviderScope scope)
    {
        var resets = 0;
        for (var index = 1; index < samples.Count; index++)
        {
            var previous = Pressure(samples[index - 1], scope);
            var current = Pressure(samples[index], scope);
            if (previous is { } previousValue
                && current is { } currentValue
                && previousValue - currentValue >= 15)
            {
                resets++;
            }
        }

        return resets;
    }

    private void OnHistoryStoreChanged(object? sender, EventArgs e) => DispatchRefresh();

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppSettings.UsageHistoryEnabled))
        {
            Dispatch(() => OnPropertyChanged(nameof(IsTrackingDisabled)));
        }
    }

    private void OnResourcesChanged(object? sender, EventArgs e)
    {
        void Relocalize()
        {
            RebuildOptions();
            Refresh();
        }

        Dispatch(Relocalize);
    }

    private void DispatchRefresh() => Dispatch(Refresh);

    private void Dispatch(Action action)
    {
        if (_disposed)
        {
            return;
        }

        void RunIfActive()
        {
            if (!_disposed)
            {
                action();
            }
        }

        var dispatcher = WpfApplication.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            RunIfActive();
        }
        else
        {
            _ = dispatcher.BeginInvoke(RunIfActive);
        }
    }

    private static bool Includes(UsageHistoryProviderScope scope, UsageProvider provider) => scope switch
    {
        UsageHistoryProviderScope.All => true,
        UsageHistoryProviderScope.Claude => provider == UsageProvider.Claude,
        UsageHistoryProviderScope.Codex => provider == UsageProvider.Codex,
        _ => false,
    };

    private static bool IsUsable(UsageHistoryCounter counter) =>
        counter is not null
        && !string.IsNullOrWhiteSpace(counter.Id)
        && double.IsFinite(counter.Utilization);

    private static void Append(ICollection<double> values, params double?[] candidates)
    {
        foreach (var value in candidates)
        {
            if (value is { } utilization && double.IsFinite(utilization))
            {
                values.Add(utilization);
            }
        }
    }

    private static TimeSpan RangeInterval(UsageHistoryRange range) => range switch
    {
        UsageHistoryRange.Hour => TimeSpan.FromHours(1),
        UsageHistoryRange.Day => TimeSpan.FromDays(1),
        UsageHistoryRange.Week => TimeSpan.FromDays(7),
        UsageHistoryRange.TwoWeeks => TimeSpan.FromDays(14),
        _ => TimeSpan.FromDays(1),
    };

    private static Brush FrozenBrush(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    private static string T(string key, string fallback) => ThemeResourceManager.GetString(key, fallback);

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private sealed class SeriesBuilder(string id, string label, UsageProvider provider)
    {
        public string Id { get; } = id;

        public string Label { get; } = label;

        public UsageProvider Provider { get; } = provider;

        public List<UsageHistoryChartPoint> Points { get; } = [];
    }
}
