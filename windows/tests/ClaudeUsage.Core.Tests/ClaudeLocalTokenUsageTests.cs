using ClaudeUsage.Core.History;

namespace ClaudeUsage.Core.Tests;

public sealed class ClaudeLocalTokenUsageTests
{
    [Fact]
    public async Task ScanUsesTodayDeduplicatesAndAcceptsNumericStrings()
    {
        using var fixture = new TokenFixture();
        var now = new DateTimeOffset(2026, 7, 13, 12, 0, 0, TimeSpan.Zero);
        var current = """
            {"requestId":"request-1","timestamp":"2026-07-13T11:59:00.123Z","message":{"id":"message-1","usage":{"input_tokens":10,"output_tokens":"20","cache_creation_input_tokens":30,"cache_read_input_tokens":"40"}},"content":"must not be retained"}
            """;
        var yesterday = """
            {"requestId":"request-2","timestamp":"2026-07-12T11:59:00Z","message":{"id":"message-2","usage":{"input_tokens":999}}}
            """;
        var future = """
            {"requestId":"request-3","timestamp":"2026-07-13T12:01:00Z","message":{"id":"message-3","usage":{"input_tokens":999}}}
            """;
        var file = fixture.Write(
            "project/session.jsonl",
            string.Join(Environment.NewLine, current, current, yesterday, future, "not-json"));
        File.SetLastWriteTimeUtc(file, now.UtcDateTime);

        var usage = await ClaudeLocalTokenAggregator.ScanAsync(
            fixture.Root,
            now,
            TimeZoneInfo.Utc);

        Assert.NotNull(usage);
        Assert.Equal(100, usage.TodayTokens);
        Assert.Equal(now, usage.UpdatedAt);
    }

    [Fact]
    public async Task ScanSkipsFilesNotModifiedToday()
    {
        using var fixture = new TokenFixture();
        var now = new DateTimeOffset(2026, 7, 13, 12, 0, 0, TimeSpan.Zero);
        var file = fixture.Write(
            "old.jsonl",
            "{\"requestId\":\"r\",\"timestamp\":\"2026-07-13T10:00:00Z\",\"message\":{\"id\":\"m\",\"usage\":{\"input_tokens\":500}}}");
        File.SetLastWriteTimeUtc(file, now.AddDays(-1).UtcDateTime);

        var usage = await ClaudeLocalTokenAggregator.ScanAsync(
            fixture.Root,
            now,
            TimeZoneInfo.Utc);

        Assert.NotNull(usage);
        Assert.Equal(0, usage.TodayTokens);
    }

    [Fact]
    public async Task MissingRootReturnsNoUsage()
    {
        var missing = Path.Combine(Path.GetTempPath(), $"ClaudeUsage-missing-{Guid.NewGuid():N}");

        var usage = await ClaudeLocalTokenAggregator.ScanAsync(
            missing,
            DateTimeOffset.UtcNow,
            TimeZoneInfo.Utc);

        Assert.Null(usage);
    }

    private sealed class TokenFixture : IDisposable
    {
        public TokenFixture()
        {
            Root = Path.Combine(Path.GetTempPath(), $"ClaudeUsage-tokens-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Root);
        }

        public string Root { get; }

        public string Write(string relativePath, string content)
        {
            var path = Path.Combine(Root, relativePath.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, content);
            return path;
        }

        public void Dispose()
        {
            try
            {
                Directory.Delete(Root, recursive: true);
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
