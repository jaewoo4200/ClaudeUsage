using System.Text.Json;
using ClaudeUsage.Core.History;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Core.Tests;

public sealed class UsageHistoryTests
{
    [Fact]
    public void PressureUsesHighestIndividualCounterAndStableTieBreak()
    {
        var snapshot = new UsageHistorySnapshot(
            claudeFiveHour: 41,
            claudeWeekly: 23,
            claudeModelMaximum: 99,
            openAIFiveHour: 43,
            claudeModelCounters:
            [
                new UsageHistoryCounter("seven_day_zeta", "Claude Zeta", 43),
                new UsageHistoryCounter("seven_day_fable", "Claude Fable", 43),
            ]);

        Assert.Equal(43, snapshot.Pressure);
        Assert.Equal("codex-five-hour", snapshot.PressureSource?.Id);
        Assert.Equal(UsageProvider.Codex, snapshot.PressureSource?.Provider);
        Assert.Equal(43, snapshot.PressureFor(UsageProvider.Claude));
        Assert.DoesNotContain(snapshot.PressureSources, source => source.Id == "claude-model-maximum");
    }

    [Fact]
    public void TodayTokensSumAvailableProviders()
    {
        Assert.Null(new UsageHistorySnapshot().TodayTokens);
        Assert.Equal(120, new UsageHistorySnapshot(claudeTodayTokens: 120).TodayTokens);
        Assert.Equal(
            320,
            new UsageHistorySnapshot(claudeTodayTokens: 120, openAITodayTokens: 200).TodayTokens);
    }

    [Fact]
    public void TrendUsesRecentSegmentAndTokenDelta()
    {
        using var fixture = new HistoryFixture();
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

        store.Record(Snapshot(20, 1_000), now.AddHours(-1), force: true);
        store.Record(Snapshot(28, 3_500), now, force: true);

        var trend = store.Trend(now, calendarTimeZone: TimeZoneInfo.Utc);

        Assert.Equal(8, trend.DeltaPercent);
        Assert.Equal(8, trend.PercentPerHour);
        Assert.Equal(2_500, trend.RecentTokenDelta);
        Assert.Equal([20d, 28d], trend.Points);
    }

    [Fact]
    public void ResetStartsNewTrendSegmentAndRefreshesCompanion()
    {
        using var fixture = new HistoryFixture();
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

        store.Record(Snapshot(92, 10_000), now.AddMinutes(-30), force: true);
        store.Record(Snapshot(8, 11_000), now.AddMinutes(-15), force: true);
        store.Record(Snapshot(10, 12_000), now, force: true);

        var trend = store.Trend(now, calendarTimeZone: TimeZoneInfo.Utc);

        Assert.True(trend.ResetDetected);
        Assert.Equal(2, trend.DeltaPercent);
        Assert.Equal(PetMood.Refreshed, PetMoodResolver.Resolve(Snapshot(10, 12_000), trend));
    }

    [Theory]
    [InlineData(25, PetMood.Calm)]
    [InlineData(62, PetMood.Focused)]
    [InlineData(80, PetMood.Sleepy)]
    [InlineData(94, PetMood.Tired)]
    public void BalancedMoodUsesPressure(double pressure, PetMood expected)
    {
        Assert.Equal(expected, PetMoodResolver.Resolve(Snapshot(pressure, null)));
    }

    [Fact]
    public void MoodUsesPaceAndSensitivityThresholds()
    {
        var rapid = new UsageTrend([20, 50], 30, 48, null, false);
        Assert.Equal(PetMood.Tired, PetMoodResolver.Resolve(Snapshot(35, null), rapid));

        var current = Snapshot(42, null);
        Assert.Equal(
            PetMood.Focused,
            PetMoodResolver.Resolve(current, UsageTrend.Empty, MimoSensitivity.Responsive));
        Assert.Equal(
            PetMood.Calm,
            PetMoodResolver.Resolve(current, UsageTrend.Empty, MimoSensitivity.Balanced));
        Assert.Equal(
            PetMood.Calm,
            PetMoodResolver.Resolve(current, UsageTrend.Empty, MimoSensitivity.Relaxed));
    }

    [Fact]
    public void RecordingUsesFiveMinuteCadenceButCapturesReset()
    {
        using var fixture = new HistoryFixture();
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.FromMinutes(5));
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

