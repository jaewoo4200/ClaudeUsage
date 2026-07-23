namespace ClaudeUsage.Core.History;

public sealed record UsageHistoryOptions
{
    public TimeSpan MinimumSampleInterval { get; init; } = TimeSpan.FromMinutes(5);

    public TimeSpan RetentionInterval { get; init; } = TimeSpan.FromDays(14);

    public int MaximumSamples { get; init; } = 4_200;

    public double ResetDropThreshold { get; init; } = 15;

    public TimeSpan TrendWindow { get; init; } = TimeSpan.FromHours(1);

    public TimeSpan RefreshedDuration { get; init; } = TimeSpan.FromMinutes(30);

    public int MaximumTrendPoints { get; init; } = 24;

    internal void Validate()
    {
        if (MinimumSampleInterval < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(MinimumSampleInterval));
        }

        if (RetentionInterval <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(RetentionInterval));
        }

        if (MaximumSamples <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(MaximumSamples));
        }

        if (!double.IsFinite(ResetDropThreshold) || ResetDropThreshold <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(ResetDropThreshold));
        }

        if (TrendWindow <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(TrendWindow));
        }

        if (RefreshedDuration < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(RefreshedDuration));
        }

        if (MaximumTrendPoints <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(MaximumTrendPoints));
        }
    }
}
