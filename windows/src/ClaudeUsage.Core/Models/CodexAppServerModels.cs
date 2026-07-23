namespace ClaudeUsage.Core.Models;

public sealed record CodexRateLimitsResult(
    CodexRateLimit? RateLimits,
    IReadOnlyDictionary<string, CodexRateLimit> RateLimitsByLimitId,
    CodexRateLimitResetCredits? RateLimitResetCredits);

public sealed record CodexRateLimitResetCredits(
    int AvailableCount,
    IReadOnlyList<CodexRateLimitResetCredit> Credits);

public sealed record CodexRateLimitResetCredit(
    string Id,
    string? ResetType,
    string Status,
    long? GrantedAt,
    long? ExpiresAt,
    string? Title,
    string? Description);

public sealed record CodexRateLimit(
    string? LimitId,
    string? LimitName,
    CodexRateLimitWindow? Primary,
    CodexRateLimitWindow? Secondary,
    string? PlanType);

public sealed record CodexRateLimitWindow(
    double UsedPercent,
    int? WindowDurationMinutes,
    long? ResetsAt);

public sealed record CodexTokenUsageResult(
    CodexTokenUsageSummary? Summary,
    IReadOnlyList<CodexTokenDailyBucket> DailyUsageBuckets);

public sealed record CodexTokenUsageSummary(
    long? LifetimeTokens,
    long? PeakDailyTokens,
    long? LongestRunningTurnSeconds,
    int? CurrentStreakDays,
    int? LongestStreakDays);

public sealed record CodexTokenDailyBucket(string StartDate, long Tokens);
