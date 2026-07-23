using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Core.Tests;

public sealed class OpenAIUsageDataTests
{
    [Fact]
    public void Counters_UsesDurationToResolveWindowKindAndSuppressesDuplicateIds()
    {
        var usage = new OpenAIUsageData(
            "business_plus",
            new OpenAIRateLimit(
                new OpenAIUsageWindow(20, null, null, 604_800),
                new OpenAIUsageWindow(30, null, null, 604_800)),
            null,
            []);

        var counter = Assert.Single(usage.Counters);
        Assert.Equal(OpenAIWindowKind.Weekly, counter.Kind);
        Assert.Equal("openai-standard-weekly", counter.Id);
        Assert.Equal("Business Plus", usage.PlanDisplayName);
    }

    [Fact]
    public void ResetCredits_UsesAvailableCountOnlyWhenDetailedCreditsAreAbsent()
    {
        var credits = new OpenAIRateLimitResetCredits(3, []);

        Assert.Equal(3, credits.UsableCount(DateTimeOffset.UtcNow));
    }

    [Fact]
    public void TokenActivity_LooksUpExactCalendarBucket()
    {
        var activity = new OpenAITokenActivity(
            summary: null,
            [
                new OpenAITokenDailyBucket("2026-07-09", 10),
                new OpenAITokenDailyBucket("2026-07-10", 20),
            ]);

        Assert.Equal(20, activity.TokensOn(new DateOnly(2026, 7, 10)));
        Assert.Null(activity.TokensOn(new DateOnly(2026, 7, 11)));
    }
}
