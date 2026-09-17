using System.Globalization;
using System.Text;

namespace ClaudeUsage.Core.Models;

public enum OpenAIWindowKind
{
    FiveHour,
    Weekly,
}

public static class OpenAIWindowKindExtensions
{
    public static bool IsWeekly(this OpenAIWindowKind kind) => kind == OpenAIWindowKind.Weekly;

    public static OpenAIWindowKind Resolve(int? durationSeconds, OpenAIWindowKind fallback)
    {
        if (durationSeconds is not > 0)
        {
            return fallback;
        }

        if (durationSeconds <= 6 * 60 * 60)
        {
            return OpenAIWindowKind.FiveHour;
        }

        if (durationSeconds >= 6 * 24 * 60 * 60)
        {
            return OpenAIWindowKind.Weekly;
        }

        return fallback;
    }
}

public sealed record OpenAIUsageWindow(
    double UsedPercent,
    DateTimeOffset? ResetAt,
    int? ResetAfterSeconds,
    int? LimitWindowSeconds)
{
    public DateTimeOffset? GetResetTime(DateTimeOffset now)
    {
        if (ResetAt is not null)
        {
            return ResetAt;
        }

        return ResetAfterSeconds is > 0
            ? now.AddSeconds(ResetAfterSeconds.Value)
            : null;
    }
}

public sealed record OpenAIRateLimit(
    OpenAIUsageWindow? PrimaryWindow,
    OpenAIUsageWindow? SecondaryWindow);

public sealed record OpenAIAdditionalRateLimit(
    string? LimitName,
    string? MeteredFeature,
    OpenAIRateLimit? RateLimit);

public enum OpenAIUsageCounterScope
{
    Standard,
    CodeReview,
    Model,
}

public sealed record OpenAIUsageCounter(
    string Id,
    string? Name,
    OpenAIUsageWindow Window,
    OpenAIWindowKind Kind,
    OpenAIUsageCounterScope Scope);

public sealed record OpenAITokenUsageSummary(
    long? LifetimeTokens,
    long? PeakDailyTokens,
    long? LongestRunningTurnSeconds,
    int? CurrentStreakDays,
    int? LongestStreakDays);

public sealed record OpenAITokenDailyBucket(string StartDate, long Tokens);

public sealed class OpenAITokenActivity
{
    public OpenAITokenActivity(
        OpenAITokenUsageSummary? summary,
        IEnumerable<OpenAITokenDailyBucket>? dailyBuckets)
    {
        Summary = summary;
        DailyBuckets = Array.AsReadOnly((dailyBuckets ?? []).ToArray());
    }

    public OpenAITokenUsageSummary? Summary { get; }

    public IReadOnlyList<OpenAITokenDailyBucket> DailyBuckets { get; }

    public long? TokensOn(DateOnly date)
    {
        var key = date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return DailyBuckets.FirstOrDefault(bucket => bucket.StartDate == key)?.Tokens;
    }
}

public sealed record OpenAIRateLimitResetCredit(
    string Id,
    string? ResetType,
    string Status,
    DateTimeOffset? GrantedAt,
    DateTimeOffset? ExpiresAt,
    string? Title,
    string? Description)
{
    public bool IsUsable(DateTimeOffset at) =>
        string.Equals(Status, "available", StringComparison.OrdinalIgnoreCase)
        && (ExpiresAt is null || ExpiresAt > at);
}

public sealed class OpenAIRateLimitResetCredits
{
    public OpenAIRateLimitResetCredits(
        int availableCount,
        IEnumerable<OpenAIRateLimitResetCredit>? credits)
    {
        AvailableCount = Math.Max(0, availableCount);
        Credits = Array.AsReadOnly((credits ?? []).ToArray());
    }

    public int AvailableCount { get; }

    public IReadOnlyList<OpenAIRateLimitResetCredit> Credits { get; }

    public IReadOnlyList<OpenAIRateLimitResetCredit> UsableCredits(DateTimeOffset at) =>
        Credits.Where(credit => credit.IsUsable(at)).ToArray();

    public int UsableCount(DateTimeOffset at) =>
        Credits.Count == 0 ? AvailableCount : UsableCredits(at).Count;

    public DateTimeOffset? EarliestExpiry(DateTimeOffset at) =>
        UsableCredits(at)
            .Where(credit => credit.ExpiresAt is not null)
            .MinBy(credit => credit.ExpiresAt)
            ?.ExpiresAt;
}

public sealed class OpenAIUsageData
{
    public OpenAIUsageData(
        string? planType,
        OpenAIRateLimit? rateLimit,
        OpenAIRateLimit? codeReviewRateLimit,
        IEnumerable<OpenAIAdditionalRateLimit>? additionalRateLimits,
        OpenAITokenActivity? tokenActivity = null,
        OpenAIRateLimitResetCredits? rateLimitResetCredits = null)
    {
        PlanType = NormalizeOptional(planType);
        RateLimit = rateLimit;
        CodeReviewRateLimit = codeReviewRateLimit;
        AdditionalRateLimits = Array.AsReadOnly((additionalRateLimits ?? []).ToArray());
        TokenActivity = tokenActivity;
        RateLimitResetCredits = rateLimitResetCredits;
    }

