using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.ViewModels;

public enum ProviderLoadState
{
    NeedsLogin,
    Unavailable,
    Loading,
    Loaded,
    Error,
}

public sealed class UsageViewModel : INotifyPropertyChanged
{
    private readonly AppSettings _settings;
    private OpenAIUsageData? _lastCodexSnapshot;
    private ClaudeAccountSnapshot? _lastClaudeSnapshot;
    private DateTimeOffset? _lastCodexUpdatedAt;
    private DateTimeOffset? _lastClaudeUpdatedAt;
    private long? _claudeTodayTokens;
    private string _planDisplayName = "—";
    private string _statusText;
    private string _statusDetail;
    private string _lastUpdatedText;
    private string _tokensTodayText = "—";
    private string _resetCreditsText = "—";
    private bool _isRefreshing;
    private bool _hasSnapshot;
    private bool _hasError;
    private bool _needsSetup;
    private bool _claudeIsRefreshing;
    private ProviderLoadState _claudeState = ProviderLoadState.NeedsLogin;
    private string _claudePlanDisplayName = "—";
    private string _claudeStatusText;
    private string _claudeStatusDetail;
    private string _claudeLastUpdatedText;
    private string _claudeTokensTodayText;

    public UsageViewModel(AppSettings settings)
    {
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));
        _statusText = T("Codex 사용량을 확인하는 중입니다", "Checking Codex usage");
        _statusDetail = T("잠시만 기다려 주세요.", "Please wait a moment.");
        _lastUpdatedText = T("업데이트 전", "Not updated yet");
        _claudeStatusText = T("Claude 로그인이 필요합니다", "Claude sign-in required");
        _claudeStatusDetail = T(
            "로그인하면 5시간·주간·모델별 한도를 함께 표시합니다.",
            "Sign in to see 5-hour, weekly, and per-model limits.");
        _claudeLastUpdatedText = T("업데이트 전", "Not updated yet");
        _claudeTokensTodayText = T("기록 꺼짐", "History off");
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<UsageCounterViewModel> Counters { get; } = [];

    public ObservableCollection<UsageCounterViewModel> ClaudeCounters { get; } = [];

    public OpenAIUsageData? LastCodexSnapshot => _lastCodexSnapshot;

    public ClaudeAccountSnapshot? LastClaudeSnapshot => _lastClaudeSnapshot;

    public string ClaudeOrganizationName =>
        _lastClaudeSnapshot?.Organization.Name ?? "Claude";

    public string PlanDisplayName
    {
        get => _planDisplayName;
        private set
        {
            if (SetField(ref _planDisplayName, value))
            {
                OnPropertyChanged(nameof(PlanCompactName));
            }
        }
    }

    public string PlanCompactName =>
        _lastCodexSnapshot?.PlanCompactName ?? PlanDisplayName.ToUpperInvariant();

    public string StatusText
    {
        get => _statusText;
        private set => SetField(ref _statusText, value);
    }

    public string StatusDetail
    {
        get => _statusDetail;
        private set => SetField(ref _statusDetail, value);
    }

    public string LastUpdatedText
    {
        get => _lastUpdatedText;
        private set => SetField(ref _lastUpdatedText, value);
    }

    public string TokensTodayText
    {
        get => _tokensTodayText;
        private set => SetField(ref _tokensTodayText, value);
    }

    public string ResetCreditsText
    {
        get => _resetCreditsText;
        private set => SetField(ref _resetCreditsText, value);
    }

    public bool IsRefreshing
    {
        get => _isRefreshing;
        private set
        {
            if (SetField(ref _isRefreshing, value))
            {
                OnPropertyChanged(nameof(RefreshButtonText));
                OnPropertyChanged(nameof(IsAnyProviderRefreshing));
            }
        }
    }

    public bool HasSnapshot
    {
        get => _hasSnapshot;
        private set
        {
            if (SetField(ref _hasSnapshot, value))
            {
                OnPropertyChanged(nameof(StatusBrush));
            }
        }
    }

    public bool HasError
    {
        get => _hasError;
        private set
        {
            if (SetField(ref _hasError, value))
            {
                OnPropertyChanged(nameof(StatusBrush));
            }
        }
    }

    public bool NeedsSetup
    {
        get => _needsSetup;
        private set => SetField(ref _needsSetup, value);
    }

    public ProviderLoadState ClaudeState
    {
        get => _claudeState;
        private set
        {
            if (!SetField(ref _claudeState, value))
            {
                return;
            }

            OnPropertyChanged(nameof(ClaudeIsRefreshing));
            OnPropertyChanged(nameof(ClaudeHasSnapshot));
            OnPropertyChanged(nameof(ClaudeHasError));
            OnPropertyChanged(nameof(ClaudeNeedsLogin));
            OnPropertyChanged(nameof(ClaudeStatusBrush));
            OnPropertyChanged(nameof(IsAnyProviderRefreshing));
            OnPropertyChanged(nameof(RefreshButtonText));
        }
    }

    public string ClaudePlanDisplayName
    {
        get => _claudePlanDisplayName;
        private set
        {
            if (SetField(ref _claudePlanDisplayName, value))
            {
                OnPropertyChanged(nameof(ClaudePlanCompactName));
            }
        }
    }

    public string ClaudePlanCompactName =>
        _lastClaudeSnapshot?.Organization.Plan.CompactName()
        ?? ClaudePlanDisplayName.ToUpperInvariant();

    public string ClaudeStatusText
    {
        get => _claudeStatusText;
        private set => SetField(ref _claudeStatusText, value);
    }

    public string ClaudeStatusDetail
    {
        get => _claudeStatusDetail;
        private set => SetField(ref _claudeStatusDetail, value);
    }

    public string ClaudeLastUpdatedText
    {
        get => _claudeLastUpdatedText;
        private set => SetField(ref _claudeLastUpdatedText, value);
    }

    public string ClaudeTokensTodayText
    {
        get => _claudeTokensTodayText;
        private set => SetField(ref _claudeTokensTodayText, value);
    }

    public bool ClaudeIsRefreshing
    {
        get => _claudeIsRefreshing;
        private set
        {
            if (SetField(ref _claudeIsRefreshing, value))
            {
                OnPropertyChanged(nameof(IsAnyProviderRefreshing));
                OnPropertyChanged(nameof(RefreshButtonText));
            }
        }
    }

    public bool ClaudeHasSnapshot => _lastClaudeSnapshot is not null;

    public bool ClaudeHasError => ClaudeState == ProviderLoadState.Error;

    public bool ClaudeNeedsLogin => ClaudeState == ProviderLoadState.NeedsLogin;

    public bool IsAnyProviderRefreshing => IsRefreshing || ClaudeIsRefreshing;

    public string RefreshButtonText => IsAnyProviderRefreshing
        ? T("새로 고치는 중…", "Refreshing…")
        : T("새로 고침", "Refresh");

    public System.Windows.Media.Brush StatusBrush => HasError
        ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(230, 84, 84))
        : HasSnapshot
            ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(49, 164, 108))
            : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(242, 169, 59));

    public System.Windows.Media.Brush ClaudeStatusBrush => ClaudeState switch
    {
        ProviderLoadState.Loaded => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(49, 164, 108)),
        ProviderLoadState.Error => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(230, 84, 84)),
        ProviderLoadState.NeedsLogin or ProviderLoadState.Unavailable =>
            new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(242, 169, 59)),
        _ => new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(242, 169, 59)),
    };

    public string TrayTooltip
    {
        get
        {
            var claude = _lastClaudeSnapshot?.Usage.FiveHour?.Utilization;
            var codex = _lastCodexSnapshot?.Counters.FirstOrDefault(counter =>
                counter.Scope == OpenAIUsageCounterScope.Standard
                && counter.Kind == OpenAIWindowKind.FiveHour)?.Window.UsedPercent;

            if (claude is { } claudePercent && codex is { } codexPercent)
            {
                return $"Claude {FormatPercent(claudePercent)} · Codex {FormatPercent(codexPercent)}";
            }

            if (claude is { } claudeOnly)
            {
                return T(
                    $"Claude {FormatPercent(claudeOnly)} · Codex 연결 대기",
                    $"Claude {FormatPercent(claudeOnly)} · Waiting for Codex");
            }

            return codex is { } codexOnly
                ? T(
                    $"Claude 로그인 필요 · Codex {FormatPercent(codexOnly)}",
                    $"Claude sign-in required · Codex {FormatPercent(codexOnly)}")
                : T("ClaudeUsage · 공급자 연결 대기", "ClaudeUsage · Waiting for providers");
        }
    }

    public void SetRefreshing()
    {
        IsRefreshing = true;
        if (!HasSnapshot)
        {
            StatusText = T("Codex 사용량을 확인하는 중입니다", "Checking Codex usage");
            StatusDetail = T(
                "설치된 Codex app-server에 안전하게 연결하고 있습니다.",
                "Connecting securely to the installed Codex app-server.");
            HasError = false;
            NeedsSetup = false;
        }
    }

    public void ApplySnapshot(
        OpenAIUsageData usage,
        DateTimeOffset updatedAt,
        DateTimeOffset? countdownNow = null)
    {
        var now = countdownNow ?? DateTimeOffset.Now;
        _lastCodexSnapshot = usage;
        _lastCodexUpdatedAt = updatedAt;
        Counters.Clear();
        foreach (var counter in usage.Counters)
        {
            if (!_settings.ShowCodexSpark && IsSpark(counter.Id, counter.Name))
            {
                continue;
            }

            Counters.Add(new UsageCounterViewModel(
                counter.Id,
                CounterTitle(counter.Name, counter.Scope),
                counter.Kind == OpenAIWindowKind.Weekly
                    ? T("주간", "Weekly")
                    : T("5시간", "5 hours"),
                counter.Window.UsedPercent,
                counter.Window.ResetAt,
                counter.Kind == OpenAIWindowKind.Weekly,
                now,
                ResettingText));
        }

        PlanDisplayName = usage.PlanDisplayName;
        TokensTodayText = usage.TodayTokens is { } tokens
            ? tokens.ToString("N0", CultureInfo.CurrentCulture)
            : T("집계 대기 중", "Waiting for totals");
        ResetCreditsText = usage.RateLimitResetCredits is { } credits
            ? T($"{credits.UsableCount(updatedAt)}개", $"{credits.UsableCount(updatedAt)} available")
            : T("제공되지 않음", "Not provided");
        LastUpdatedText = T(
            $"{updatedAt.LocalDateTime:HH:mm} 업데이트",
            $"Updated at {updatedAt.LocalDateTime:HH:mm}");
        StatusText = T("자동 연결됨", "Connected automatically");
        StatusDetail = T("60초마다 자동으로 갱신됩니다.", "Refreshes automatically every 60 seconds.");
        HasSnapshot = true;
        HasError = false;
        NeedsSetup = false;
        IsRefreshing = false;
        NotifyTrayChanged();
    }

    public void SetClaudeRefreshing()
    {
        ClaudeIsRefreshing = true;
        if (!ClaudeHasSnapshot)
        {
            ClaudeState = ProviderLoadState.Loading;
            ClaudeStatusText = T("Claude 사용량을 확인하는 중입니다", "Checking Claude usage");
            ClaudeStatusDetail = T(
                "claude.ai 사용량 응답을 안전하게 확인하고 있습니다.",
                "Checking the claude.ai usage response securely.");
        }
        NotifyTrayChanged();
    }

    public void ApplyClaudeSnapshot(
        ClaudeAccountSnapshot snapshot,
        DateTimeOffset updatedAt,
        DateTimeOffset? countdownNow = null)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var now = countdownNow ?? DateTimeOffset.Now;
        _lastClaudeSnapshot = snapshot;
        _lastClaudeUpdatedAt = updatedAt;
        ClaudeCounters.Clear();
        foreach (var counter in snapshot.Usage.Counters)
        {
            ClaudeCounters.Add(new UsageCounterViewModel(
                counter.Id,
                counter.DisplayName,
                counter.IsWeekly ? T("주간", "Weekly") : T("5시간", "5 hours"),
                counter.Window.Utilization,
                counter.Window.ResetsAt,
                counter.IsWeekly,
                now,
                ResettingText));
        }

        ClaudePlanDisplayName = snapshot.Organization.PlanDisplayName;
        ClaudeLastUpdatedText = T(
            $"{updatedAt.LocalDateTime:HH:mm} 업데이트",
            $"Updated at {updatedAt.LocalDateTime:HH:mm}");
        ClaudeStatusText = T("로그인됨", "Signed in");
        ClaudeStatusDetail = T(
            "Codex와 독립적으로 60초마다 갱신됩니다.",
            "Refreshes every 60 seconds independently of Codex.");
        ClaudeIsRefreshing = false;
        ClaudeState = ProviderLoadState.Loaded;
        OnPropertyChanged(nameof(ClaudeHasSnapshot));
        OnPropertyChanged(nameof(ClaudeOrganizationName));
        NotifyTrayChanged();
    }

    public void Relocalize()
    {
        OnPropertyChanged(nameof(RefreshButtonText));

        if (_lastCodexSnapshot is { } codexSnapshot && _lastCodexUpdatedAt is { } codexUpdatedAt)
        {
            ApplySnapshot(codexSnapshot, codexUpdatedAt);
        }
        else
        {
            StatusText = T("Codex 사용량을 확인하는 중입니다", "Checking Codex usage");
            StatusDetail = T("잠시만 기다려 주세요.", "Please wait a moment.");
            LastUpdatedText = T("업데이트 전", "Not updated yet");
        }

        if (_lastClaudeSnapshot is { } claudeSnapshot && _lastClaudeUpdatedAt is { } claudeUpdatedAt)
        {
            ApplyClaudeSnapshot(claudeSnapshot, claudeUpdatedAt);
            if (_settings.UsageHistoryEnabled)
            {
                ApplyClaudeLocalTokens(_claudeTodayTokens);
            }
            else
            {
                SetClaudeHistoryDisabled();
            }
        }
        else if (ClaudeState == ProviderLoadState.NeedsLogin)
        {
            ClearClaudeForLogout();
        }

        NotifyTrayChanged();
    }

    /// <summary>
    /// Advances visible reset countdowns without fetching provider data.
    /// The coordinator calls this every second, matching macOS CountdownText.
    /// </summary>
    public void UpdateCountdowns(DateTimeOffset now)
    {
        var codexChanged = false;
        foreach (var counter in Counters)
        {
            codexChanged |= counter.UpdateCountdown(now, ResettingText);
        }

        var claudeChanged = false;
        foreach (var counter in ClaudeCounters)
        {
            claudeChanged |= counter.UpdateCountdown(now, ResettingText);
        }

        // Flyout bindings observe each counter directly. WidgetViewModel maps
        // the same counters into its own presentation records, so notify it
        // only when visible text actually changed.
        if (codexChanged)
        {
            OnPropertyChanged(nameof(Counters));
        }

        if (claudeChanged)
        {
            OnPropertyChanged(nameof(ClaudeCounters));
        }
    }

    public void SetClaudeError(string title, string detail, bool needsLogin)
    {
        ClaudeIsRefreshing = false;
        if (ClaudeHasSnapshot && !needsLogin)
        {
            // Match macOS: a transient refresh failure keeps the last loaded
            // snapshot and its exact card geometry on screen.
            ClaudeState = ProviderLoadState.Loaded;
            NotifyTrayChanged();
            return;
        }

        if (needsLogin && ClaudeHasSnapshot)
        {
            ClearClaudeForLogout();
        }

        ClaudeStatusText = ClaudeHasSnapshot
            ? $"{T("이전 값 표시 중", "Showing previous values")} · {title}"
            : title;
        ClaudeStatusDetail = detail;
        ClaudeState = needsLogin ? ProviderLoadState.NeedsLogin : ProviderLoadState.Error;
        NotifyTrayChanged();
    }

    public void SetClaudeUnavailable(string title, string detail)
    {
        ClaudeIsRefreshing = false;
        ClaudeStatusText = ClaudeHasSnapshot
            ? $"{T("이전 값 표시 중", "Showing previous values")} · {title}"
            : title;
        ClaudeStatusDetail = detail;
        ClaudeState = ProviderLoadState.Unavailable;
        NotifyTrayChanged();
    }

    public void ClearClaudeForLogout()
    {
        ClaudeIsRefreshing = false;
        _lastClaudeSnapshot = null;
        _lastClaudeUpdatedAt = null;
        _claudeTodayTokens = null;
        ClaudeCounters.Clear();
        ClaudePlanDisplayName = "—";
        ClaudeLastUpdatedText = T("업데이트 전", "Not updated yet");
        ClaudeTokensTodayText = T("기록 꺼짐", "History off");
        ClaudeStatusText = T("Claude 로그인이 필요합니다", "Claude sign-in required");
        ClaudeStatusDetail = T(
            "로그인하면 5시간·주간·모델별 한도를 함께 표시합니다.",
            "Sign in to see 5-hour, weekly, and per-model limits.");
        ClaudeState = ProviderLoadState.NeedsLogin;
        OnPropertyChanged(nameof(ClaudeHasSnapshot));
        OnPropertyChanged(nameof(ClaudeOrganizationName));
        NotifyTrayChanged();
    }

    public void ApplyClaudeLocalTokens(long? todayTokens)
    {
        _claudeTodayTokens = todayTokens;
        ClaudeTokensTodayText = todayTokens is { } tokens
            ? tokens.ToString("N0", CultureInfo.CurrentCulture)
            : T("집계 대기 중", "Waiting for totals");
    }

    public void SetClaudeHistoryDisabled()
    {
        _claudeTodayTokens = null;
        ClaudeTokensTodayText = T("기록 꺼짐", "History off");
    }

    public UsageHistorySnapshot CreateHistorySnapshot()
    {
        var claudeUsage = _lastClaudeSnapshot?.Usage;
        var codexCounters = _lastCodexSnapshot?.Counters ?? [];
        var codexFiveHour = codexCounters.FirstOrDefault(counter =>
            counter.Scope == OpenAIUsageCounterScope.Standard
            && counter.Kind == OpenAIWindowKind.FiveHour)?.Window.UsedPercent;
        var codexWeekly = codexCounters.FirstOrDefault(counter =>
            counter.Scope == OpenAIUsageCounterScope.Standard
            && counter.Kind == OpenAIWindowKind.Weekly)?.Window.UsedPercent;

        var claudeModels = claudeUsage?.Counters
            .Where(counter => counter.IsModel)
            .Select(counter => new UsageHistoryCounter(
                counter.Id,
                counter.DisplayName,
                counter.Window.Utilization))
            .ToArray() ?? [];
        var codexModels = codexCounters
            .Where(counter => counter.Scope == OpenAIUsageCounterScope.Model)
            .Where(counter => _settings.ShowCodexSpark || !IsSpark(counter.Id, counter.Name))
            .Select(counter => new UsageHistoryCounter(
                counter.Id,
                CounterTitle(counter.Name, counter.Scope),
                counter.Window.UsedPercent))
            .ToArray();

        return new UsageHistorySnapshot(
            claudeFiveHour: claudeUsage?.FiveHour?.Utilization,
            claudeWeekly: claudeUsage?.SevenDay?.Utilization,
            openAIFiveHour: codexFiveHour,
            openAIWeekly: codexWeekly,
            claudeTodayTokens: _claudeTodayTokens,
            openAITodayTokens: _lastCodexSnapshot?.TodayTokens,
            claudeModelCounters: claudeModels,
            openAIModelCounters: codexModels);
    }

    public void SetError(string title, string detail, bool needsSetup)
    {
        StatusText = HasSnapshot
            ? $"{T("이전 값 표시 중", "Showing previous values")} · {title}"
            : title;
        StatusDetail = detail;
        HasError = true;
        NeedsSetup = needsSetup;
        IsRefreshing = false;
        NotifyTrayChanged();
    }

    private static bool IsSpark(string id, string? name) =>
        id.Contains("spark", StringComparison.OrdinalIgnoreCase)
        || (name?.Contains("spark", StringComparison.OrdinalIgnoreCase) ?? false);

    private string CounterTitle(string? name, OpenAIUsageCounterScope scope) => scope switch
    {
        OpenAIUsageCounterScope.Standard => T("Codex 전체", "Codex overall"),
        OpenAIUsageCounterScope.CodeReview => "Code Review",
        _ => string.IsNullOrWhiteSpace(name) ? T("Codex 모델", "Codex model") : name
    };

    private static string FormatPercent(double percent) => $"{Math.Clamp(percent, 0, 100):0}%";

    private string ResettingText => T("리셋 중", "Resetting");

    private string T(string korean, string english) =>
        _settings.Language == AppLanguage.Korean ? korean : english;

    private void NotifyTrayChanged()
    {
        OnPropertyChanged(nameof(TrayTooltip));
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
