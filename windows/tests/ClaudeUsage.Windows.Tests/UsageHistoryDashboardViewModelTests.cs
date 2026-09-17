using System.IO;
using ClaudeUsage.Core.History;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;

namespace ClaudeUsage.Windows.Tests;

public sealed class UsageHistoryDashboardViewModelTests
{
    [Fact]
    public void ScopeBuildsOnlyRequestedSeriesAndCalculatesResetSummary()
    {
        using var fixture = new HistoryFixture();
        var now = DateTimeOffset.Now;
        fixture.Store.Record(
            new UsageHistorySnapshot(claudeFiveHour: 50, openAIFiveHour: 10),
            now.AddMinutes(-30),
            force: true);
        fixture.Store.Record(
            new UsageHistorySnapshot(claudeFiveHour: 20, openAIFiveHour: 30),
            now.AddMinutes(-20),
            force: true);

        using var viewModel = fixture.CreateViewModel();
        viewModel.Scope = UsageHistoryProviderScope.Claude;

        Assert.NotEmpty(viewModel.Series);
        Assert.All(viewModel.Series, series => Assert.Equal(UsageProvider.Claude, series.Provider));
        Assert.Equal("50%", viewModel.PeakText);
        Assert.Equal("-30.0%p", viewModel.ChangeText);
        Assert.Equal("2", viewModel.SampleCountText);
        Assert.Equal("1", viewModel.ResetCountText);
        Assert.True(viewModel.HasChartData);
    }

    [Fact]
    public void HourRangeExcludesOlderSamples()
    {
        using var fixture = new HistoryFixture();
        var now = DateTimeOffset.Now;
        fixture.Store.Record(
            new UsageHistorySnapshot(openAIFiveHour: 8),
            now.AddHours(-2),
            force: true);
        fixture.Store.Record(
            new UsageHistorySnapshot(openAIFiveHour: 22),
            now.AddMinutes(-20),
            force: true);

        using var viewModel = fixture.CreateViewModel();
        viewModel.Range = UsageHistoryRange.Hour;

        Assert.Equal("1", viewModel.SampleCountText);
        Assert.Equal("22%", viewModel.PeakText);
        Assert.All(viewModel.Series, series => Assert.Single(series.Points));
    }

    [Fact]
    public void StoreChangesRefreshOpenDashboardState()
    {
        using var fixture = new HistoryFixture();
        using var viewModel = fixture.CreateViewModel();
        Assert.False(viewModel.HasSamples);
        Assert.False(viewModel.HasChartData);

        fixture.Store.Record(
            new UsageHistorySnapshot(claudeWeekly: 42),
            DateTimeOffset.Now,
            force: true);

        Assert.True(viewModel.HasSamples);
        Assert.True(viewModel.HasChartData);
        Assert.Equal("1", viewModel.SampleCountText);

        fixture.Store.Clear();

        Assert.False(viewModel.HasSamples);
        Assert.False(viewModel.HasChartData);
        Assert.Equal("0", viewModel.SampleCountText);
    }

    [Fact]
    public void SeriesPaletteOrderMatchesTheMacDashboard()
    {
        using var fixture = new HistoryFixture();
        fixture.Store.Record(
            new UsageHistorySnapshot(
                claudeFiveHour: 48,
                claudeWeekly: 20,
                openAIFiveHour: 30,
                openAIWeekly: 17,
                claudeModelCounters: [new UsageHistoryCounter("fable", "Claude Fable", 45)],
                openAIModelCounters: [new UsageHistoryCounter("spark", "Codex Spark", 12)]),
            DateTimeOffset.Now,
            force: true);

        using var viewModel = fixture.CreateViewModel();

        Assert.Equal(
            [
                "claude-five-hour",
                "claude-weekly",
                "codex-five-hour",
                "codex-weekly",
                "claude-fable",
                "codex-spark",
            ],
            viewModel.Series.Select(series => series.Id));
    }

    private sealed class HistoryFixture : IDisposable
    {
        private readonly string _directory;

        public HistoryFixture()
        {
            _directory = Path.Combine(Path.GetTempPath(), $"ClaudeUsage-dashboard-{Guid.NewGuid():N}");
            Directory.CreateDirectory(_directory);
            Store = new UsageHistoryStore(Path.Combine(_directory, "history.json"));
            Service = new UsageHistoryService(Store, new NoopLocalTokenService());
        }

        public UsageHistoryStore Store { get; }

        public UsageHistoryService Service { get; }

        public UsageHistoryDashboardViewModel CreateViewModel() =>
            new(Service, new AppSettings { Language = AppLanguage.English });

        public void Dispose()
        {
            try
            {
                Directory.Delete(_directory, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    private sealed class NoopLocalTokenService : IClaudeLocalTokenUsageService
    {
        public Task<ClaudeLocalTokenUsage?> FetchAsync(
            DateTimeOffset? now = null,
            CancellationToken cancellationToken = default) =>
            Task.FromResult<ClaudeLocalTokenUsage?>(null);
    }
}
