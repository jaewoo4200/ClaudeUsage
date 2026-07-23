namespace ClaudeUsage.Windows.ViewModels;

/// <summary>
/// Mirrors the macOS CountdownText display grammar. The timer cadence belongs
/// to the coordinator; this type only turns a reset instant into visible text.
/// </summary>
internal static class UsageCountdownFormatter
{
    public const string UnavailableText = "–";

    public static string Format(
        DateTimeOffset? resetsAt,
        DateTimeOffset now,
        bool isWeekly,
        string resettingText)
    {
        if (resetsAt is null)
        {
            return UnavailableText;
        }

        var remaining = resetsAt.Value - now;
        if (remaining <= TimeSpan.Zero)
        {
            return resettingText;
        }

        // Swift's Int(TimeInterval) truncates toward zero. Keeping the same
        // whole-second calculation also preserves total hours above 24.
        var totalSeconds = (long)remaining.TotalSeconds;
        if (isWeekly)
        {
            var days = totalSeconds / 86_400;
            var hours = totalSeconds % 86_400 / 3_600;
            var minutes = totalSeconds % 3_600 / 60;
            return $"{days}d {hours}h {minutes}m";
        }

        var totalHours = totalSeconds / 3_600;
        var remainingMinutes = totalSeconds % 3_600 / 60;
        var remainingSeconds = totalSeconds % 60;
        return $"{totalHours}:{remainingMinutes:00}:{remainingSeconds:00}";
    }
}
