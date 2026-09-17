using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.ViewModels;

public sealed record CompanionOption(CompanionKind Kind, string Id, string DisplayName, string Description);

public sealed class CompanionViewModel : INotifyPropertyChanged
{
    private CompanionKind _selectedCompanion;
    private MimoSensitivity _sensitivity;
    private MimoAnimationMode _animationMode;
    private bool _reducedMotion;
    private AppLanguage _language;
    private UsageHistorySnapshot _snapshot = new();
    private UsageTrend _trend = UsageTrend.Empty;
    private PetMood _mood = PetMood.Waiting;
    private string _bubbleText;
    private int _availableResetCredits;
    private DateTimeOffset? _earliestResetCreditExpiry;
    private string? _resetRecommendation;
    private DateTimeOffset _messageNow = DateTimeOffset.Now;

    public CompanionViewModel(
        CompanionKind selectedCompanion = CompanionKind.Mimo,
        MimoSensitivity sensitivity = MimoSensitivity.Balanced,
        MimoAnimationMode animationMode = MimoAnimationMode.Automatic,
        bool reducedMotion = false,
        AppLanguage language = AppLanguage.Korean)
    {
        _selectedCompanion = selectedCompanion;
        _sensitivity = sensitivity;
        _animationMode = animationMode;
        _reducedMotion = reducedMotion;
        _language = language;
        _bubbleText = L(
            "Companion.Bubble.Loading",
            "사용량을 불러오고 있어요.",
            "Loading usage…");
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<CompanionOption> CompanionOptions => CreateCatalog();

    public AppLanguage Language
    {
        get => _language;
        set
        {
            if (!SetField(ref _language, value))
            {
                return;
            }

            OnPropertyChanged(nameof(CompanionOptions));
            OnPropertyChanged(nameof(MoodTitle));
            OnPropertyChanged(nameof(PaceText));
            OnPropertyChanged(nameof(RecentTokenText));
            OnPropertyChanged(nameof(DetailText));
            ResolveBubble();
            OnPropertyChanged(nameof(AccessibilityLabel));
        }
    }

    public CompanionKind SelectedCompanion
    {
        get => _selectedCompanion;
        set
        {
            if (SetField(ref _selectedCompanion, value))
            {
                OnPropertyChanged(nameof(SelectedCompanionName));
                OnPropertyChanged(nameof(AccessibilityLabel));
            }
        }
    }

    public string SelectedCompanionName => SelectedCompanion.DisplayName();

    public MimoSensitivity Sensitivity
    {
        get => _sensitivity;
        set
        {
            if (SetField(ref _sensitivity, value))
            {
                ResolveState();
            }
        }
    }

    public MimoAnimationMode AnimationMode
    {
        get => _animationMode;
        set => SetField(ref _animationMode, value);
    }

    public bool ReducedMotion
    {
        get => _reducedMotion;
        set => SetField(ref _reducedMotion, value);
    }

    public PetMood Mood
    {
        get => _mood;
        private set
        {
            if (SetField(ref _mood, value))
            {
                OnPropertyChanged(nameof(MoodTitle));
                OnPropertyChanged(nameof(AccessibilityLabel));
            }
        }
    }

    public UsageHistorySnapshot Snapshot => _snapshot;

    public UsageTrend Trend => _trend;

    public string BubbleText
    {
        get => _bubbleText;
        private set
        {
            if (SetField(ref _bubbleText, value))
            {
                OnPropertyChanged(nameof(AccessibilityLabel));
            }
        }
    }

    public string PressureText => _snapshot.Pressure is { } pressure ? $"{pressure:0}%" : "-";

    public double Pressure => Math.Clamp(_snapshot.Pressure ?? 0, 0, 100);

    public string RemainingText => _snapshot.Pressure is { } pressure
        ? $"{Math.Max(0, 100 - pressure):0}%"
        : "-";

    public string MoodTitle => MoodText();

    public IReadOnlyList<double> TrendPoints => _trend.Points;

    public string PaceText => _trend.PercentPerHour is { } pace
        ? Format(
            "Companion.PaceFormat",
            "+{0:0.#}%p/시간",
            "+{0:0.#}%p/hour",
            pace)
        : "-";

    public string RecentTokenText => _trend.RecentTokenDelta is { } tokens
        ? Format(
            "Companion.TokenDeltaFormat",
            "+{0} 토큰",
            "+{0} tokens",
            tokens.ToString("N0", CultureInfo.CurrentCulture))
        : "-";

    public string DetailText
    {
        get
        {
            if (_trend.RecentTokenDelta is > 0)
            {
                return RecentTokenText;
            }

            if (_trend.PercentPerHour is > 0.1)
            {
                return PaceText;
            }

            return PressureText == "-"
                ? L("Companion.Detail.Waiting", "사용량 대기 중", "Waiting for usage")
                : Format(
                    "Companion.Detail.PressureFormat",
                    "현재 {0}",
                    "Now {0}",
                    PressureText);
        }
    }

    public string AccessibilityLabel => Format(
        "Companion.AccessibilityFormat",
        "{0}, {1}, 사용량 {2}. {3}",
        "{0}, {1}, usage {2}. {3}",
        SelectedCompanionName,
        MoodText(),
        PressureText,
        BubbleText);

    public void ApplyUsage(
        UsageHistorySnapshot snapshot,
        UsageTrend? trend = null,
        bool historyEnabled = true,
        DateTimeOffset? now = null)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        _snapshot = snapshot;
        _trend = historyEnabled ? trend ?? UsageTrend.Empty : UsageTrend.Empty;
        _messageNow = now ?? DateTimeOffset.Now;
        OnPropertyChanged(nameof(Snapshot));
        OnPropertyChanged(nameof(Trend));
        OnPropertyChanged(nameof(PressureText));
        OnPropertyChanged(nameof(Pressure));
        OnPropertyChanged(nameof(RemainingText));
        OnPropertyChanged(nameof(PaceText));
        OnPropertyChanged(nameof(RecentTokenText));
        OnPropertyChanged(nameof(DetailText));
        OnPropertyChanged(nameof(TrendPoints));
        ResolveState();
    }

