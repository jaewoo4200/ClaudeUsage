using System.Text.Json.Serialization;

namespace ClaudeUsage.Core.Models;

public sealed record UsageHistoryCounter(string Id, string Label, double Utilization);

[JsonConverter(typeof(JsonStringEnumConverter<UsageProvider>))]
public enum UsageProvider
{
    [JsonStringEnumMemberName("claude")]
    Claude,

    [JsonStringEnumMemberName("codex")]
    Codex,
}

public sealed record UsagePressureSource(
    string Id,
    string Label,
    UsageProvider Provider,
    double Utilization);

public sealed class UsageHistorySnapshot
{
    public UsageHistorySnapshot(
        double? claudeFiveHour = null,
        double? claudeWeekly = null,
        double? claudeModelMaximum = null,
        double? openAIFiveHour = null,
        double? openAIWeekly = null,
        double? openAIModelMaximum = null,
        long? claudeTodayTokens = null,
        long? openAITodayTokens = null,
        IEnumerable<UsageHistoryCounter>? claudeModelCounters = null,
        IEnumerable<UsageHistoryCounter>? openAIModelCounters = null)
    {
        ClaudeFiveHour = claudeFiveHour;
        ClaudeWeekly = claudeWeekly;
        ClaudeModelMaximum = claudeModelMaximum;
        OpenAIFiveHour = openAIFiveHour;
        OpenAIWeekly = openAIWeekly;
        OpenAIModelMaximum = openAIModelMaximum;
        ClaudeTodayTokens = claudeTodayTokens;
        OpenAITodayTokens = openAITodayTokens;
        // A locally edited or partially recovered JSON file can contain null
        // array elements even though the public model is non-nullable.
        ClaudeModelCounters = Array.AsReadOnly((claudeModelCounters ?? [])
            .OfType<UsageHistoryCounter>()
            .ToArray());
        OpenAIModelCounters = Array.AsReadOnly((openAIModelCounters ?? [])
            .OfType<UsageHistoryCounter>()
            .ToArray());
    }

    public double? ClaudeFiveHour { get; }

    public double? ClaudeWeekly { get; }

    /// <summary>
    /// Legacy aggregate retained for samples written before individual model counters.
    /// It is ignored whenever <see cref="ClaudeModelCounters"/> contains values.
    /// </summary>
    public double? ClaudeModelMaximum { get; }

    public double? OpenAIFiveHour { get; }

    public double? OpenAIWeekly { get; }

    /// <summary>
    /// Legacy aggregate retained for samples written before individual model counters.
    /// It is ignored whenever <see cref="OpenAIModelCounters"/> contains values.
    /// </summary>
    public double? OpenAIModelMaximum { get; }

    public long? ClaudeTodayTokens { get; }

    public long? OpenAITodayTokens { get; }

    public IReadOnlyList<UsageHistoryCounter> ClaudeModelCounters { get; }

    public IReadOnlyList<UsageHistoryCounter> OpenAIModelCounters { get; }

    [JsonIgnore]
    public IReadOnlyList<UsagePressureSource> PressureSources
    {
        get
        {
            var sources = new List<UsagePressureSource>();
            AppendSource(sources, ClaudeFiveHour, "claude-five-hour", "Claude 5-hour", UsageProvider.Claude);
            AppendSource(sources, ClaudeWeekly, "claude-weekly", "Claude weekly", UsageProvider.Claude);
            AppendSource(sources, OpenAIFiveHour, "codex-five-hour", "Codex 5-hour", UsageProvider.Codex);
            AppendSource(sources, OpenAIWeekly, "codex-weekly", "Codex weekly", UsageProvider.Codex);

            sources.AddRange(ClaudeModelCounters
                .Where(IsUsableCounter)
                .Select(counter => new UsagePressureSource(
                    counter.Id,
                    counter.Label,
                    UsageProvider.Claude,
                    counter.Utilization)));
            sources.AddRange(OpenAIModelCounters
                .Where(IsUsableCounter)
                .Select(counter => new UsagePressureSource(
                    counter.Id,
                    counter.Label,
                    UsageProvider.Codex,
                    counter.Utilization)));

            if (ClaudeModelCounters.Count == 0)
            {
                AppendSource(
                    sources,
                    ClaudeModelMaximum,
                    "claude-model-maximum",
                    "Claude model limit",
                    UsageProvider.Claude);
            }

            if (OpenAIModelCounters.Count == 0)
            {
                AppendSource(
                    sources,
                    OpenAIModelMaximum,
                    "codex-model-maximum",
                    "Codex model limit",
                    UsageProvider.Codex);
            }

            return Array.AsReadOnly(sources
                .OrderByDescending(source => source.Utilization)
                .ThenBy(source => source.Id, StringComparer.Ordinal)
                .ToArray());
        }
    }

