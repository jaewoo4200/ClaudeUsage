using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.ViewModels;

public enum WidgetProviderKind
{
    Claude,
    Codex,
}

public enum WidgetPanelKind
{
    Combined,
    Claude,
    Codex,
}

public enum WidgetUsageLevel
{
    Normal,
    Warning,
    Danger,
}

public sealed record WidgetMetricViewModel(
    string Id,
    string Title,
    string WindowLabel,
    double Percent,
    string ResetText)
{
    public double ClampedPercent => Math.Clamp(Percent, 0, 100);

    public string PercentageText => $"{ClampedPercent:0}%";

    public WidgetUsageLevel Level => ClampedPercent switch
    {
        >= 90 => WidgetUsageLevel.Danger,
        >= 70 => WidgetUsageLevel.Warning,
        _ => WidgetUsageLevel.Normal,
    };

    public string AccessibleName => $"{Title}, {WindowLabel}, {PercentageText}, {ResetText}";
}

public sealed class ProviderWidgetViewModel : INotifyPropertyChanged
{
    private string _planBadge = "—";
    private string _planCompactBadge = "—";
    private string _headerStatusText = string.Empty;
    private string _statusText = string.Empty;
    private string _tokensToday = "–";
    private string _resetCredits = "–";
    private bool _isConnected;
    private ProviderLoadState _loadState = ProviderLoadState.NeedsLogin;

    public ProviderWidgetViewModel(WidgetProviderKind provider)
    {
        Provider = provider;
        DisplayName = provider == WidgetProviderKind.Claude ? "Claude" : "Codex";
        Glyph = provider == WidgetProviderKind.Claude ? "C" : "X";
        Metrics.CollectionChanged += OnMetricsCollectionChanged;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public WidgetProviderKind Provider { get; }

    public string DisplayName { get; }

    public string UpperDisplayName => DisplayName.ToUpperInvariant();

    public string Glyph { get; }

    public bool IsClaude => Provider == WidgetProviderKind.Claude;

    public ObservableCollection<WidgetMetricViewModel> Metrics { get; } = [];

    public string PlanBadge
    {
        get => _planBadge;
        set => SetField(ref _planBadge, string.IsNullOrWhiteSpace(value) ? "—" : value);
    }

    public string PlanCompactBadge
    {
        get => _planCompactBadge;
        set => SetField(ref _planCompactBadge, string.IsNullOrWhiteSpace(value) ? "—" : value);
    }

    public string StatusText
    {
        get => _statusText;
        set
        {
            if (SetField(ref _statusText, value ?? string.Empty))
            {
                OnPropertyChanged(nameof(HasStatus));
            }
        }
    }

    public string HeaderStatusText
    {
        get => _headerStatusText;
        set => SetField(ref _headerStatusText, value ?? string.Empty);
    }

    public string TokensToday
    {
        get => _tokensToday;
        set => SetField(ref _tokensToday, string.IsNullOrWhiteSpace(value) ? "–" : value);
    }

    public string ResetCredits
    {
        get => _resetCredits;
        set => SetField(ref _resetCredits, string.IsNullOrWhiteSpace(value) ? "–" : value);
    }

    public bool IsConnected
    {
        get => _isConnected;
        set => SetField(ref _isConnected, value);
    }

    public ProviderLoadState LoadState
    {
        get => _loadState;
        set
        {
            if (!SetField(ref _loadState, value))
            {
                return;
            }

            OnPropertyChanged(nameof(IsLoading));
            OnPropertyChanged(nameof(HasError));
            OnPropertyChanged(nameof(NeedsLogin));
            OnPropertyChanged(nameof(IsUnavailable));
            OnPropertyChanged(nameof(IsLoaded));
            OnPropertyChanged(nameof(NeedsAction));
            OnPropertyChanged(nameof(HasStatus));
        }
    }

    public bool IsLoading => LoadState == ProviderLoadState.Loading;

    public bool HasError => LoadState == ProviderLoadState.Error;

    public bool NeedsLogin => LoadState == ProviderLoadState.NeedsLogin;

    public bool IsUnavailable => LoadState == ProviderLoadState.Unavailable;

    public bool IsLoaded => LoadState == ProviderLoadState.Loaded;

    public bool NeedsAction => NeedsLogin || IsUnavailable;

    public bool HasMetrics => Metrics.Count > 0;

    public bool HasStatus => !HasMetrics && !IsLoading && !string.IsNullOrWhiteSpace(StatusText);

    public bool HasSupplementaryData => Provider == WidgetProviderKind.Codex
                                        && (TokensToday != "–" || ResetCredits != "–");

    public void ReplaceMetrics(IEnumerable<WidgetMetricViewModel> metrics)
    {
        Metrics.Clear();
        foreach (var metric in metrics)
        {
            Metrics.Add(metric);
        }
    }

    public void NotifySupplementaryDataChanged() =>
        OnPropertyChanged(nameof(HasSupplementaryData));

    private void OnMetricsCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        OnPropertyChanged(nameof(HasMetrics));
        OnPropertyChanged(nameof(HasStatus));
    }

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

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

/// <summary>
/// Presentation adapter for floating widgets. Codex is synchronized from the
/// existing UsageViewModel. Phase 3 can feed Claude independently through
/// ApplyClaude without coupling either provider's state to the other.
/// </summary>
public sealed class WidgetViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly UsageViewModel _usageViewModel;
    private readonly AppSettings _settings;
    private WidgetProviderKind _pagedProviderKind = WidgetProviderKind.Claude;
    private bool _disposed;

