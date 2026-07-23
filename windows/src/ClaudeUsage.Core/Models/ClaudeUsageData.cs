namespace ClaudeUsage.Core.Models;

public sealed record ClaudeUsageWindow(double Utilization, DateTimeOffset? ResetsAt);

public sealed record ClaudeExtraUsage(
    bool IsEnabled,
    double MonthlyLimit,
    double UsedCredits,
    double Utilization,
    string? Currency);

public sealed record ClaudeUsageCounter(
    string Id,
    string DisplayName,
    ClaudeUsageWindow Window,
    bool IsWeekly,
    bool IsModel);

public sealed class ClaudeUsageData
{
    public ClaudeUsageData(
        ClaudeUsageWindow? fiveHour,
        ClaudeUsageWindow? sevenDay,
        ClaudeUsageWindow? sevenDaySonnet = null,
        ClaudeUsageWindow? sevenDayOpus = null,
        ClaudeUsageWindow? sevenDayOmelette = null,
        ClaudeUsageWindow? sevenDayFable = null,
        ClaudeExtraUsage? extraUsage = null,
        IReadOnlyDictionary<string, ClaudeUsageWindow>? additionalSevenDayWindows = null)
    {
        FiveHour = fiveHour;
        SevenDay = sevenDay;
        SevenDaySonnet = sevenDaySonnet;
        SevenDayOpus = sevenDayOpus;
        SevenDayOmelette = sevenDayOmelette;
        SevenDayFable = sevenDayFable;
        ExtraUsage = extraUsage;
        AdditionalSevenDayWindows = new System.Collections.ObjectModel.ReadOnlyDictionary<string, ClaudeUsageWindow>(
            new Dictionary<string, ClaudeUsageWindow>(
                additionalSevenDayWindows ?? new Dictionary<string, ClaudeUsageWindow>(),
                StringComparer.Ordinal));
    }

    public ClaudeUsageWindow? FiveHour { get; }

    public ClaudeUsageWindow? SevenDay { get; }

    public ClaudeUsageWindow? SevenDaySonnet { get; }

    public ClaudeUsageWindow? SevenDayOpus { get; }

    public ClaudeUsageWindow? SevenDayOmelette { get; }

    public ClaudeUsageWindow? SevenDayFable { get; }

    public ClaudeExtraUsage? ExtraUsage { get; }

    public IReadOnlyDictionary<string, ClaudeUsageWindow> AdditionalSevenDayWindows { get; }

    public IReadOnlyList<ClaudeUsageCounter> Counters
    {
        get
        {
            var counters = new List<ClaudeUsageCounter>();
            AddCounter(counters, "five_hour", "Claude", FiveHour, isWeekly: false, isModel: false);
            AddCounter(counters, "seven_day", "Claude", SevenDay, isWeekly: true, isModel: false);
            AddCounter(counters, "seven_day_sonnet", "Claude Sonnet", SevenDaySonnet, isWeekly: true, isModel: true);
            AddCounter(counters, "seven_day_opus", "Claude Opus", SevenDayOpus, isWeekly: true, isModel: true);
            AddCounter(counters, "seven_day_omelette", "Claude Design", SevenDayOmelette, isWeekly: true, isModel: true);
            AddCounter(counters, "seven_day_fable", "Claude Fable", SevenDayFable, isWeekly: true, isModel: true);

            foreach (var (id, window) in AdditionalSevenDayWindows.OrderBy(entry => entry.Key, StringComparer.Ordinal))
            {
                AddCounter(counters, id, DynamicDisplayName(id), window, isWeekly: true, isModel: true);
            }

            return counters.AsReadOnly();
        }
    }

    private static void AddCounter(
        ICollection<ClaudeUsageCounter> counters,
        string id,
        string displayName,
        ClaudeUsageWindow? window,
        bool isWeekly,
        bool isModel)
    {
        if (window is not null)
        {
            counters.Add(new ClaudeUsageCounter(id, displayName, window, isWeekly, isModel));
        }
    }

