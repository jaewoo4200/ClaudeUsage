using System.IO;
using ClaudeUsage.Core.History;

namespace ClaudeUsage.Windows.Services;

public interface IClaudeLocalTokenUsageService
{
    Task<ClaudeLocalTokenUsage?> FetchAsync(
        DateTimeOffset? now = null,
        CancellationToken cancellationToken = default);
}

public sealed class ClaudeLocalTokenUsageService : IClaudeLocalTokenUsageService
{
    private readonly string _rootDirectory;
    private readonly TimeZoneInfo _calendarTimeZone;

    public ClaudeLocalTokenUsageService(
        string? rootDirectory = null,
        TimeZoneInfo? calendarTimeZone = null)
    {
        _rootDirectory = rootDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude",
            "projects");
        _calendarTimeZone = calendarTimeZone ?? TimeZoneInfo.Local;
    }

    public string RootDirectory => _rootDirectory;

    public Task<ClaudeLocalTokenUsage?> FetchAsync(
        DateTimeOffset? now = null,
        CancellationToken cancellationToken = default) =>
        ClaudeLocalTokenAggregator.ScanAsync(
            _rootDirectory,
            now,
            _calendarTimeZone,
            cancellationToken);
}