    public WidgetViewModel(
        UsageViewModel usageViewModel,
        AppSettings settings,
        CompanionViewModel companionViewModel)
    {
        _usageViewModel = usageViewModel;
        _settings = settings;
        Companion = companionViewModel ?? throw new ArgumentNullException(nameof(companionViewModel));
        Claude = new ProviderWidgetViewModel(WidgetProviderKind.Claude)
        {
            StatusText = Text("Widget.ClaudeNeedsLogin", "Sign in to Claude to see usage."),
        };
        Codex = new ProviderWidgetViewModel(WidgetProviderKind.Codex);
        PreviousProviderCommand = new WidgetRelayCommand(ToggleProvider);
        NextProviderCommand = new WidgetRelayCommand(ToggleProvider);

        _usageViewModel.PropertyChanged += OnUsagePropertyChanged;
        _usageViewModel.Counters.CollectionChanged += OnUsageCountersChanged;
        _usageViewModel.ClaudeCounters.CollectionChanged += OnUsageCountersChanged;
        _settings.PropertyChanged += OnSettingsPropertyChanged;
        Companion.PropertyChanged += OnCompanionPropertyChanged;
        ThemeResourceManager.ResourcesChanged += OnResourcesChanged;
        SyncClaude();
        SyncCodex();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ProviderWidgetViewModel Claude { get; }

    public ProviderWidgetViewModel Codex { get; }

    public CompanionViewModel Companion { get; }

    public WidgetProviderKind PagedProviderKind
    {
        get => _pagedProviderKind;
        set
        {
            if (SetField(ref _pagedProviderKind, value))
            {
                OnPropertyChanged(nameof(PagedProvider));
                OnPropertyChanged(nameof(IsClaudePage));
                OnPropertyChanged(nameof(IsCodexPage));
                OnPropertyChanged(nameof(PagedProviderName));
            }
        }
    }

    public ProviderWidgetViewModel PagedProvider =>
        PagedProviderKind == WidgetProviderKind.Claude ? Claude : Codex;

    public string PagedProviderName => PagedProvider.DisplayName;

    public bool IsClaudePage => PagedProviderKind == WidgetProviderKind.Claude;

    public bool IsCodexPage => PagedProviderKind == WidgetProviderKind.Codex;

    public WidgetLayoutMode Layout => _settings.WidgetLayout;

    public bool IsStackedLayout => Layout is WidgetLayoutMode.Stacked or WidgetLayoutMode.Separate;

    public bool IsHorizontalLayout => Layout == WidgetLayoutMode.Horizontal;

    public bool IsPagedLayout => Layout == WidgetLayoutMode.Paged;

    public bool ShowCompanion => _settings.CompanionEnabled;

    public string CompanionName => _settings.SelectedCompanion.ToString();

    public string CompanionGlyph => CompanionName[..1];

    public ICommand PreviousProviderCommand { get; }

    public ICommand NextProviderCommand { get; }

    public string HeadroomLabel => Localized("최소 여유", "Headroom");

    public string NextResetLabel => Localized("다음 초기화", "Next reset");

    public string ResetCreditsLabel => Localized("초기화권", "Reset passes");

    public string RecentActivityLabel => Localized("최근 1시간", "Recent activity");

    public string TokensTodayLabel => Localized("오늘 토큰", "Tokens today");

    public string HeadroomText => Companion.RemainingText;

    public WidgetUsageLevel HeadroomLevel => Companion.Pressure switch
    {
        >= 90 => WidgetUsageLevel.Danger,
        >= 70 => WidgetUsageLevel.Warning,
        _ => WidgetUsageLevel.Normal,
    };

    public string NextResetSummary
    {
        get
        {
            var candidate = Claude.Metrics
                .Select(metric => (Provider: Claude.DisplayName, Metric: metric))
                .Concat(Codex.Metrics.Select(metric => (Provider: Codex.DisplayName, Metric: metric)))
                .FirstOrDefault(item => !IsPlaceholder(item.Metric.ResetText));
            return candidate.Metric is null
                ? "-"
                : $"{candidate.Provider} {candidate.Metric.ResetText}";
        }
    }

    public string ResetCreditsSummary => Codex.ResetCredits;

    public bool HasResetCredits => !IsPlaceholder(Codex.ResetCredits);

    public string RecentActivitySummary => Companion.DetailText;

    public string TokensTodaySummary => !IsPlaceholder(Codex.TokensToday)
        ? Codex.TokensToday
        : Claude.TokensToday;

    public void ApplyClaude(
        string? planDisplayName,
        IEnumerable<WidgetMetricViewModel>? metrics,
        bool isConnected,
        string? statusText = null)
    {
        Claude.PlanBadge = planDisplayName ?? "—";
        Claude.PlanCompactBadge = (planDisplayName ?? "—").ToUpperInvariant();
        Claude.IsConnected = isConnected;
        Claude.LoadState = isConnected ? ProviderLoadState.Loaded : ProviderLoadState.NeedsLogin;
        Claude.HeaderStatusText = isConnected
            ? Localized("로그인됨", "Signed in")
            : Localized("메뉴바에서 로그인해 주세요", "Please sign in from the menu bar");
        Claude.StatusText = statusText ?? (isConnected
            ? string.Empty
            : Text("Widget.ClaudeNeedsLogin", "Sign in to Claude to see usage."));
        Claude.ReplaceMetrics(metrics ?? []);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _usageViewModel.PropertyChanged -= OnUsagePropertyChanged;
        _usageViewModel.Counters.CollectionChanged -= OnUsageCountersChanged;
        _usageViewModel.ClaudeCounters.CollectionChanged -= OnUsageCountersChanged;
        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        Companion.PropertyChanged -= OnCompanionPropertyChanged;
        ThemeResourceManager.ResourcesChanged -= OnResourcesChanged;
        GC.SuppressFinalize(this);
    }

    private void ToggleProvider() => PagedProviderKind = PagedProviderKind == WidgetProviderKind.Claude
        ? WidgetProviderKind.Codex
        : WidgetProviderKind.Claude;

    private void SyncCodex()
    {
        var loadState = ResolveCodexLoadState();
        Codex.PlanBadge = _usageViewModel.PlanDisplayName;
        Codex.PlanCompactBadge = _usageViewModel.LastCodexSnapshot?.PlanCompactName
                                 ?? _usageViewModel.PlanDisplayName.ToUpperInvariant();
        Codex.IsConnected = _usageViewModel.HasSnapshot;
        Codex.LoadState = loadState;
        Codex.HeaderStatusText = loadState switch
        {
            ProviderLoadState.Loaded =>
                Localized("자동 연결됨", "Connected automatically"),
            ProviderLoadState.Loading => Localized("불러오는 중…", "Loading…"),
            ProviderLoadState.Unavailable =>
                Localized("ChatGPT 또는 Codex 앱 로그인이 필요해요", "Sign in to the ChatGPT or Codex app"),
            ProviderLoadState.Error => Localized("불러오기 실패", "Load failed"),
            _ => string.Empty,
        };
        Codex.StatusText = loadState switch
        {
            ProviderLoadState.Loaded when _usageViewModel.Counters.Count == 0 =>
                Text("Widget.NoData", "No usage limits are available."),
            ProviderLoadState.Unavailable =>
                Text("Widget.CodexNotConnected", "Codex isn't connected."),
            ProviderLoadState.Error =>
                Text("Widget.LoadFailed", "Failed to load usage."),
            _ => _usageViewModel.StatusText,
        };
        Codex.TokensToday = _usageViewModel.TokensTodayText;
        Codex.ResetCredits = _usageViewModel.ResetCreditsText;
        Codex.NotifySupplementaryDataChanged();
        Codex.ReplaceMetrics(_usageViewModel.Counters.Select(counter => new WidgetMetricViewModel(
            counter.Id,
            counter.Title,
            counter.WindowLabel,
            counter.ClampedPercent,
            counter.ResetText)));
        NotifyHorizontalSummaryChanged();
    }

    private void SyncClaude()
    {
        var loadState = _usageViewModel.ClaudeState;
        Claude.PlanBadge = _usageViewModel.ClaudePlanDisplayName;
        Claude.PlanCompactBadge = _usageViewModel.LastClaudeSnapshot?.Organization.Plan.CompactName()
                                  ?? _usageViewModel.ClaudePlanDisplayName.ToUpperInvariant();
        Claude.IsConnected = _usageViewModel.ClaudeHasSnapshot;
        Claude.LoadState = loadState;
        Claude.HeaderStatusText = loadState switch
        {
            ProviderLoadState.Loaded => Localized("로그인됨", "Signed in"),
            ProviderLoadState.Loading => Localized("불러오는 중…", "Loading…"),
            ProviderLoadState.NeedsLogin =>
                Localized("메뉴바에서 로그인해 주세요", "Please sign in from the menu bar"),
            ProviderLoadState.Error => Localized("불러오기 실패", "Load failed"),
            _ => string.Empty,
        };
        Claude.StatusText = loadState switch
        {
            ProviderLoadState.NeedsLogin =>
                Text("Widget.ClaudeNeedsLogin", "Sign in to Claude to see usage."),
            ProviderLoadState.Error =>
                Text("Widget.LoadFailed", "Failed to load usage."),
            ProviderLoadState.Loaded when _usageViewModel.ClaudeCounters.Count == 0 => string.Empty,
            _ => _usageViewModel.ClaudeStatusText,
        };
        Claude.TokensToday = _usageViewModel.ClaudeTokensTodayText;
        Claude.NotifySupplementaryDataChanged();
        Claude.ReplaceMetrics(_usageViewModel.ClaudeCounters.Select(counter => new WidgetMetricViewModel(
            counter.Id,
            counter.Title,
            counter.WindowLabel,
            counter.ClampedPercent,
            counter.ResetText)));
        NotifyHorizontalSummaryChanged();
    }

    private ProviderLoadState ResolveCodexLoadState()
    {
        if (_usageViewModel.HasSnapshot)
        {
            return ProviderLoadState.Loaded;
        }

        if (_usageViewModel.NeedsSetup)
        {
            return ProviderLoadState.Unavailable;
        }

        if (_usageViewModel.HasError)
        {
            return ProviderLoadState.Error;
        }

        return ProviderLoadState.Loading;
    }

    private void OnUsagePropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        SyncClaude();
        SyncCodex();
    }