    [JsonIgnore]
    public UsagePressureSource? PressureSource => PressureSources.FirstOrDefault();

    [JsonIgnore]
    public double? Pressure => PressureSource?.Utilization;

    [JsonIgnore]
    public long? TodayTokens
    {
        get
        {
            if (ClaudeTodayTokens is null)
            {
                return OpenAITodayTokens;
            }

            if (OpenAITodayTokens is null)
            {
                return ClaudeTodayTokens;
            }

            return SaturatingAdd(ClaudeTodayTokens.Value, OpenAITodayTokens.Value);
        }
    }

    [JsonIgnore]
    public bool HasUsage => Pressure is not null;

    public UsagePressureSource? PressureSourceFor(UsageProvider provider) =>
        PressureSources.FirstOrDefault(source => source.Provider == provider);

    public double? PressureFor(UsageProvider provider) => PressureSourceFor(provider)?.Utilization;

    public UsageHistorySnapshot WithClaudeTodayTokens(long? todayTokens) => new(
        ClaudeFiveHour,
        ClaudeWeekly,
        ClaudeModelMaximum,
        OpenAIFiveHour,
        OpenAIWeekly,
        OpenAIModelMaximum,
        todayTokens,
        OpenAITodayTokens,
        ClaudeModelCounters,
        OpenAIModelCounters);

    private static bool IsUsableCounter(UsageHistoryCounter counter) =>
        !string.IsNullOrWhiteSpace(counter.Id) && double.IsFinite(counter.Utilization);

    private static void AppendSource(
        ICollection<UsagePressureSource> sources,
        double? value,
        string id,
        string label,
        UsageProvider provider)
    {
        if (value is not { } utilization || !double.IsFinite(utilization))
        {
            return;
        }

        sources.Add(new UsagePressureSource(id, label, provider, utilization));
    }

    private static long SaturatingAdd(long left, long right)
    {
        if (right > 0 && left > long.MaxValue - right)
        {
            return long.MaxValue;
        }

        if (right < 0 && left < long.MinValue - right)
        {
            return long.MinValue;
        }

        return left + right;
    }
}

public sealed class UsageHistorySample
{
    [JsonConstructor]
    public UsageHistorySample(
        DateTimeOffset timestamp,
        double? claudeFiveHour = null,
        double? claudeWeekly = null,
        double? claudeModelMaximum = null,
        double? openAIFiveHour = null,
        double? openAIWeekly = null,
        double? openAIModelMaximum = null,
        long? claudeTodayTokens = null,
        long? openAITodayTokens = null,
        UsageHistoryCounter[]? claudeModelCounters = null,
        UsageHistoryCounter[]? openAIModelCounters = null)
    {
        Timestamp = timestamp;
        ClaudeFiveHour = claudeFiveHour;
        ClaudeWeekly = claudeWeekly;
        ClaudeModelMaximum = claudeModelMaximum;
        OpenAIFiveHour = openAIFiveHour;
        OpenAIWeekly = openAIWeekly;
        OpenAIModelMaximum = openAIModelMaximum;
        ClaudeTodayTokens = claudeTodayTokens;
        OpenAITodayTokens = openAITodayTokens;
        ClaudeModelCounters = claudeModelCounters;
        OpenAIModelCounters = openAIModelCounters;
    }