    /// <summary>
    /// Updates read-only reset-credit messaging. This view model intentionally exposes no consume command.
    /// </summary>
    public void ApplyResetCreditStatus(
        int availableCount,
        DateTimeOffset? earliestExpiry = null,
        string? recommendation = null,
        DateTimeOffset? now = null)
    {
        _availableResetCredits = Math.Max(0, availableCount);
        _earliestResetCreditExpiry = earliestExpiry;
        _resetRecommendation = string.IsNullOrWhiteSpace(recommendation) ? null : recommendation.Trim();
        _messageNow = now ?? DateTimeOffset.Now;
        ResolveBubble();
    }

    public void ClearResetCreditStatus()
    {
        _availableResetCredits = 0;
        _earliestResetCreditExpiry = null;
        _resetRecommendation = null;
        ResolveBubble();
    }

    private void ResolveState()
    {
        Mood = PetMoodResolver.Resolve(_snapshot, _trend, Sensitivity);
        ResolveBubble();
    }

    private void ResolveBubble()
    {
        BubbleText = ResolveBubbleText();
    }

    private string ResolveBubbleText()
    {
        // Deterministic priority: credit advice/expiry, reset, critical, rapid activity, idle.
        if (_resetRecommendation is not null)
        {
            return _resetRecommendation;
        }

        if (_availableResetCredits > 0
            && _earliestResetCreditExpiry is { } expiry
            && expiry > _messageNow
            && expiry - _messageNow <= TimeSpan.FromHours(72))
        {
            return Format(
                "Companion.Bubble.CreditExpiryFormat",
                "초기화 크레딧 {0}개 · {1} 만료",
                "{0} reset passes · expires {1}",
                _availableResetCredits,
                FormatExpiry(expiry));
        }

        if (Mood == PetMood.Refreshed)
        {
            return L(
                "Companion.Bubble.Refreshed",
                "한도가 초기화됐어요. 다시 산뜻하게 시작해요!",
                "Your limit has reset. You're ready for a fresh start!");
        }

        if (Mood == PetMood.Tired)
        {
            return L(
                "Companion.Bubble.Tired",
                "한도에 가까워졌어요. 다음 초기화 시간을 확인해 주세요.",
                "You're close to the limit. Check the next reset time.");
        }

        if ((_trend.PercentPerHour ?? 0) >= 25)
        {
            return L(
                "Companion.Bubble.FastPace",
                "사용 속도가 아주 빨라요. 잠깐 한도를 살펴볼까요?",
                "Usage is rising quickly. Take a moment to check your limit.");
        }

        if (Mood == PetMood.Sleepy)
        {
            return L(
                "Companion.Bubble.Sleepy",
                "오늘 많이 달렸어요. 남은 여유를 확인해 주세요.",
                "You've done a lot today. Check how much room is left.");
        }

        if (Mood == PetMood.Focused && _snapshot.PressureSource is { } source)
        {
            return Format(
                "Companion.Bubble.FocusedFormat",
                "{0} 사용량을 집중해서 지켜보고 있어요.",
                "Keeping a close eye on {0} usage.",
                source.Label);
        }

        if (_availableResetCredits > 0)
        {
            return Format(
                "Companion.Bubble.CreditsAvailableFormat",
                "사용 가능한 초기화 크레딧이 {0}개 있어요.",
                "You have {0} reset passes available.",
                _availableResetCredits);
        }

        return Mood switch
        {
            PetMood.Waiting => L(
                "Companion.Bubble.Loading",
                "사용량을 불러오고 있어요.",
                "Loading usage…"),
            PetMood.Calm => L(
                "Companion.Bubble.Calm",
                "아직 여유로워요. 편안하게 작업하세요.",
                "There's plenty of room. Keep working comfortably."),
            _ => L(
                "Companion.Bubble.Watching",
                "사용량 변화를 지켜보고 있어요.",
                "Watching for usage changes."),
        };
    }