    private static string DynamicDisplayName(string id)
    {
        const string Prefix = "seven_day_";
        var source = id.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase)
            ? id[Prefix.Length..]
            : id;
        var words = source
            .Replace('-', ' ')
            .Replace('_', ' ')
            .Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return words.Length == 0
            ? "Claude model"
            : "Claude " + string.Join(" ", words.Select(TitleCase));
    }

    private static string TitleCase(string value) => value.Length switch
    {
        0 => value,
        1 => value.ToUpperInvariant(),
        _ => char.ToUpperInvariant(value[0]) + value[1..],
    };
}

public enum ClaudePlan
{
    Free,
    Pro,
    Max5X,
    Max20X,
    Team,
    Enterprise,
    Unknown,
}

public static class ClaudePlanExtensions
{
    public static string DisplayName(this ClaudePlan plan) => plan switch
    {
        ClaudePlan.Free => "Free",
        ClaudePlan.Pro => "Pro",
        ClaudePlan.Max5X => "Max 5x",
        ClaudePlan.Max20X => "Max 20x",
        ClaudePlan.Team => "Team",
        ClaudePlan.Enterprise => "Enterprise",
        _ => "-",
    };

    public static string CompactName(this ClaudePlan plan) => plan switch
    {
        ClaudePlan.Max5X => "MAX 5X",
        ClaudePlan.Max20X => "MAX 20X",
        ClaudePlan.Enterprise => "ENT",
        ClaudePlan.Unknown => "-",
        _ => plan.DisplayName().ToUpperInvariant(),
    };

    public static ClaudePlan Parse(IEnumerable<string>? capabilities, string? rateLimitTier)
    {
        var tier = rateLimitTier?.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(tier))
        {
            if (tier.Contains("max_20x", StringComparison.Ordinal))
            {
                return ClaudePlan.Max20X;
            }

            if (tier.Contains("max_5x", StringComparison.Ordinal)
                || tier.Contains("max", StringComparison.Ordinal))
            {
                return ClaudePlan.Max5X;
            }

            if (tier.Contains("pro", StringComparison.Ordinal))
            {
                return ClaudePlan.Pro;
            }

            if (tier.Contains("team", StringComparison.Ordinal))
            {
                return ClaudePlan.Team;
            }

            if (tier.Contains("enterprise", StringComparison.Ordinal))
            {
                return ClaudePlan.Enterprise;
            }
        }

        var normalized = new HashSet<string>(
            capabilities ?? [],
            StringComparer.OrdinalIgnoreCase);
        if (normalized.Contains("claude_max"))
        {
            return ClaudePlan.Max5X;
        }

        if (normalized.Contains("claude_pro"))
        {
            return ClaudePlan.Pro;
        }

        if (normalized.Contains("claude_team"))
        {
            return ClaudePlan.Team;
        }

        if (normalized.Contains("claude_enterprise"))
        {
            return ClaudePlan.Enterprise;
        }

        return normalized.Contains("chat") ? ClaudePlan.Free : ClaudePlan.Unknown;
    }
}

public sealed class ClaudeOrganization
{
    public ClaudeOrganization(
        string id,
        string? name,
        IEnumerable<string>? capabilities,
        string? rateLimitTier)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        Id = id.Trim();
        Name = string.IsNullOrWhiteSpace(name) ? null : name.Trim();
        Capabilities = Array.AsReadOnly((capabilities ?? []).Where(value => !string.IsNullOrWhiteSpace(value)).ToArray());
        RateLimitTier = string.IsNullOrWhiteSpace(rateLimitTier) ? null : rateLimitTier.Trim();
    }

    public string Id { get; }

    public string? Name { get; }

    public IReadOnlyList<string> Capabilities { get; }

    public string? RateLimitTier { get; }

    public ClaudePlan Plan => ClaudePlanExtensions.Parse(Capabilities, RateLimitTier);

    public string PlanDisplayName => Plan.DisplayName();
}

public sealed record ClaudeAccountSnapshot(
    ClaudeOrganization Organization,
    ClaudeUsageData Usage);