    public UsageHistorySample(DateTimeOffset timestamp, UsageHistorySnapshot snapshot)
        : this(
            timestamp,
            snapshot.ClaudeFiveHour,
            snapshot.ClaudeWeekly,
            snapshot.ClaudeModelMaximum,
            snapshot.OpenAIFiveHour,
            snapshot.OpenAIWeekly,
            snapshot.OpenAIModelMaximum,
            snapshot.ClaudeTodayTokens,
            snapshot.OpenAITodayTokens,
            snapshot.ClaudeModelCounters.Count == 0 ? null : snapshot.ClaudeModelCounters.ToArray(),
            snapshot.OpenAIModelCounters.Count == 0 ? null : snapshot.OpenAIModelCounters.ToArray())
    {
    }

    public DateTimeOffset Timestamp { get; }

    public double? ClaudeFiveHour { get; }

    public double? ClaudeWeekly { get; }

    public double? ClaudeModelMaximum { get; }

    public double? OpenAIFiveHour { get; }

    public double? OpenAIWeekly { get; }

    public double? OpenAIModelMaximum { get; }

    public long? ClaudeTodayTokens { get; }

    public long? OpenAITodayTokens { get; }

    public UsageHistoryCounter[]? ClaudeModelCounters { get; }

    public UsageHistoryCounter[]? OpenAIModelCounters { get; }

    [JsonIgnore]
    public UsageHistorySnapshot Snapshot => new(
        ClaudeFiveHour,
        ClaudeWeekly,
        ClaudeModelMaximum,
        OpenAIFiveHour,
        OpenAIWeekly,
        OpenAIModelMaximum,
        ClaudeTodayTokens,
        OpenAITodayTokens,
        ClaudeModelCounters,
        OpenAIModelCounters);
}

public sealed record UsageTrend(
    IReadOnlyList<double> Points,
    double? DeltaPercent,
    double? PercentPerHour,
    long? RecentTokenDelta,
    bool ResetDetected)
{
    public static UsageTrend Empty { get; } = new([], null, null, null, false);
}

[JsonConverter(typeof(JsonStringEnumConverter<PetMood>))]
public enum PetMood
{
    [JsonStringEnumMemberName("waiting")]
    Waiting,

    [JsonStringEnumMemberName("calm")]
    Calm,

    [JsonStringEnumMemberName("focused")]
    Focused,

    [JsonStringEnumMemberName("sleepy")]
    Sleepy,

    [JsonStringEnumMemberName("tired")]
    Tired,

    [JsonStringEnumMemberName("refreshed")]
    Refreshed,
}

[JsonConverter(typeof(JsonStringEnumConverter<MimoSensitivity>))]
public enum MimoSensitivity
{
    [JsonStringEnumMemberName("responsive")]
    Responsive,

    [JsonStringEnumMemberName("balanced")]
    Balanced,

    [JsonStringEnumMemberName("relaxed")]
    Relaxed,
}

public readonly record struct MoodThresholds(
    double FocusedPressure,
    double FocusedBurnRate,
    double SleepyPressure,
    double SleepyBurnRate,
    double TiredPressure,
    double TiredBurnRate);

public static class MimoSensitivityExtensions
{
    public static MoodThresholds Thresholds(this MimoSensitivity sensitivity) => sensitivity switch
    {
        MimoSensitivity.Responsive => new(35, 8, 70, 22, 90, 40),
        MimoSensitivity.Balanced => new(50, 14, 75, 28, 90, 45),
        MimoSensitivity.Relaxed => new(60, 18, 82, 34, 94, 52),
        _ => throw new ArgumentOutOfRangeException(nameof(sensitivity), sensitivity, null),
    };
}

public static class PetMoodResolver
{
    public static PetMood Resolve(
        UsageHistorySnapshot snapshot,
        UsageTrend? trend = null,
        MimoSensitivity sensitivity = MimoSensitivity.Balanced)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        trend ??= UsageTrend.Empty;

