using System.Globalization;
using System.Text.Json;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Core.Parsing;

public static class CodexUsageMapper
{
    public static OpenAIUsageData Parse(string rateLimitsJson, string? tokenUsageJson = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(rateLimitsJson);

        using var rateLimitsDocument = JsonDocument.Parse(rateLimitsJson);
        if (string.IsNullOrWhiteSpace(tokenUsageJson))
        {
            return Parse(rateLimitsDocument.RootElement, tokenUsageResult: null);
        }

        try
        {
            using var tokenUsageDocument = JsonDocument.Parse(tokenUsageJson);
            return Parse(rateLimitsDocument.RootElement, tokenUsageDocument.RootElement);
        }
        catch (JsonException)
        {
            // Token activity is supplementary. Invalid or unsupported token payloads must not
            // discard a valid rate-limit snapshot.
            return Parse(rateLimitsDocument.RootElement, tokenUsageResult: null);
        }
    }

    public static OpenAIUsageData Parse(
        JsonElement rateLimitsResult,
        JsonElement? tokenUsageResult)
    {
        var rawRateLimits = ParseRateLimitsResult(rateLimitsResult);
        var rawTokenUsage = tokenUsageResult is { ValueKind: JsonValueKind.Object } tokenElement
            ? ParseTokenUsageResult(tokenElement)
            : null;

        return Map(rawRateLimits, rawTokenUsage);
    }

    public static OpenAIUsageData Map(
        CodexRateLimitsResult rateLimits,
        CodexTokenUsageResult? tokenUsage = null)
    {
        ArgumentNullException.ThrowIfNull(rateLimits);

        var indexed = rateLimits.RateLimitsByLimitId;
        var standardSelection = SelectStandardLimit(rateLimits.RateLimits, indexed);
        var standard = standardSelection.Limit;
        if (standard is null || (standard.Primary is null && standard.Secondary is null))
        {
            throw new JsonException(
                "The Codex rate-limit result does not contain a valid standard usage window.");
        }

        OpenAIRateLimit? codeReview = null;
        var additional = new List<OpenAIAdditionalRateLimit>();

        foreach (var entry in indexed.OrderBy(entry => entry.Key, StringComparer.Ordinal))
        {
            if (IsSelectedStandard(entry.Key, entry.Value, standardSelection))
            {
                continue;
            }

            var identity = $"{entry.Key} {entry.Value.LimitId} {entry.Value.LimitName}";
            if (IsCodeReview(identity))
            {
                codeReview ??= MapRateLimit(entry.Value);
                continue;
            }

            additional.Add(new OpenAIAdditionalRateLimit(
                entry.Value.LimitName,
                entry.Key,
                MapRateLimit(entry.Value)));
        }

        var activity = tokenUsage is null
            ? null
            : new OpenAITokenActivity(
                tokenUsage.Summary is null
                    ? null
                    : new OpenAITokenUsageSummary(
                        tokenUsage.Summary.LifetimeTokens,
                        tokenUsage.Summary.PeakDailyTokens,
                        tokenUsage.Summary.LongestRunningTurnSeconds,
                        tokenUsage.Summary.CurrentStreakDays,
                        tokenUsage.Summary.LongestStreakDays),
                tokenUsage.DailyUsageBuckets.Select(bucket =>
                    new OpenAITokenDailyBucket(bucket.StartDate, bucket.Tokens)));

        return new OpenAIUsageData(
            standard?.PlanType,
            standard is null ? null : MapRateLimit(standard),
            codeReview,
            additional,
            activity,
            MapResetCredits(rateLimits.RateLimitResetCredits));
    }

    public static CodexRateLimitsResult ParseRateLimitsResult(JsonElement element)
    {
        EnsureObject(element, "The Codex rate-limit result must be a JSON object.");

        var rateLimits = TryGetProperty(element, "rateLimits", out var rateLimitsElement)
            ? ParseRateLimit(rateLimitsElement)
            : null;

        var indexed = new Dictionary<string, CodexRateLimit>(StringComparer.Ordinal);
        if (TryGetProperty(element, "rateLimitsByLimitId", out var indexedElement)
            && indexedElement.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in indexedElement.EnumerateObject())
            {
                var parsed = ParseRateLimit(property.Value);
                if (parsed is not null)
                {
                    indexed[property.Name] = parsed;
                }
            }
        }

        var resetCredits = TryGetProperty(element, "rateLimitResetCredits", out var resetElement)
            ? ParseResetCredits(resetElement)
            : null;

