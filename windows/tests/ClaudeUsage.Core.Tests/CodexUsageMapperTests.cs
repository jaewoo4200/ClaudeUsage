using System.Text.Json;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Core.Parsing;

namespace ClaudeUsage.Core.Tests;

public sealed class CodexUsageMapperTests
{
    [Fact]
    public void Parse_MapsDocumentedRateLimitsTokenBucketsAndCredits()
    {
        var usage = CodexUsageMapper.Parse(
            ReadFixture("codex-rate-limits.json"),
            ReadFixture("codex-token-usage.json"));

        Assert.Equal("Pro", usage.PlanDisplayName);
        Assert.Equal(28, usage.RateLimit?.PrimaryWindow?.UsedPercent);
        Assert.Equal(604_800, usage.RateLimit?.SecondaryWindow?.LimitWindowSeconds);
        Assert.Equal(
            DateTimeOffset.FromUnixTimeSeconds(1_783_904_355),
            usage.RateLimit?.SecondaryWindow?.ResetAt);

        var model = Assert.Single(usage.AdditionalRateLimits);
        Assert.Equal("GPT-5.6-Sol", model.LimitName);
        Assert.Equal(123_456, usage.TokenActivity?.TokensOn(new DateOnly(2026, 7, 10)));
        Assert.Equal(1_000_000, usage.TokenActivity?.Summary?.LifetimeTokens);
        Assert.Equal(120, usage.TokenActivity?.Summary?.LongestRunningTurnSeconds);

        var credits = Assert.IsType<OpenAIRateLimitResetCredits>(usage.RateLimitResetCredits);
        var beforeExpiry = DateTimeOffset.FromUnixTimeSeconds(1_784_000_000);
        Assert.Equal(1, credits.AvailableCount);
        Assert.Equal(1, credits.UsableCount(beforeExpiry));
        Assert.Equal("credit-available", Assert.Single(credits.UsableCredits(beforeExpiry)).Id);
        Assert.Equal(
            DateTimeOffset.FromUnixTimeSeconds(1_784_334_787),
            credits.EarliestExpiry(beforeExpiry));
        Assert.Equal(0, credits.UsableCount(DateTimeOffset.FromUnixTimeSeconds(1_785_000_000)));
    }

    [Theory]
    [InlineData("decoy-first")]
    [InlineData("codex-first")]
    public void Parse_SelectsCodexStandardLimitWithoutDependingOnDictionaryOrder(string order)
    {
        var decoy = """
            "aaa_unnamed": {
              "limitId": "aaa_unnamed",
              "limitName": null,
              "primary": {"usedPercent": 91, "windowDurationMins": 300},
              "planType": "free"
            }
            """;
        var codex = """
            "codex": {
              "limitId": "codex",
              "limitName": null,
              "primary": {"usedPercent": 28, "windowDurationMins": 300},
              "planType": "pro"
            }
            """;
        var entries = order == "decoy-first"
            ? $"{decoy},{codex}"
            : $"{codex},{decoy}";
        var json = $$"""
            {
              "rateLimitsByLimitId": {
                {{entries}}
              }
            }
            """;

        var usage = CodexUsageMapper.Parse(json);

        Assert.Equal("pro", usage.PlanType);
        Assert.Equal(28, usage.RateLimit?.PrimaryWindow?.UsedPercent);
    }

    [Fact]
    public void Parse_PreservesUnknownModelNamesAndBuildsDynamicCounters()
    {
        var usage = CodexUsageMapper.Parse(
            """
            {
              "rateLimitsByLimitId": {
                "gpt_5_6_terra": {
                  "limitId": "gpt_5_6_terra",
                  "limitName": "GPT-5.6-Terra",
                  "primary": {"usedPercent": 7, "windowDurationMins": 300}
                },
                "codex": {
                  "limitId": "codex",
                  "limitName": null,
                  "primary": {"usedPercent": 8, "windowDurationMins": 300},
                  "planType": "enterprise"
                },
                "gpt_5_6_sol": {
                  "limitId": "gpt_5_6_sol",
                  "limitName": "GPT-5.6-Sol",
                  "primary": {"usedPercent": 24, "windowDurationMins": 300},
                  "secondary": {"usedPercent": 11, "windowDurationMins": 10080}
                }
              }
            }
            """);

        Assert.Equal("Enterprise", usage.PlanDisplayName);
        Assert.Equal(
            ["GPT-5.6-Sol", "GPT-5.6-Sol", "GPT-5.6-Terra"],
            usage.Counters
                .Where(counter => counter.Scope == OpenAIUsageCounterScope.Model)
                .Select(counter => counter.Name));
        Assert.Contains(
            usage.Counters,
            counter => counter.Id == "openai-model-gpt-5-6-sol-weekly");
        Assert.Contains(
            usage.Counters,
            counter => counter.Id == "openai-model-gpt-5-6-terra-five-hour");
    }

    [Fact]
    public void Parse_AllowsMissingTokenActivity()
    {
        var usage = CodexUsageMapper.Parse(ReadFixture("codex-rate-limits.json"));

        Assert.Null(usage.TokenActivity);
        Assert.Null(usage.TodayTokens);
        Assert.Equal(28, usage.RateLimit?.PrimaryWindow?.UsedPercent);
    }

    [Fact]
    public void Parse_IgnoresMalformedOptionalTokenPayload()
    {
        var usage = CodexUsageMapper.Parse(
            ReadFixture("codex-rate-limits.json"),
            "not-json");

        Assert.Null(usage.TokenActivity);
        Assert.Equal(28, usage.RateLimit?.PrimaryWindow?.UsedPercent);
    }