        if (snapshot.Pressure is not { } pressure)
        {
            return PetMood.Waiting;
        }

        if (trend.ResetDetected && pressure < 60)
        {
            return PetMood.Refreshed;
        }

        var thresholds = sensitivity.Thresholds();
        var burnRate = trend.PercentPerHour ?? 0;
        if (pressure >= thresholds.TiredPressure || burnRate >= thresholds.TiredBurnRate)
        {
            return PetMood.Tired;
        }

        if (pressure >= thresholds.SleepyPressure || burnRate >= thresholds.SleepyBurnRate)
        {
            return PetMood.Sleepy;
        }

        if (pressure >= thresholds.FocusedPressure || burnRate >= thresholds.FocusedBurnRate)
        {
            return PetMood.Focused;
        }

        return PetMood.Calm;
    }
}

[JsonConverter(typeof(JsonStringEnumConverter<MimoAnimationMode>))]
public enum MimoAnimationMode
{
    [JsonStringEnumMemberName("automatic")]
    Automatic,

    [JsonStringEnumMemberName("lively")]
    Lively,

    [JsonStringEnumMemberName("still")]
    Still,
}

public static class MimoAnimationModeExtensions
{
    public static TimeSpan? UpdateInterval(this MimoAnimationMode mode, PetMood mood) => mode switch
    {
        MimoAnimationMode.Still => null,
        MimoAnimationMode.Lively => TimeSpan.FromSeconds(0.25),
        MimoAnimationMode.Automatic when mood is PetMood.Focused or PetMood.Refreshed =>
            TimeSpan.FromSeconds(0.45),
        MimoAnimationMode.Automatic when mood is PetMood.Sleepy or PetMood.Tired =>
            TimeSpan.FromSeconds(1.8),
        MimoAnimationMode.Automatic => TimeSpan.FromSeconds(1.4),
        _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, null),
    };

    public static TimeSpan TransitionDuration(this MimoAnimationMode mode, PetMood mood) => mode switch
    {
        MimoAnimationMode.Still => TimeSpan.Zero,
        MimoAnimationMode.Lively => TimeSpan.FromSeconds(0.16),
        MimoAnimationMode.Automatic when mood is PetMood.Focused or PetMood.Refreshed =>
            TimeSpan.FromSeconds(0.16),
        MimoAnimationMode.Automatic when mood is PetMood.Sleepy or PetMood.Tired =>
            TimeSpan.FromSeconds(0.25),
        MimoAnimationMode.Automatic => TimeSpan.FromSeconds(0.22),
        _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, null),
    };
}

[JsonConverter(typeof(JsonStringEnumConverter<CompanionKind>))]
public enum CompanionKind
{
    [JsonStringEnumMemberName("mimo")]
    Mimo,

    [JsonStringEnumMemberName("lumi")]
    Lumi,

    [JsonStringEnumMemberName("kumo")]
    Kumo,

    [JsonStringEnumMemberName("dot")]
    Dot,

    [JsonStringEnumMemberName("navi")]
    Navi,

    [JsonStringEnumMemberName("bori")]
    Bori,

    [JsonStringEnumMemberName("muru")]
    Muru,

    [JsonStringEnumMemberName("tori")]
    Tori,

    [JsonStringEnumMemberName("pico")]
    Pico,
}

public static class CompanionKindExtensions
{
    public static string Id(this CompanionKind kind) => kind.ToString().ToLowerInvariant();

    public static string DisplayName(this CompanionKind kind) => kind switch
    {
        CompanionKind.Mimo => "Mimo",
        CompanionKind.Lumi => "Lumi",
        CompanionKind.Kumo => "Kumo",
        CompanionKind.Dot => "Dot",
        CompanionKind.Navi => "Navi",
        CompanionKind.Bori => "Bori",
        CompanionKind.Muru => "Muru",
        CompanionKind.Tori => "Tori",
        CompanionKind.Pico => "Pico",
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, null),
    };
}