    private string FormatExpiry(DateTimeOffset expiry) =>
        expiry.ToLocalTime().ToString(
            L("Companion.ExpiryDateFormat", "M월 d일 HH:mm", "MMM d, HH:mm"),
            CultureInfo.CurrentCulture);

    private IReadOnlyList<CompanionOption> CreateCatalog() =>
    [
        CreateOption(CompanionKind.Mimo, "mimo", "a robot that works beside your laptop", "노트북과 함께 일하는 로봇"),
        CreateOption(CompanionKind.Lumi, "lumi", "a desk lamp that shines while you focus", "집중할 때 빛을 비추는 데스크 램프"),
        CreateOption(CompanionKind.Kumo, "kumo", "a cloud whose weather changes with usage", "사용량에 따라 날씨가 바뀌는 구름"),
        CreateOption(CompanionKind.Dot, "dot", "a pixel friend carrying a tiny terminal", "작은 터미널을 품은 픽셀 친구"),
        CreateOption(CompanionKind.Navi, "navi", "a drone that explores Claude and Codex", "Claude와 Codex를 탐색하는 드론"),
        CreateOption(CompanionKind.Bori, "bori", "a fox researcher wearing focus glasses", "집중 안경을 쓰는 여우 연구원"),
        CreateOption(CompanionKind.Muru, "muru", "a mushroom friend who loves books and sprouts", "책과 새잎을 좋아하는 버섯 친구"),
        CreateOption(CompanionKind.Tori, "tori", "a digital bird that flaps faster as work gets busy", "바쁠수록 날갯짓이 빨라지는 디지털 새"),
        CreateOption(CompanionKind.Pico, "pico", "a robot cat whose chest battery shows remaining room", "가슴 배터리로 남은 여유를 보여주는 로봇 고양이"),
    ];

    private CompanionOption CreateOption(
        CompanionKind kind,
        string id,
        string englishDescription,
        string koreanDescription) => new(
            kind,
            id,
            kind.DisplayName(),
            L($"Companion.Description.{kind}", koreanDescription, englishDescription));

    private string MoodText() => L(
        $"Companion.Mood.{Mood}",
        Mood switch
        {
            PetMood.Waiting => "대기 중",
            PetMood.Calm => "여유로움",
            PetMood.Focused => "집중",
            PetMood.Sleepy => "피곤함",
            PetMood.Tired => "한도 임박",
            PetMood.Refreshed => "새로고침",
            _ => Mood.ToString(),
        },
        Mood.ToString());

    private string L(string key, string koreanFallback, string englishFallback) =>
        ThemeResourceManager.GetString(
            key,
            Language == AppLanguage.Korean ? koreanFallback : englishFallback);

    private string Format(
        string key,
        string koreanFallback,
        string englishFallback,
        params object[] arguments) => string.Format(
            CultureInfo.CurrentCulture,
            L(key, koreanFallback, englishFallback),
            arguments);

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