        Assert.True(store.Record(Snapshot(40, 1_000), now, force: true));
        Assert.False(store.Record(Snapshot(48, 5_000), now.AddMinutes(1)));
        Assert.Single(store.Samples);

        Assert.True(store.Record(Snapshot(15, 5_500), now.AddMinutes(2)));
        Assert.Equal(2, store.Samples.Count);
    }

    [Fact]
    public void RefreshedMoodExpiresThirtyMinutesAfterReset()
    {
        using var fixture = new HistoryFixture();
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

        store.Record(Snapshot(90, null), now.AddMinutes(-40), force: true);
        store.Record(Snapshot(10, null), now.AddMinutes(-35), force: true);
        store.Record(Snapshot(12, null), now, force: true);

        Assert.False(store.Trend(now).ResetDetected);
    }

    [Fact]
    public void RetentionIsBoundedByAgeAndCount()
    {
        using var fixture = new HistoryFixture();
        var store = new UsageHistoryStore(
            fixture.FilePath,
            new UsageHistoryOptions
            {
                MinimumSampleInterval = TimeSpan.Zero,
                RetentionInterval = TimeSpan.FromDays(14),
                MaximumSamples = 3,
            });
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

        store.Record(Snapshot(10, null), now.AddDays(-20), force: true);
        store.Record(Snapshot(20, null), now.AddDays(-2), force: true);
        store.Record(Snapshot(30, null), now.AddDays(-1), force: true);
        store.Record(Snapshot(40, null), now.AddHours(-1), force: true);
        store.Record(Snapshot(50, null), now, force: true);

        Assert.Equal(3, store.Samples.Count);
        Assert.Equal([30d, 40d, 50d], store.Samples.Select(sample => sample.Snapshot.Pressure!.Value));
        Assert.All(store.Samples, sample => Assert.True(sample.Timestamp >= now.AddDays(-14)));
    }

    [Fact]
    public void HistoryPersistsModelCountersAndLoadsLegacySamples()
    {
        using var fixture = new HistoryFixture();
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        var model = new UsageHistoryCounter("seven_day_fable", "Claude Fable", 47);
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);

        store.Record(
            new UsageHistorySnapshot(
                claudeFiveHour: 30,
                claudeWeekly: 20,
                claudeModelMaximum: 47,
                claudeModelCounters: [model]),
            now,
            force: true);

        var reloaded = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);
        Assert.Equal(model, Assert.Single(Assert.Single(reloaded.Samples).ClaudeModelCounters!));

        File.WriteAllText(
            fixture.FilePath,
            "[{\"timestamp\":\"2027-01-15T08:00:00+00:00\",\"claudeFiveHour\":12,\"claudeWeekly\":8}]");
        var legacy = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);
        var legacySample = Assert.Single(legacy.Samples);
        Assert.Equal(12, legacySample.Snapshot.Pressure);
        Assert.Empty(legacySample.Snapshot.ClaudeModelCounters);
    }

    [Fact]
    public void StoreSkipsEmptySnapshotAndClearDeletesOnlyHistoryFile()
    {
        using var fixture = new HistoryFixture();
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);

        Assert.False(store.Record(new UsageHistorySnapshot(), force: true));
        Assert.False(File.Exists(fixture.FilePath));

        store.Record(Snapshot(10, null), force: true);
        Assert.True(File.Exists(fixture.FilePath));
        store.Clear();

        Assert.Empty(store.Samples);
        Assert.False(File.Exists(fixture.FilePath));
    }

    [Fact]
    public void ReopenImmediatelyPrunesExpiredAndOversizedHistory()
    {
        using var fixture = new HistoryFixture();
        var now = DateTimeOffset.Now;
        var samples = new[]
        {
            new UsageHistorySample(now.AddDays(-30), Snapshot(5, null)),
            new UsageHistorySample(now.AddDays(-4), Snapshot(10, null)),
            new UsageHistorySample(now.AddDays(-3), Snapshot(20, null)),
            new UsageHistorySample(now.AddDays(-2), Snapshot(30, null)),
            new UsageHistorySample(now.AddDays(-1), Snapshot(40, null)),
        };
        File.WriteAllText(fixture.FilePath, JsonSerializer.Serialize(samples));

        var options = new UsageHistoryOptions
        {
            MinimumSampleInterval = TimeSpan.Zero,
            RetentionInterval = TimeSpan.FromDays(14),
            MaximumSamples = 3,
        };
        var store = new UsageHistoryStore(fixture.FilePath, options);

        Assert.Equal([20d, 30d, 40d], store.Samples.Select(sample => sample.Snapshot.Pressure!.Value));
        Assert.DoesNotContain(store.Samples, sample => sample.Timestamp < now.AddDays(-14));

        var reloaded = new UsageHistoryStore(fixture.FilePath, options);
        Assert.Equal(3, reloaded.Samples.Count);
    }

    [Fact]
    public void ClearRemovesCrashTemporaryHistoryFiles()
    {
        using var fixture = new HistoryFixture();
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);
        store.Record(Snapshot(10, null), force: true);
        var temporaryPath = Path.Combine(
            Path.GetDirectoryName(fixture.FilePath)!,
            $".{Path.GetFileName(fixture.FilePath)}.deadbeef.tmp");
        File.WriteAllText(temporaryPath, "sensitive-history-remnant");

        store.Clear();

        Assert.False(File.Exists(fixture.FilePath));
        Assert.False(File.Exists(temporaryPath));
    }

    [Fact]
    public void ClearReportsFailureWhenHistoryPathCannotBeDeleted()
    {
        using var fixture = new HistoryFixture();
        Directory.CreateDirectory(fixture.FilePath);
        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);

        var exception = Assert.Throws<IOException>(() => store.Clear());

        Assert.Contains("could not be deleted completely", exception.Message);
        Assert.NotNull(store.LastPersistenceError);
        Assert.True(Directory.Exists(fixture.FilePath));
    }

    [Fact]
    public void LoadIgnoresNullSamplesAndNullModelCounters()
    {
        using var fixture = new HistoryFixture();
        var timestamp = DateTimeOffset.Now;
        var timestampJson = JsonSerializer.Serialize(timestamp);
        File.WriteAllText(
            fixture.FilePath,
            $$"""
            [
              null,
              {
                "timestamp": {{timestampJson}},
                "claudeFiveHour": 21,
                "claudeModelCounters": [
                  null,
                  { "id": "seven_day_fable", "label": "Claude Fable", "utilization": 42 }
                ]
              }
            ]
            """);

        var store = fixture.CreateStore(minimumSampleInterval: TimeSpan.Zero);
        var sample = Assert.Single(store.Samples);

        Assert.Equal(42, sample.Snapshot.Pressure);
        Assert.Equal("seven_day_fable", Assert.Single(sample.Snapshot.ClaudeModelCounters).Id);
    }

    [Fact]
    public void CompanionCatalogAndAnimationCadenceAreStable()
    {
        Assert.Equal(
            [
                CompanionKind.Mimo,
                CompanionKind.Lumi,
                CompanionKind.Kumo,
                CompanionKind.Dot,
                CompanionKind.Navi,
                CompanionKind.Bori,
                CompanionKind.Muru,
                CompanionKind.Tori,
                CompanionKind.Pico,
            ],
            Enum.GetValues<CompanionKind>());
        Assert.Equal(
            ["mimo", "lumi", "kumo", "dot", "navi", "bori", "muru", "tori", "pico"],
            Enum.GetValues<CompanionKind>().Select(kind => kind.Id()));

        var encoded = JsonSerializer.Serialize(Enum.GetValues<CompanionKind>());
        Assert.Equal("[\"mimo\",\"lumi\",\"kumo\",\"dot\",\"navi\",\"bori\",\"muru\",\"tori\",\"pico\"]", encoded);
        Assert.Equal(
            Enum.GetValues<CompanionKind>(),
            JsonSerializer.Deserialize<CompanionKind[]>(encoded));

        Assert.Equal(1.4, MimoAnimationMode.Automatic.UpdateInterval(PetMood.Calm)?.TotalSeconds);
        Assert.Equal(0.45, MimoAnimationMode.Automatic.UpdateInterval(PetMood.Focused)?.TotalSeconds);
        Assert.Equal(0.25, MimoAnimationMode.Lively.UpdateInterval(PetMood.Calm)?.TotalSeconds);
        Assert.Null(MimoAnimationMode.Still.UpdateInterval(PetMood.Focused));
        Assert.Equal(0.22, MimoAnimationMode.Automatic.TransitionDuration(PetMood.Calm).TotalSeconds);
        Assert.Equal(0.16, MimoAnimationMode.Lively.TransitionDuration(PetMood.Calm).TotalSeconds);

        var first = CompanionPoseResolver.Resolve(CompanionKind.Mimo, PetMood.Focused, 100);
        Assert.Equal(first, CompanionPoseResolver.Resolve(CompanionKind.Mimo, PetMood.Focused, 100));
        Assert.NotEqual(first, CompanionPoseResolver.Resolve(CompanionKind.Mimo, PetMood.Focused, 101));
        var reduced = CompanionPoseResolver.Resolve(
            CompanionKind.Mimo,
            PetMood.Refreshed,
            long.MaxValue,
            reducedMotion: true);
        Assert.True(reduced.ShowCelebration);
        Assert.Equal(16, reduced.LeftPartAngle);
        Assert.Equal(-132, reduced.RightPartAngle);
        Assert.Equal(-4, reduced.LeftLegAngle);
        Assert.Equal(4, reduced.RightLegAngle);
    }

    [Fact]
    public void ReducedMotionUsesEachMacCharactersTimeZeroPose()
    {
        var cases = new[]
        {
            new PoseCase(CompanionKind.Mimo, PetMood.Tired, 34, -34, 0, 12, -12, 0, 1),
            new PoseCase(CompanionKind.Lumi, PetMood.Tired, 0, 0, 18, 0, 0, 0, 0.52),
            new PoseCase(CompanionKind.Bori, PetMood.Focused, 0, 0, 0, 0, 0, -48, 1),
            new PoseCase(CompanionKind.Bori, PetMood.Tired, 0, 0, 9, 0, 0, -18, 1),
            new PoseCase(CompanionKind.Muru, PetMood.Sleepy, 0, 0, 8, 0, 0, 0, 1),
            new PoseCase(CompanionKind.Tori, PetMood.Refreshed, -22, 22, 0, 0, 0, 0, 1),
            new PoseCase(CompanionKind.Pico, PetMood.Tired, -18, 18, 0, 0, 0, 42, 1),
            new PoseCase(CompanionKind.Dot, PetMood.Focused, 0, 0, 0, 0, 0, 0, 1),
            new PoseCase(CompanionKind.Navi, PetMood.Calm, 0, 0, 0, 0, 0, 0, 1),
        };

        foreach (var item in cases)
        {
            var pose = CompanionPoseResolver.Resolve(item.Kind, item.Mood, long.MaxValue, reducedMotion: true);
            Assert.Equal(item.LeftPartAngle, pose.LeftPartAngle);
            Assert.Equal(item.RightPartAngle, pose.RightPartAngle);
            Assert.Equal(item.HeadAngle, pose.HeadAngle);
            Assert.Equal(item.LeftLegAngle, pose.LeftLegAngle);
            Assert.Equal(item.RightLegAngle, pose.RightLegAngle);
            Assert.Equal(item.TailAngle, pose.TailAngle);
            Assert.Equal(0, pose.VerticalOffset);
            Assert.Equal(item.EffectOpacity, pose.EffectOpacity);
        }
    }

    private static UsageHistorySnapshot Snapshot(double pressure, long? tokens) => new(
        claudeFiveHour: pressure,
        claudeTodayTokens: tokens);

    private sealed record PoseCase(
        CompanionKind Kind,
        PetMood Mood,
        double LeftPartAngle,
        double RightPartAngle,
        double HeadAngle,
        double LeftLegAngle,
        double RightLegAngle,
        double TailAngle,
        double EffectOpacity);

    private sealed class HistoryFixture : IDisposable
    {
        private readonly string _directory = Path.Combine(
            Path.GetTempPath(),
            $"ClaudeUsage-history-{Guid.NewGuid():N}");

        public HistoryFixture()
        {
            Directory.CreateDirectory(_directory);
        }

        public string FilePath => Path.Combine(_directory, "usage-history.json");

        public UsageHistoryStore CreateStore(TimeSpan minimumSampleInterval) => new(
            FilePath,
            new UsageHistoryOptions { MinimumSampleInterval = minimumSampleInterval });

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
}