public readonly record struct CompanionPose(
    double LeftPartAngle,
    double RightPartAngle,
    double HeadAngle,
    bool ShowWorkProp,
    bool ShowSleepMark,
    bool ShowAlert,
    bool ShowCelebration,
    double LeftLegAngle = 0,
    double RightLegAngle = 0,
    double TailAngle = 0,
    double VerticalOffset = 0,
    double EffectOpacity = 1);

public static class CompanionPoseResolver
{
    /// <summary>
    /// Resolves a stable target pose for a time bucket. No random state is used, so recreating a
    /// widget in the same bucket produces the same pose.
    /// </summary>
    public static CompanionPose Resolve(
        CompanionKind kind,
        PetMood mood,
        long timeBucket,
        bool reducedMotion = false)
    {
        if (reducedMotion)
        {
            return StaticPose(kind, mood);
        }

        // The SwiftUI characters resolve their motion from the same two waves.  A time bucket is
        // intentionally used here instead of wall-clock state so separate Windows widgets stay in
        // a deterministic pose.  Bucket zero is also the canonical still/reduced-motion pose.
        var slow = Math.Sin(timeBucket * 1.35);
        var quick = Math.Sin(timeBucket * 3.4);
        var pose = StaticPose(kind, mood);

        return kind switch
        {
            CompanionKind.Mimo => mood switch
            {
                PetMood.Waiting => pose with
                {
                    LeftPartAngle = 17 + slow * 5,
                    RightPartAngle = -17 - slow * 5,
                    LeftLegAngle = quick * 7,
                    RightLegAngle = -quick * 7,
                },
                PetMood.Calm => pose with
                {
                    LeftPartAngle = 16 + slow * 4,
                    RightPartAngle = -16 - slow * 4,
                    LeftLegAngle = slow * 2,
                    RightLegAngle = -slow * 2,
                },
                PetMood.Focused => pose with
                {
                    LeftPartAngle = 22 + quick * 7,
                    RightPartAngle = -22 - quick * 7,
                    LeftLegAngle = quick * 3,
                    RightLegAngle = -quick * 3,
                },
                PetMood.Tired => pose with
                {
                    LeftPartAngle = 34 + slow * 5,
                    RightPartAngle = -34 - slow * 5,
                },
                PetMood.Refreshed => pose with
                {
                    LeftPartAngle = 16 + slow * 4,
                    RightPartAngle = -132 + quick * 24,
                    LeftLegAngle = -4 + quick * 6,
                    RightLegAngle = 4 - quick * 6,
                },
                _ => pose,
            },
            CompanionKind.Lumi => pose with
            {
                HeadAngle = mood switch
                {
                    PetMood.Focused => -8 + quick * 3,
                    PetMood.Refreshed => -4 + quick * 8,
                    PetMood.Waiting or PetMood.Calm => -2 + slow * 3,
                    _ => pose.HeadAngle,
                },
                EffectOpacity = mood == PetMood.Tired ? 0.52 + Math.Abs(quick) * 0.38 : 1,
            },
            CompanionKind.Kumo => pose with
            {
                HeadAngle = mood == PetMood.Refreshed ? quick * 8 : 0,
                VerticalOffset = mood == PetMood.Sleepy ? slow * 1.5 : 0,
            },
            CompanionKind.Dot => pose with
            {
                VerticalOffset = mood == PetMood.Focused ? quick * 3.5 : slow * 1.5,
            },
            CompanionKind.Navi => pose with { VerticalOffset = slow * 4.5 },
            CompanionKind.Bori => pose with
            {
                HeadAngle = mood == PetMood.Tired ? 9 : slow * 2.5,
                TailAngle = mood switch
                {
                    PetMood.Focused or PetMood.Refreshed => -48 + quick * 14,
                    PetMood.Waiting or PetMood.Calm => -42 + slow * 7,
                    _ => -18,
                },
            },
            CompanionKind.Muru => pose with
            {
                HeadAngle = mood is PetMood.Sleepy or PetMood.Tired ? 8 : slow * 2,
            },
            CompanionKind.Tori => pose with
            {
                LeftPartAngle = mood switch
                {
                    PetMood.Focused or PetMood.Refreshed => -(22 + quick * 30),
                    PetMood.Waiting or PetMood.Calm => -(18 + slow * 8),
                    _ => -8,
                },
                RightPartAngle = mood switch
                {
                    PetMood.Focused or PetMood.Refreshed => 22 + quick * 30,
                    PetMood.Waiting or PetMood.Calm => 18 + slow * 8,
                    _ => 8,
                },
            },
            CompanionKind.Pico => pose with
            {
                LeftPartAngle = mood is PetMood.Sleepy or PetMood.Tired ? -18 : -slow * 3,
                RightPartAngle = mood is PetMood.Sleepy or PetMood.Tired ? 18 : slow * 3,
                TailAngle = 42 + slow * 7,
            },
            _ => pose,
        };
    }

