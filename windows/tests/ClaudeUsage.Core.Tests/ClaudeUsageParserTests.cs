using System.Text.Json;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Core.Parsing;

namespace ClaudeUsage.Core.Tests;

public sealed class ClaudeUsageParserTests
{
    [Fact]
    public void Parse_NormalizesKnownDynamicAndExtraUsageValues()
    {
        var usage = ClaudeUsageParser.Parse(ReadFixture("claude-nested-fable.json"));

        Assert.Equal(17, usage.FiveHour?.Utilization);
        Assert.Equal(42, usage.SevenDay?.Utilization);
        Assert.Equal(8, usage.SevenDaySonnet?.Utilization);
        Assert.Equal(11, usage.SevenDayOpus?.Utilization);

        var future = Assert.Single(usage.AdditionalSevenDayWindows);
        Assert.Equal("seven_day_future_model", future.Key);
        Assert.Equal(12.5, future.Value.Utilization);

        var extra = Assert.IsType<ClaudeExtraUsage>(usage.ExtraUsage);
        Assert.True(extra.IsEnabled);
        Assert.Equal(100.5, extra.MonthlyLimit);
        Assert.Equal(20.25, extra.UsedCredits);
        Assert.Equal(50, extra.Utilization);
        Assert.Equal("USD", extra.Currency);
    }

    [Fact]
    public void Parse_SelectsNestedFableRejectsFiveHourAndUsesTrustedWeeklyReset()
    {
        var usage = ClaudeUsageParser.Parse(ReadFixture("claude-nested-fable.json"));

        var fable = Assert.IsType<ClaudeUsageWindow>(usage.SevenDayFable);
        Assert.Equal(43, fable.Utilization);
        Assert.NotEqual(99, fable.Utilization);
        Assert.Equal(usage.SevenDay?.ResetsAt, fable.ResetsAt);
    }

    [Theory]
    [InlineData("used_percent", "0.37")]
    [InlineData("percentage", "37")]
    [InlineData("percent", "0.37")]
    public void Parse_AcceptsDocumentedNestedFablePercentageKeys(string key, string value)
    {
        var json = $$$"""
            {
              "five_hour": {"utilization": 10},
              "seven_day": {
                "utilization": 20,
                "resets_at": "2026-07-20T00:00:00Z"
              },
              "limits": [{
                "scope": {"model": {"display_name": "Fable"}},
                "weekly": {"{{{key}}}": "{{{value}}}"}
              }]
            }
            """;

        var usage = ClaudeUsageParser.Parse(json);

        Assert.Equal(37, usage.SevenDayFable?.Utilization);
        Assert.Equal(usage.SevenDay?.ResetsAt, usage.SevenDayFable?.ResetsAt);
    }

    [Fact]
    public void Parse_PrefersNonZeroWeeklyFableRatioOverZeroDecoy()
    {
        var usage = ClaudeUsageParser.Parse(
            """
            {
              "five_hour": {"utilization": 55},
              "seven_day": {
                "utilization": 66,
                "resets_at": "2026-07-20T00:00:00Z"
              },
              "limits": [{
                "name": "Fable",
                "usage": {"utilization": 0},
                "weekly": {
                  "used": "25",
                  "limit": "100",
                  "resets_at": "2026-07-20T00:00:00Z"
                },
                "five_hour": {"utilization": 91}
              }]
            }
            """);

        Assert.Equal(25, usage.SevenDayFable?.Utilization);
    }

    [Fact]
    public void Parse_RejectsFableCandidateWhoseMetadataIdentifiesFiveHourWindow()
    {
        var usage = ClaudeUsageParser.Parse(
            """
            {
              "five_hour": {"utilization": 10},
              "seven_day": {"utilization": 20},
              "limits": [{
                "name": "Fable",
                "quota": {
                  "type": "five_hour",
                  "percentage": 87
                },
                "weekly": {
                  "percentage": 31
                }
              }]
            }
            """);

        Assert.Equal(31, usage.SevenDayFable?.Utilization);
    }

    [Fact]
    public void Parse_NeverSubstitutesFiveHourPercentageForMissingFableWeeklyUsage()
    {
        var usage = ClaudeUsageParser.Parse(
            """
            {
              "five_hour": {"utilization": 12},
              "seven_day": {"utilization": 23},
              "limits": [{
                "scope": {"model": {"display_name": "Fable"}},
                "five_hour": {"utilization": 94}
              }]
            }
            """);

        Assert.Null(usage.SevenDayFable);
    }