    public string? PlanType { get; }

    public OpenAIRateLimit? RateLimit { get; }

    public OpenAIRateLimit? CodeReviewRateLimit { get; }

    public IReadOnlyList<OpenAIAdditionalRateLimit> AdditionalRateLimits { get; }

    public OpenAITokenActivity? TokenActivity { get; }

    public OpenAIRateLimitResetCredits? RateLimitResetCredits { get; }

    public string PlanDisplayName => PlanType?.ToLowerInvariant() switch
    {
        null or "" => "-",
        "free" => "Free",
        "go" => "Go",
        "plus" => "Plus",
        "pro" => "Pro",
        "team" => "Team",
        "business" => "Business",
        "enterprise" => "Enterprise",
        "edu" or "education" => "Edu",
        _ => string.Join(
            " ",
            PlanType.Split('_', StringSplitOptions.RemoveEmptyEntries)
                .Select(TitleCaseComponent)),
    };

    public string PlanCompactName => PlanDisplayName.ToUpperInvariant();

    public long? TodayTokens => TokenActivity?.TokensOn(DateOnly.FromDateTime(DateTime.Now));

    public IReadOnlyList<OpenAIUsageCounter> Counters
    {
        get
        {
            var result = new List<OpenAIUsageCounter>();
            var usedIds = new HashSet<string>(StringComparer.Ordinal);

            AppendCounters(
                RateLimit,
                "openai-standard",
                name: null,
                OpenAIUsageCounterScope.Standard,
                result,
                usedIds);
            AppendCounters(
                CodeReviewRateLimit,
                "openai-code-review",
                "Code Review",
                OpenAIUsageCounterScope.CodeReview,
                result,
                usedIds);

            foreach (var entry in AdditionalRateLimits
                         .OrderBy(DisplayName, StringComparer.OrdinalIgnoreCase)
                         .ThenBy(entry => entry.MeteredFeature, StringComparer.Ordinal)
                         .ThenBy(entry => entry.LimitName, StringComparer.Ordinal))
            {
                var source = FirstNonEmpty(entry.MeteredFeature, entry.LimitName) ?? "model";
                var slug = Slug(source);
                AppendCounters(
                    entry.RateLimit,
                    $"openai-model-{(slug.Length == 0 ? "unknown" : slug)}",
                    DisplayName(entry),
                    OpenAIUsageCounterScope.Model,
                    result,
                    usedIds);
            }

            return result.AsReadOnly();
        }
    }

    private static void AppendCounters(
        OpenAIRateLimit? rateLimit,
        string idBase,
        string? name,
        OpenAIUsageCounterScope scope,
        ICollection<OpenAIUsageCounter> result,
        ISet<string> usedIds)
    {
        var candidates = new (OpenAIUsageWindow? Window, OpenAIWindowKind Fallback)[]
        {
            (rateLimit?.PrimaryWindow, OpenAIWindowKind.FiveHour),
            (rateLimit?.SecondaryWindow, OpenAIWindowKind.Weekly),
        };

        foreach (var (window, fallback) in candidates)
        {
            if (window is null)
            {
                continue;
            }

            var kind = OpenAIWindowKindExtensions.Resolve(window.LimitWindowSeconds, fallback);
            var suffix = kind == OpenAIWindowKind.Weekly ? "weekly" : "five-hour";
            var id = $"{idBase}-{suffix}";
            if (!usedIds.Add(id))
            {
                continue;
            }

            result.Add(new OpenAIUsageCounter(id, name, window, kind, scope));
        }
    }

    private static string DisplayName(OpenAIAdditionalRateLimit entry)
    {
        var explicitName = FirstNonEmpty(entry.LimitName);
        if (explicitName is not null)
        {
            return explicitName;
        }

        var feature = FirstNonEmpty(entry.MeteredFeature);
        if (feature is null)
        {
            return "Codex model";
        }

        var words = new string(
                feature.Select(character => char.IsLetterOrDigit(character) ? character : ' ').ToArray())
            .Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return string.Join(" ", words.Select(TitleCaseComponent));
    }

    private static string? FirstNonEmpty(params string?[] values) =>
        values
            .Select(NormalizeOptional)
            .FirstOrDefault(value => value is not null);

    private static string? NormalizeOptional(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }

    private static string TitleCaseComponent(string value) => value.Length switch
    {
        0 => value,
        1 => value.ToUpperInvariant(),
        _ => char.ToUpperInvariant(value[0]) + value[1..],
    };

    private static string Slug(string value)
    {
        var result = new StringBuilder();
        var lastWasDash = false;

        foreach (var character in value.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(character))
            {
                result.Append(character);
                lastWasDash = false;
            }
            else if (!lastWasDash && result.Length > 0)
            {
                result.Append('-');
                lastWasDash = true;
            }
        }

        return result.ToString().Trim('-');
    }
}
