using ClaudeUsage.Core.History;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using System.IO;
using System.Net.Http;

namespace ClaudeUsage.Windows.Tests;

public sealed class CountdownParityTests
{
    private static readonly DateTimeOffset Now = new(2026, 7, 13, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void FormatterMatchesMacCountdownTextGrammar()
    {
        Assert.Equal(
            UsageCountdownFormatter.UnavailableText,
            UsageCountdownFormatter.Format(null, Now, isWeekly: false, "Resetting"));
        Assert.Equal(
            "Resetting",
            UsageCountdownFormatter.Format(Now, Now, isWeekly: false, "Resetting"));
        Assert.Equal(
            "27:04:05",
            UsageCountdownFormatter.Format(
                Now.AddHours(27).AddMinutes(4).AddSeconds(5),
                Now,
                isWeekly: false,
                "Resetting"));
        Assert.Equal(
            "8d 2h 3m",
            UsageCountdownFormatter.Format(
                Now.AddDays(8).AddHours(2).AddMinutes(3).AddSeconds(59),
                Now,
                isWeekly: true,
                "Resetting"));
    }

    [Fact]
    public void TickUpdatesFlyoutCounterAndWidgetWithoutReplacingProviderSnapshot()
    {
        var settings = new AppSettings { Language = AppLanguage.English };
        var usage = new UsageViewModel(settings);
        var counter = new UsageCounterViewModel(
            "five-hour",
            "Codex overall",
            "5 hours",
            35,
            Now.AddHours(1).AddMinutes(2).AddSeconds(3),
            isWeekly: false,
            Now,
            "Resetting");
        usage.Counters.Add(counter);
        var companion = new CompanionViewModel(language: AppLanguage.English);
        using var widget = new WidgetViewModel(usage, settings, companion);

        var itemNotifications = 0;
        counter.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(UsageCounterViewModel.ResetText))
            {
                itemNotifications++;
            }
        };

        usage.UpdateCountdowns(Now.AddSeconds(1));

        Assert.Equal("1:02:02", counter.ResetText);
        Assert.Equal("1:02:02", widget.Codex.Metrics.Single().ResetText);
        Assert.Equal(1, itemNotifications);
        Assert.Null(usage.LastCodexSnapshot);
    }

    [Fact]
    public void WeeklyTickUsesOneSecondCadenceButOnlyChangesAtMinuteBoundary()
    {
        var counter = new UsageCounterViewModel(
            "weekly",
            "Weekly",
            "Weekly",
            20,
            Now.AddDays(2).AddHours(3).AddMinutes(4).AddSeconds(5),
            isWeekly: true,
            Now,
            "Resetting");

        Assert.Equal("2d 3h 4m", counter.ResetText);
        Assert.False(counter.UpdateCountdown(Now.AddSeconds(1), "Resetting"));
        Assert.Equal("2d 3h 4m", counter.ResetText);
        Assert.True(counter.UpdateCountdown(Now.AddSeconds(6), "Resetting"));
        Assert.Equal("2d 3h 3m", counter.ResetText);
    }

    [Fact]
    public async Task CoordinatorRunsCountdownWithoutNetworkAndStopsItOnDispose()
    {
        var settings = new AppSettings { Language = AppLanguage.English };
        var usage = new UsageViewModel(settings);
        var counter = new UsageCounterViewModel(
            "five-hour",
            "Codex overall",
            "5 hours",
            35,
            Now.AddSeconds(10),
            isWeekly: false,
            Now,
            "Resetting");
        usage.Counters.Add(counter);

        var clockCalls = 0;
        DateTimeOffset NextNow() => Now.AddSeconds(Interlocked.Increment(ref clockCalls) - 1);
        var firstTimerTick = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        counter.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(UsageCounterViewModel.ResetText)
                && counter.ResetText == "0:00:09")
            {
                firstTimerTick.TrySetResult();
            }
        };

        using var httpClient = new HttpClient();
        var historyPath = Path.Combine(
            Path.GetTempPath(),
            $"claude-usage-countdown-{Guid.NewGuid():N}.json");
        var companion = new CompanionViewModel(language: AppLanguage.English);
        var coordinator = new UsageCoordinator(
            new CodexExecutableLocator(settings),
            new CodexAppServerClient(),
            new ClaudeUsageService(httpClient, new EmptyCookieStore()),
            new UsageHistoryService(new UsageHistoryStore(historyPath)),
            usage,
            companion,
            settings,
            externalRefreshEnabled: false,
            countdownInterval: TimeSpan.FromMilliseconds(10),
            nowProvider: NextNow);

        coordinator.Start();
        await firstTimerTick.Task.WaitAsync(TimeSpan.FromSeconds(2));

        coordinator.Dispose();
        await coordinator.CountdownCompletion.WaitAsync(TimeSpan.FromSeconds(2));
        var callsAfterDispose = Volatile.Read(ref clockCalls);
        await Task.Delay(50);

        Assert.NotEqual("0:00:10", counter.ResetText);
        Assert.Equal(callsAfterDispose, Volatile.Read(ref clockCalls));
        Assert.True(callsAfterDispose >= 2);
    }

    private sealed class EmptyCookieStore : IClaudeCookieStore
    {
        public Task<string?> LoadAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<string?>(null);

        public Task SaveAsync(string cookieHeader, CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task ClearAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task<bool> ClearIfMatchesAsync(
            string expectedCookieHeader,
            CancellationToken cancellationToken = default) => Task.FromResult(false);
    }
}