    [Fact]
    public void Parse_DoesNotUseResetFromMalformedWeeklyBaseAsTrustedReset()
    {
        var usage = ClaudeUsageParser.Parse(
            """
            {
              "five_hour": {"utilization": 12},
              "seven_day": {
                "utilization": "bad-number",
                "resets_at": "2026-07-20T00:00:00Z"
              },
              "seven_day_fable": {
                "utilization": 33,
                "resets_at": "2026-07-21T00:00:00Z"
              }
            }
            """);

        Assert.Null(usage.SevenDay);
        Assert.Equal(
            DateTimeOffset.Parse("2026-07-21T00:00:00Z"),
            usage.SevenDayFable?.ResetsAt);
    }

    [Fact]
    public void Parse_DoesNotLetOneFableEntryTaintSiblingModelEntries()
    {
        var usage = ClaudeUsageParser.Parse(
            """
            {
              "five_hour": {"utilization": 12},
              "seven_day": {"utilization": 23},
              "limits": {
                "entries": [
                  {
                    "scope": {"model": {"display_name": "Fable"}},
                    "weekly": {"utilization": 21}
                  },
                  {
                    "scope": {"model": {"display_name": "Other Model"}},
                    "weekly": {"utilization": 88}
                  }
                ]
              }
            }
            """);

        Assert.Equal(21, usage.SevenDayFable?.Utilization);
    }

    [Fact]
    public void Parse_MalformedOptionalCountersDoNotDestroyBaseUsage()
    {
        var usage = ClaudeUsageParser.Parse(ReadFixture("claude-malformed-optionals.json"));

        Assert.Equal(22, usage.FiveHour?.Utilization);
        Assert.Equal(61, usage.SevenDay?.Utilization);
        Assert.Null(usage.SevenDaySonnet);
        Assert.Null(usage.SevenDayOpus);
        Assert.Null(usage.SevenDayOmelette);
        Assert.Equal(9, usage.AdditionalSevenDayWindows["seven_day_future_valid"].Utilization);
        Assert.DoesNotContain("seven_day_future_broken", usage.AdditionalSevenDayWindows.Keys);
        Assert.NotNull(usage.ExtraUsage);
        Assert.Equal(0, usage.ExtraUsage?.MonthlyLimit);
    }

    [Fact]
    public void Parse_TopLevelFableStillFollowsTrustedWeeklyReset()
    {
        var usage = ClaudeUsageParser.Parse(
            """
            {
              "five_hour": {"utilization": 10},
              "seven_day": {
                "utilization": 20,
                "resets_at": "2026-07-20T00:00:00Z"
              },
              "seven_day_fable": {
                "utilization": "0.44",
                "resets_at": "2026-07-19T00:00:00Z"
              }
            }
            """);

        Assert.Equal(44, usage.SevenDayFable?.Utilization);
        Assert.Equal(usage.SevenDay?.ResetsAt, usage.SevenDayFable?.ResetsAt);
    }

    [Fact]
    public void Parse_AllowsOneValidBaseWindowForPartialRollouts()
    {
        var usage = ClaudeUsageParser.Parse(
            """
            {
              "five_hour": {"utilization": "bad-number"},
              "seven_day": {"utilization": "0.19"}
            }
            """);

        Assert.Null(usage.FiveHour);
        Assert.Equal(19, usage.SevenDay?.Utilization);
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("{}")]
    [InlineData("{\"five_hour\":null,\"seven_day\":{}}")]
    [InlineData("{\"limits\":[{\"name\":\"Fable\",\"weekly\":{\"utilization\":44}}]}")]
    public void Parse_RejectsResponsesWithoutATrustworthyBaseWindow(string json)
    {
        Assert.Throws<JsonException>(() => ClaudeUsageParser.Parse(json));
    }

    [Fact]
    public void Counters_ExposeKnownAndDynamicModelsWithoutHardcodingFutureNames()
    {
        var usage = ClaudeUsageParser.Parse(ReadFixture("claude-nested-fable.json"));

        Assert.Contains(usage.Counters, counter => counter.Id == "five_hour" && !counter.IsWeekly);
        Assert.Contains(usage.Counters, counter => counter.Id == "seven_day_fable" && counter.DisplayName == "Claude Fable");
        Assert.Contains(
            usage.Counters,
            counter => counter.Id == "seven_day_future_model"
                && counter.DisplayName == "Claude Future Model");
    }

    private static string ReadFixture(string fileName) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", fileName));
}
