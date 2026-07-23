using System.Globalization;
using System.Text.Json;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Core.Parsing;

public static class ClaudeUsageParser
{
    private static readonly string[] PercentKeys =
    [
        "utilization",
        "usage_percentage",
        "usage_percent",
        "used_percentage",
        "used_percent",
        "percentage",
        "percent",
        "percent_used",
    ];

    private static readonly string[] UsedKeys =
    [
        "used",
        "used_credits",
        "used_tokens",
        "current",
        "consumed",
        "value",
    ];

    private static readonly string[] LimitKeys =
    [
        "limit",
        "monthly_limit",
        "token_limit",
        "max",
        "total",
        "quota",
    ];

    private static readonly string[] ResetKeys =
    [
        "resets_at",
        "reset_at",
        "resetsAt",
        "resetAt",
        "reset_time",
        "resetTime",
    ];

    private static readonly HashSet<string> KnownUsageKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "five_hour",
        "seven_day",
        "seven_day_sonnet",
        "seven_day_opus",
        "seven_day_omelette",
        "seven_day_fable",
        "extra_usage",
    };

    private static readonly HashSet<string> IdentityKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "id",
        "key",
        "name",
        "title",
        "label",
        "model",
        "model_name",
        "modelName",
        "display_name",
        "displayName",
        "slug",
        "type",
    };

    public static ClaudeUsageData Parse(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        using var document = JsonDocument.Parse(json);
        return Parse(document.RootElement);
    }

    public static ClaudeUsageData Parse(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException("The Claude usage response must be a JSON object.");
        }

        var fiveHour = ParseTopLevelWindow(root, "five_hour");
        var sevenDay = ParseTopLevelWindow(root, "seven_day");

        // An arbitrary object (or a response whose only usable value is a nested model
        // decoy) must not be accepted as an authenticated quota snapshot. One valid base
        // window is enough to retain a partially rolled-out response.
        if (fiveHour is null && sevenDay is null)
        {
            throw new JsonException(
                "The Claude usage response does not contain a trustworthy base usage window.");
        }

        var sonnet = ParseTopLevelWindow(root, "seven_day_sonnet");
        var opus = ParseTopLevelWindow(root, "seven_day_opus");
        var omelette = ParseTopLevelWindow(root, "seven_day_omelette");
        var directFable = ParseTopLevelWindowCandidate(root, "seven_day_fable", confidence: 110);

        Candidate? extractedFable = null;
        WalkForFable(
            root,
            path: [],
            inheritedFableContext: false,
            weeklyReset: sevenDay?.ResetsAt,
            ref extractedFable);

        var selectedFable = BetterCandidate(directFable, extractedFable, sevenDay?.ResetsAt);
        var fable = selectedFable is null
            ? null
            : new ClaudeUsageWindow(
                selectedFable.Window.Utilization,
                sevenDay?.ResetsAt ?? selectedFable.Window.ResetsAt);

        var additional = new Dictionary<string, ClaudeUsageWindow>(StringComparer.Ordinal);
        foreach (var property in root.EnumerateObject())
        {
            if (KnownUsageKeys.Contains(property.Name)
                || !property.Name.StartsWith("seven_day_", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var candidate = CreateDirectCandidate(
                property.Value,
                [property.Name],
                confidence: 100);
            if (candidate is not null)
            {
                additional[property.Name] = candidate.Window;
            }
        }

        return new ClaudeUsageData(
            fiveHour,
            sevenDay,
            sonnet,
            opus,
            omelette,
            fable,
            ParseExtraUsage(root),
            additional);
    }

    private static ClaudeUsageWindow? ParseTopLevelWindow(JsonElement root, string key) =>
        ParseTopLevelWindowCandidate(root, key, confidence: 100)?.Window;

    private static Candidate? ParseTopLevelWindowCandidate(
        JsonElement root,
        string key,
        int confidence)
    {
        return TryGetProperty(root, key, out var element)
            ? CreateDirectCandidate(element, [key], confidence)
            : null;
    }

    private static ClaudeExtraUsage? ParseExtraUsage(JsonElement root)
    {
        if (!TryGetProperty(root, "extra_usage", out var extra)
            || extra.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        return new ClaudeExtraUsage(
            ReadBoolean(extra, "is_enabled") ?? false,
            ReadNumber(extra, "monthly_limit") ?? 0,
            ReadNumber(extra, "used_credits") ?? 0,
            NormalizePercent(ReadNumber(extra, "utilization") ?? 0),
            ReadString(extra, "currency"));
    }

    private static void WalkForFable(
        JsonElement value,
        IReadOnlyList<string> path,
        bool inheritedFableContext,
        DateTimeOffset? weeklyReset,
        ref Candidate? best)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
            {
                var broadContainer = IsBroadUsageContainer(value);
                var currentContext = inheritedFableContext
                    || PathContains(path, "fable")
                    // Do not let a Fable entry elsewhere in the response taint the root
                    // base windows. A nested Fable-scoped container may legitimately
                    // expose both five-hour and weekly children, however.
                    || (!(broadContainer && path.Count == 0) && ContainsFableIdentity(value));

                if (currentContext && !IsFiveHourPath(path))
                {
                    var candidate = CreateDirectCandidate(
                        value,
                        path,
                        confidence: 100,
                        rejectFiveHourPath: true);
                    if (IsBetter(candidate, best, weeklyReset))
                    {
                        best = candidate;
                    }
                }

                foreach (var property in value.EnumerateObject())
                {
                    WalkForFable(
                        property.Value,
                        Append(path, property.Name),
                        currentContext,
                        weeklyReset,
                        ref best);
                }

                break;
            }
            case JsonValueKind.Array:
            {
                var index = 0;
                foreach (var child in value.EnumerateArray())
                {
                    WalkForFable(
                        child,
                        Append(path, index.ToString(CultureInfo.InvariantCulture)),
                        inheritedFableContext,
                        weeklyReset,
                        ref best);
                    index++;
                }

                break;
            }
        }
    }

    private static Candidate? CreateDirectCandidate(
        JsonElement element,
        IReadOnlyList<string> path,
        int confidence,
        bool rejectFiveHourPath = false)
    {
        if (element.ValueKind != JsonValueKind.Object
            || (rejectFiveHourPath && (IsFiveHourPath(path) || IdentifiesFiveHourWindow(element))))
        {
            return null;
        }

        Candidate? best = null;
        for (var index = 0; index < PercentKeys.Length; index++)
        {
            var key = PercentKeys[index];
            if (!TryGetProperty(element, key, out var raw)
                || !TryReadNumber(raw, out var value)
                || value < 0)
            {
                continue;
            }

            var keyConfidence = key.Equals("utilization", StringComparison.OrdinalIgnoreCase)
                ? confidence
                : confidence - 10;
            var candidate = new Candidate(
                new ClaudeUsageWindow(NormalizePercent(value), ReadReset(element)),
                keyConfidence,
                Append(path, key));
            if (IsBetter(candidate, best, weeklyReset: null))
            {
                best = candidate;
            }
        }

        foreach (var usedKey in UsedKeys)
        {
            if (!TryGetProperty(element, usedKey, out var usedElement)
                || !TryReadNumber(usedElement, out var used)
                || used < 0)
            {
                continue;
            }

            foreach (var limitKey in LimitKeys)
            {
                if (!TryGetProperty(element, limitKey, out var limitElement)
                    || !TryReadNumber(limitElement, out var limit)
                    || limit <= 0)
                {
                    continue;
                }

                var candidate = new Candidate(
                    new ClaudeUsageWindow(NormalizePercent(used / limit), ReadReset(element)),
                    confidence - 20,
                    Append(Append(path, usedKey), limitKey));
                if (IsBetter(candidate, best, weeklyReset: null))
                {
                    best = candidate;
                }
            }
        }

        return best;
    }

    private static Candidate? BetterCandidate(
        Candidate? first,
        Candidate? second,
        DateTimeOffset? weeklyReset)
    {
        if (first is null)
        {
            return second;
        }

        return IsBetter(second, first, weeklyReset) ? second : first;
    }

    private static bool IsBetter(
        Candidate? candidate,
        Candidate? current,
        DateTimeOffset? weeklyReset)
    {
        if (candidate is null)
        {
            return false;
        }

        if (current is null)
        {
            return true;
        }

        var candidateScore = candidate.Confidence + ContextScore(candidate, weeklyReset);
        var currentScore = current.Confidence + ContextScore(current, weeklyReset);

        if (candidate.Window.Utilization > 0 && current.Window.Utilization == 0)
        {
            return candidateScore >= currentScore - 80;
        }

        if (candidate.Window.Utilization == 0 && current.Window.Utilization > 0)
        {
            return candidateScore > currentScore + 80;
        }

        if (Math.Abs(candidateScore - currentScore) > 10)
        {
            return candidateScore > currentScore;
        }

        return candidateScore != currentScore
            ? candidateScore > currentScore
            : candidate.Window.Utilization > current.Window.Utilization;
    }

    private static int ContextScore(Candidate candidate, DateTimeOffset? weeklyReset)
    {
        if (IsFiveHourPath(candidate.Path))
        {
            return -1_000;
        }

        var score = 0;
        if (PathContains(candidate.Path, "fable"))
        {
            score += 100;
        }

        if (PathContains(candidate.Path, "seven_day")
            || PathContains(candidate.Path, "weekly")
            || PathContains(candidate.Path, "week"))
        {
            score += 30;
        }

        if (candidate.Window.ResetsAt is { } candidateReset && weeklyReset is { } trustedReset)
        {
            if (Math.Abs((candidateReset - trustedReset).TotalSeconds) < 60)
            {
                score += 60;
            }
            else
            {
                score -= 120;
            }
        }

        return score;
    }

    private static bool ContainsFableIdentity(
        JsonElement value,
        int depth = 0,
        bool insideIdentityContainer = false)
    {
        if (depth >= 5)
        {
            return false;
        }

        if (value.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in value.EnumerateObject())
            {
                if (property.Name.Contains("fable", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }

                if (IdentityKeys.Contains(property.Name)
                    && ScalarText(property.Value)?.Contains("fable", StringComparison.OrdinalIgnoreCase) == true)
                {
                    return true;
                }

                var isIdentityContainer = insideIdentityContainer
                    || property.Name.Equals("scope", StringComparison.OrdinalIgnoreCase)
                    || property.Name.Equals("identity", StringComparison.OrdinalIgnoreCase)
                    || property.Name.Equals("metadata", StringComparison.OrdinalIgnoreCase)
                    || property.Name.Equals("model", StringComparison.OrdinalIgnoreCase);
                if (isIdentityContainer
                    && ContainsFableIdentity(
                        property.Value,
                        depth + 1,
                        insideIdentityContainer: true))
                {
                    return true;
                }
            }
        }
        else if (insideIdentityContainer && value.ValueKind == JsonValueKind.Array)
        {
            foreach (var child in value.EnumerateArray())
            {
                if (ContainsFableIdentity(
                        child,
                        depth + 1,
                        insideIdentityContainer: true))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static bool IsBroadUsageContainer(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        foreach (var property in value.EnumerateObject())
        {
            if (property.Name.Equals("five_hour", StringComparison.OrdinalIgnoreCase)
                || property.Name.Equals("fiveHour", StringComparison.OrdinalIgnoreCase)
                || property.Name.Equals("seven_day", StringComparison.OrdinalIgnoreCase)
                || property.Name.Equals("sevenDay", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static DateTimeOffset? ReadReset(JsonElement element)
    {
        foreach (var key in ResetKeys)
        {
            if (!TryGetProperty(element, key, out var raw))
            {
                continue;
            }

            var text = ScalarText(raw);
            if (text is not null
                && DateTimeOffset.TryParse(
                    text,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal,
                    out var reset))
            {
                return reset;
            }
        }

        return null;
    }

    private static string? ReadString(JsonElement element, string key) =>
        TryGetProperty(element, key, out var value) ? ScalarText(value) : null;

    private static double? ReadNumber(JsonElement element, string key) =>
        TryGetProperty(element, key, out var value) && TryReadNumber(value, out var result)
            ? result
            : null;

    private static bool? ReadBoolean(JsonElement element, string key)
    {
        if (!TryGetProperty(element, key, out var value))
        {
            return null;
        }

        if (value.ValueKind is JsonValueKind.True or JsonValueKind.False)
        {
            return value.GetBoolean();
        }

        return bool.TryParse(ScalarText(value), out var result) ? result : null;
    }

    private static bool TryReadNumber(JsonElement value, out double result)
    {
        var parsed = value.ValueKind switch
        {
            JsonValueKind.Number => value.TryGetDouble(out result),
            JsonValueKind.String => double.TryParse(
                value.GetString(),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out result),
            _ => SetFailedNumber(out result),
        };

        return parsed && double.IsFinite(result);
    }

    private static bool SetFailedNumber(out double result)
    {
        result = 0;
        return false;
    }

    private static double NormalizePercent(double value) =>
        value is >= 0 and <= 1 ? value * 100 : value;

    private static string? ScalarText(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.String => value.GetString(),
        JsonValueKind.Number => value.GetRawText(),
        JsonValueKind.True => bool.TrueString,
        JsonValueKind.False => bool.FalseString,
        _ => null,
    };

    private static bool TryGetProperty(JsonElement element, string name, out JsonElement value)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                {
                    value = property.Value;
                    return true;
                }
            }
        }

        value = default;
        return false;
    }

    private static bool IsFiveHourPath(IReadOnlyList<string> path)
    {
        var normalized = string.Join('.', path).ToLowerInvariant();
        return normalized.Contains("five_hour", StringComparison.Ordinal)
            || normalized.Contains("fivehour", StringComparison.Ordinal)
            || normalized.Contains("5_hour", StringComparison.Ordinal);
    }

    private static bool IdentifiesFiveHourWindow(JsonElement element)
    {
        var hintKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "id",
            "key",
            "name",
            "label",
            "type",
            "window",
            "window_type",
            "windowType",
            "period",
        };

        foreach (var property in element.EnumerateObject())
        {
            if (!hintKeys.Contains(property.Name))
            {
                continue;
            }

            var normalized = ScalarText(property.Value)?.ToLowerInvariant();
            if (normalized?.Contains("five_hour", StringComparison.Ordinal) == true
                || normalized?.Contains("fivehour", StringComparison.Ordinal) == true
                || normalized?.Contains("5_hour", StringComparison.Ordinal) == true
                || normalized?.Contains("5-hour", StringComparison.Ordinal) == true)
            {
                return true;
            }
        }

        return false;
    }

    private static bool PathContains(IReadOnlyList<string> path, string value) =>
        string.Join('.', path).Contains(value, StringComparison.OrdinalIgnoreCase);

    private static IReadOnlyList<string> Append(IReadOnlyList<string> path, string value)
    {
        var result = new string[path.Count + 1];
        for (var index = 0; index < path.Count; index++)
        {
            result[index] = path[index];
        }

        result[^1] = value;
        return result;
    }

    private sealed record Candidate(
        ClaudeUsageWindow Window,
        int Confidence,
        IReadOnlyList<string> Path);
}