        return new CodexRateLimitsResult(rateLimits, indexed, resetCredits);
    }

    public static CodexTokenUsageResult ParseTokenUsageResult(JsonElement element)
    {
        EnsureObject(element, "The Codex token-usage result must be a JSON object.");

        CodexTokenUsageSummary? summary = null;
        if (TryGetProperty(element, "summary", out var summaryElement)
            && summaryElement.ValueKind == JsonValueKind.Object)
        {
            summary = new CodexTokenUsageSummary(
                ReadNullableInt64(summaryElement, "lifetimeTokens"),
                ReadNullableInt64(summaryElement, "peakDailyTokens"),
                ReadNullableInt64(summaryElement, "longestRunningTurnSec"),
                ReadNullableInt32(summaryElement, "currentStreakDays"),
                ReadNullableInt32(summaryElement, "longestStreakDays"));
        }

        var buckets = new List<CodexTokenDailyBucket>();
        if (TryGetProperty(element, "dailyUsageBuckets", out var bucketsElement)
            && bucketsElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var bucketElement in bucketsElement.EnumerateArray())
            {
                if (bucketElement.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }

                var startDate = ReadOptionalString(bucketElement, "startDate");
                var tokens = ReadNullableInt64(bucketElement, "tokens");
                if (startDate is not null && tokens is not null)
                {
                    buckets.Add(new CodexTokenDailyBucket(startDate, tokens.Value));
                }
            }
        }

        return new CodexTokenUsageResult(summary, buckets.AsReadOnly());
    }

    private static CodexRateLimit? ParseRateLimit(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        return new CodexRateLimit(
            ReadOptionalString(element, "limitId"),
            ReadOptionalString(element, "limitName"),
            TryGetProperty(element, "primary", out var primary) ? ParseWindow(primary) : null,
            TryGetProperty(element, "secondary", out var secondary) ? ParseWindow(secondary) : null,
            ReadOptionalString(element, "planType"));
    }

    private static CodexRateLimitWindow? ParseWindow(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var usedPercent = ReadNullableDouble(element, "usedPercent");
        if (usedPercent is null)
        {
            return null;
        }

        return new CodexRateLimitWindow(
            usedPercent.Value,
            ReadNullableInt32(element, "windowDurationMins"),
            ReadNullableInt64(element, "resetsAt"));
    }

    private static CodexRateLimitResetCredits? ParseResetCredits(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var credits = new List<CodexRateLimitResetCredit>();
        if (TryGetProperty(element, "credits", out var creditsElement)
            && creditsElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var creditElement in creditsElement.EnumerateArray())
            {
                if (creditElement.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }

                var id = ReadOptionalString(creditElement, "id");
                var status = ReadOptionalString(creditElement, "status");
                if (id is null || status is null)
                {
                    continue;
                }

                credits.Add(new CodexRateLimitResetCredit(
                    id,
                    ReadOptionalString(creditElement, "resetType"),
                    status,
                    ReadNullableInt64(creditElement, "grantedAt"),
                    ReadNullableInt64(creditElement, "expiresAt"),
                    ReadOptionalString(creditElement, "title"),
                    ReadOptionalString(creditElement, "description")));
            }
        }

        return new CodexRateLimitResetCredits(
            ReadNullableInt32(element, "availableCount") ?? 0,
            credits.AsReadOnly());
    }

    private static (string? Key, CodexRateLimit? Limit) SelectStandardLimit(
        CodexRateLimit? direct,
        IReadOnlyDictionary<string, CodexRateLimit> indexed)
    {
        if (direct is not null)
        {
            return (null, direct);
        }

        if (indexed.TryGetValue("codex", out var keyedCodex))
        {
            return ("codex", keyedCodex);
        }

        var identifiedCodex = indexed
            .Where(entry => string.Equals(entry.Value.LimitId, "codex", StringComparison.OrdinalIgnoreCase))
            .OrderBy(entry => entry.Key, StringComparer.Ordinal)
            .FirstOrDefault();
        if (identifiedCodex.Value is not null)
        {
            return (identifiedCodex.Key, identifiedCodex.Value);
        }

        var unnamed = indexed
            .Where(entry => string.IsNullOrWhiteSpace(entry.Value.LimitName))
            .OrderBy(entry => entry.Key, StringComparer.Ordinal)
            .FirstOrDefault();
        return unnamed.Value is null ? (null, null) : (unnamed.Key, unnamed.Value);
    }

    private static bool IsSelectedStandard(
        string key,
        CodexRateLimit candidate,
        (string? Key, CodexRateLimit? Limit) selection)
    {
        if (selection.Limit is null)
        {
            return false;
        }

        if (selection.Key is not null)
        {
            return string.Equals(key, selection.Key, StringComparison.Ordinal);
        }

        if (string.Equals(key, "codex", StringComparison.Ordinal)
            && string.IsNullOrWhiteSpace(candidate.LimitName))
        {
            return true;
        }

        return selection.Limit.LimitId is not null
            && (string.Equals(key, selection.Limit.LimitId, StringComparison.Ordinal)
                || string.Equals(candidate.LimitId, selection.Limit.LimitId, StringComparison.Ordinal));
    }

    private static bool IsCodeReview(string identity)
    {
        var normalized = identity.ToLowerInvariant();
        return normalized.Contains("code_review", StringComparison.Ordinal)
            || normalized.Contains("code review", StringComparison.Ordinal);
    }

    private static OpenAIRateLimit MapRateLimit(CodexRateLimit rateLimit) =>
        new(MapWindow(rateLimit.Primary), MapWindow(rateLimit.Secondary));

    private static OpenAIUsageWindow? MapWindow(CodexRateLimitWindow? window)
    {
        if (window is null)
        {
            return null;
        }

        int? durationSeconds = null;
        if (window.WindowDurationMinutes is not null)
        {
            try
            {
                durationSeconds = checked(window.WindowDurationMinutes.Value * 60);
            }
            catch (OverflowException)
            {
                durationSeconds = null;
            }
        }

        return new OpenAIUsageWindow(
            window.UsedPercent,
            UnixTime(window.ResetsAt),
            ResetAfterSeconds: null,
            durationSeconds);
    }

    private static OpenAIRateLimitResetCredits? MapResetCredits(CodexRateLimitResetCredits? credits) =>
        credits is null
            ? null
            : new OpenAIRateLimitResetCredits(
                credits.AvailableCount,
                credits.Credits.Select(credit => new OpenAIRateLimitResetCredit(
                    credit.Id,
                    credit.ResetType,
                    credit.Status,
                    UnixTime(credit.GrantedAt),
                    UnixTime(credit.ExpiresAt),
                    credit.Title,
                    credit.Description)));

    private static DateTimeOffset? UnixTime(long? seconds)
    {
        if (seconds is not > 0)
        {
            return null;
        }

        try
        {
            return DateTimeOffset.FromUnixTimeSeconds(seconds.Value);
        }
        catch (ArgumentOutOfRangeException)
        {
            return null;
        }
    }

    private static string? ReadOptionalString(JsonElement element, string propertyName)
    {
        if (!TryGetProperty(element, propertyName, out var value)
            || value.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        var text = value.GetString()?.Trim();
        return string.IsNullOrEmpty(text) ? null : text;
    }

    private static double? ReadNullableDouble(JsonElement element, string propertyName)
    {
        if (!TryGetProperty(element, propertyName, out var value))
        {
            return null;
        }

        double parsed;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out parsed))
        {
            return double.IsFinite(parsed) ? parsed : null;
        }

        return value.ValueKind == JsonValueKind.String
            && double.TryParse(
                value.GetString(),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out parsed)
            && double.IsFinite(parsed)
                ? parsed
                : null;
    }

    private static int? ReadNullableInt32(JsonElement element, string propertyName)
    {
        var number = ReadNullableDouble(element, propertyName);
        return number.HasValue && number.Value >= int.MinValue && number.Value <= int.MaxValue
            ? (int)number.Value
            : null;
    }

    private static long? ReadNullableInt64(JsonElement element, string propertyName)
    {
        if (!TryGetProperty(element, propertyName, out var value))
        {
            return null;
        }

        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var integer))
        {
            return integer;
        }

        if (value.ValueKind == JsonValueKind.String
            && long.TryParse(
                value.GetString(),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out integer))
        {
            return integer;
        }

        var number = ReadNullableDouble(element, propertyName);
        return number.HasValue && number.Value >= long.MinValue && number.Value <= long.MaxValue
            ? (long)number.Value
            : null;
    }

    private static bool TryGetProperty(
        JsonElement element,
        string propertyName,
        out JsonElement value)
    {
        value = default;
        return element.ValueKind == JsonValueKind.Object
            && element.TryGetProperty(propertyName, out value);
    }

    private static void EnsureObject(JsonElement element, string message)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException(message);
        }
    }
}