    [Fact]
    public void Parse_AcceptsNumericStringsAcrossWindowsCreditsAndTokenActivity()
    {
        var rateJson = """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {
                  "usedPercent": "22.5",
                  "windowDurationMins": "300",
                  "resetsAt": "1783634265"
                },
                "planType": "pro"
              },
              "rateLimitResetCredits": {
                "availableCount": "2",
                "credits": [
                  {
                    "id": "credit-1",
                    "status": "available",
                    "grantedAt": "1781742787",
                    "expiresAt": "1784334787"
                  }
                ]
              }
            }
            """;
        var tokenJson = """
            {
              "summary": {
                "lifetimeTokens": "1000000",
                "peakDailyTokens": "250000",
                "longestRunningTurnSec": "120",
                "currentStreakDays": "5",
                "longestStreakDays": "9"
              },
              "dailyUsageBuckets": [
                {"startDate": "2026-07-10", "tokens": "123456"}
              ]
            }
            """;

        var usage = CodexUsageMapper.Parse(rateJson, tokenJson);

        Assert.Equal(22.5, usage.RateLimit?.PrimaryWindow?.UsedPercent);
        Assert.Equal(18_000, usage.RateLimit?.PrimaryWindow?.LimitWindowSeconds);
        Assert.Equal(
            DateTimeOffset.FromUnixTimeSeconds(1_783_634_265),
            usage.RateLimit?.PrimaryWindow?.ResetAt);
        Assert.Equal(2, usage.RateLimitResetCredits?.AvailableCount);
        Assert.Equal(1_000_000, usage.TokenActivity?.Summary?.LifetimeTokens);
        Assert.Equal(123_456, usage.TokenActivity?.TokensOn(new DateOnly(2026, 7, 10)));
    }

    [Fact]
    public void Parse_MalformedOptionalLimitsAndBucketsDoNotDestroyBaseUsage()
    {
        var usage = CodexUsageMapper.Parse(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": {
                  "usedPercent": 22,
                  "windowDurationMins": 300
                }
              },
              "rateLimitsByLimitId": {
                "broken_primitive": 42,
                "broken_window": {
                  "limitName": "Broken",
                  "primary": "not-an-object"
                },
                "gpt_future": {
                  "limitName": "GPT-Future",
                  "primary": {
                    "usedPercent": "bad-number",
                    "windowDurationMins": "bad-number"
                  }
                }
              },
              "rateLimitResetCredits": {
                "availableCount": 1,
                "credits": [null, 42, {"id": "missing-status"}]
              }
            }
            """,
            """
            {
              "dailyUsageBuckets": [
                null,
                {"startDate": "2026-07-10", "tokens": "bad-number"},
                {"tokens": 50}
              ]
            }
            """);

        Assert.Equal(22, usage.RateLimit?.PrimaryWindow?.UsedPercent);
        Assert.Empty(usage.TokenActivity?.DailyBuckets ?? []);
        Assert.Empty(usage.RateLimitResetCredits?.Credits ?? []);
        Assert.Contains(usage.AdditionalRateLimits, limit => limit.LimitName == "GPT-Future");
        Assert.DoesNotContain(usage.Counters, counter => counter.Name == "GPT-Future");
    }

    [Fact]
    public void Parse_SeparatesCodeReviewFromModelLimits()
    {
        var usage = CodexUsageMapper.Parse(
            """
            {
              "rateLimitsByLimitId": {
                "codex": {
                  "limitId": "codex",
                  "primary": {"usedPercent": 10, "windowDurationMins": 300}
                },
                "codex_code_review": {
                  "limitId": "review",
                  "limitName": "Automated Review",
                  "primary": {"usedPercent": 40, "windowDurationMins": 10080}
                },
                "other_review": {
                  "limitName": "Code Review Burst",
                  "primary": {"usedPercent": 30, "windowDurationMins": 300}
                }
              }
            }
            """);

        Assert.NotNull(usage.CodeReviewRateLimit);
        Assert.DoesNotContain(
            usage.AdditionalRateLimits,
            limit => limit.MeteredFeature?.Contains("review", StringComparison.OrdinalIgnoreCase) == true);
        Assert.Contains(
            usage.Counters,
            counter => counter.Scope == OpenAIUsageCounterScope.CodeReview);
    }

    [Fact]
    public void Parse_JsonElementOverloadExposesTheWpfBoundary()
    {
        using var rateDocument = JsonDocument.Parse(ReadFixture("codex-rate-limits.json"));
        using var tokenDocument = JsonDocument.Parse(ReadFixture("codex-token-usage.json"));

        var usage = CodexUsageMapper.Parse(
            rateDocument.RootElement,
            tokenDocument.RootElement);

        Assert.Equal("Pro", usage.PlanDisplayName);
        Assert.Equal(4, usage.Counters.Count);
    }

    [Fact]
    public void Parse_RejectsNonObjectRateLimitPayload()
    {
        Assert.Throws<JsonException>(() => CodexUsageMapper.Parse("[]"));
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"rateLimits\":{}}")]
    [InlineData("{\"rateLimits\":{\"primary\":{}}}")]
    [InlineData("{\"rateLimits\":{\"primary\":{\"usedPercent\":\"not-a-number\"}}}")]
    [InlineData("{\"rateLimitsByLimitId\":{\"future\":{\"limitName\":\"GPT-Future\",\"primary\":{\"usedPercent\":10}}}}")]
    public void Parse_RejectsMissingOrMalformedStandardRateLimit(string json)
    {
        Assert.Throws<JsonException>(() => CodexUsageMapper.Parse(json));
    }

    private static string ReadFixture(string fileName) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", fileName));
}