    private static CompanionPose StaticPose(CompanionKind kind, PetMood mood)
    {
        var pose = new CompanionPose(
            0,
            0,
            0,
            ShowWorkProp: mood == PetMood.Focused,
            ShowSleepMark: mood is PetMood.Sleepy or PetMood.Tired,
            ShowAlert: mood == PetMood.Tired,
            ShowCelebration: mood == PetMood.Refreshed);

        return kind switch
        {
            CompanionKind.Mimo => mood switch
            {
                PetMood.Waiting => pose with { LeftPartAngle = 17, RightPartAngle = -17 },
                PetMood.Calm => pose with { LeftPartAngle = 16, RightPartAngle = -16 },
                PetMood.Focused => pose with { LeftPartAngle = 22, RightPartAngle = -22 },
                PetMood.Sleepy => pose with
                {
                    LeftPartAngle = 24,
                    RightPartAngle = -24,
                    LeftLegAngle = 8,
                    RightLegAngle = -8,
                },
                PetMood.Tired => pose with
                {
                    LeftPartAngle = 34,
                    RightPartAngle = -34,
                    LeftLegAngle = 12,
                    RightLegAngle = -12,
                },
                PetMood.Refreshed => pose with
                {
                    LeftPartAngle = 16,
                    RightPartAngle = -132,
                    LeftLegAngle = -4,
                    RightLegAngle = 4,
                },
                _ => pose,
            },
            CompanionKind.Lumi => pose with
            {
                HeadAngle = mood switch
                {
                    PetMood.Focused => -8,
                    PetMood.Sleepy => 10,
                    PetMood.Tired => 18,
                    PetMood.Refreshed => -4,
                    _ => -2,
                },
                EffectOpacity = mood == PetMood.Tired ? 0.52 : 1,
            },
            CompanionKind.Bori => pose with
            {
                HeadAngle = mood == PetMood.Tired ? 9 : 0,
                TailAngle = mood switch
                {
                    PetMood.Focused or PetMood.Refreshed => -48,
                    PetMood.Sleepy or PetMood.Tired => -18,
                    _ => -42,
                },
            },
            CompanionKind.Muru => pose with
            {
                HeadAngle = mood is PetMood.Sleepy or PetMood.Tired ? 8 : 0,
            },
            CompanionKind.Tori => pose with
            {
                LeftPartAngle = mood is PetMood.Sleepy or PetMood.Tired
                    ? -8
                    : mood is PetMood.Focused or PetMood.Refreshed ? -22 : -18,
                RightPartAngle = mood is PetMood.Sleepy or PetMood.Tired
                    ? 8
                    : mood is PetMood.Focused or PetMood.Refreshed ? 22 : 18,
            },
            CompanionKind.Pico => pose with
            {
                LeftPartAngle = mood is PetMood.Sleepy or PetMood.Tired ? -18 : 0,
                RightPartAngle = mood is PetMood.Sleepy or PetMood.Tired ? 18 : 0,
                TailAngle = 42,
            },
            _ => pose,
        };
    }
}