    private void OnUsageCountersChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        SyncClaude();
        SyncCodex();
    }

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppSettings.WidgetLayout))
        {
            OnPropertyChanged(nameof(Layout));
            OnPropertyChanged(nameof(IsStackedLayout));
            OnPropertyChanged(nameof(IsHorizontalLayout));
            OnPropertyChanged(nameof(IsPagedLayout));
        }
        else if (e.PropertyName == nameof(AppSettings.CompanionEnabled))
        {
            OnPropertyChanged(nameof(ShowCompanion));
        }
        else if (e.PropertyName == nameof(AppSettings.SelectedCompanion))
        {
            OnPropertyChanged(nameof(CompanionName));
            OnPropertyChanged(nameof(CompanionGlyph));
        }
        else if (e.PropertyName == nameof(AppSettings.Language))
        {
            SyncClaude();
            SyncCodex();
            OnPropertyChanged(nameof(HeadroomLabel));
            OnPropertyChanged(nameof(NextResetLabel));
            OnPropertyChanged(nameof(ResetCreditsLabel));
            OnPropertyChanged(nameof(RecentActivityLabel));
            OnPropertyChanged(nameof(TokensTodayLabel));
        }
    }

    private void OnCompanionPropertyChanged(object? sender, PropertyChangedEventArgs e) =>
        NotifyHorizontalSummaryChanged();

    private void NotifyHorizontalSummaryChanged()
    {
        OnPropertyChanged(nameof(HeadroomText));
        OnPropertyChanged(nameof(HeadroomLevel));
        OnPropertyChanged(nameof(NextResetSummary));
        OnPropertyChanged(nameof(ResetCreditsSummary));
        OnPropertyChanged(nameof(HasResetCredits));
        OnPropertyChanged(nameof(RecentActivitySummary));
        OnPropertyChanged(nameof(TokensTodaySummary));
    }

    private string Localized(string korean, string english) =>
        _settings.Language == AppLanguage.Korean ? korean : english;

    private static bool IsPlaceholder(string? value) =>
        string.IsNullOrWhiteSpace(value) || value is "-" or "—";

    private void OnResourcesChanged(object? sender, EventArgs e)
    {
        SyncClaude();
        SyncCodex();
    }

    private static string Text(string key, string fallback) =>
        ThemeResourceManager.GetString(key, fallback);

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

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

internal sealed class WidgetRelayCommand(Action execute) : ICommand
{
    public event EventHandler? CanExecuteChanged
    {
        add { }
        remove { }
    }

    public bool CanExecute(object? parameter) => true;

    public void Execute(object? parameter) => execute();
}
