using System.Net;
using System.Net.Http;
using System.IO;
using System.Text;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class ClaudeSessionLifecycleTests
{
    [Fact]
    public async Task DpapiRoundTripContainsNoPlaintextAndClearRemovesRemnants()
    {
        using var fixture = new SessionFixture();
        var store = new DpapiClaudeCookieStore(fixture.StoragePath);
        const string cookie = "sessionKey=secret-session-value";

        await store.SaveAsync(cookie);

        Assert.Equal(cookie, await store.LoadAsync());
        var protectedBytes = await File.ReadAllBytesAsync(fixture.StoragePath);
        Assert.DoesNotContain(cookie, Encoding.UTF8.GetString(protectedBytes));

        var remnant = Path.Combine(
            fixture.DirectoryPath,
            $".{Path.GetFileName(fixture.StoragePath)}.crash.tmp");
        await File.WriteAllTextAsync(remnant, "encrypted-remnant-placeholder");
        await store.ClearAsync();

        Assert.False(File.Exists(fixture.StoragePath));
        Assert.False(File.Exists(remnant));
        Assert.Null(await store.LoadAsync());
    }

    [Fact]
    public async Task ConcurrentOldCompareClearNeverDeletesNewSession()
    {
        using var fixture = new SessionFixture();
        var store = new DpapiClaudeCookieStore(fixture.StoragePath);
        const string oldCookie = "sessionKey=old-session";
        const string newCookie = "sessionKey=new-session";
        await store.SaveAsync(oldCookie);

        var clearOld = store.ClearIfMatchesAsync(oldCookie);
        var saveNew = store.SaveAsync(newCookie);
        await Task.WhenAll(clearOld, saveNew);

        Assert.Equal(newCookie, await store.LoadAsync());
    }

    [Fact]
    public async Task LateUnauthorizedResponsePreservesNewlySavedSession()
    {
        using var fixture = new SessionFixture();
        var store = new DpapiClaudeCookieStore(fixture.StoragePath);
        const string oldCookie = "sessionKey=expired-session";
        const string newCookie = "sessionKey=fresh-session";
        await store.SaveAsync(oldCookie);

        using var handler = new BlockingUnauthorizedHandler();
        using var httpClient = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(10),
        };
        var service = new ClaudeUsageService(httpClient, store);
        var fetch = service.FetchSnapshotAsync();
        await handler.RequestStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await store.SaveAsync(newCookie);
        handler.ReleaseResponse.TrySetResult();

        var exception = await Assert.ThrowsAsync<ClaudeUsageException>(() => fetch);
        Assert.Equal(ClaudeUsageErrorKind.AuthenticationExpired, exception.Kind);
        Assert.Equal(newCookie, await store.LoadAsync());
    }

    private sealed class BlockingUnauthorizedHandler : HttpMessageHandler
    {
        public TaskCompletionSource RequestStarted { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource ReleaseResponse { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestStarted.TrySetResult();
            await ReleaseResponse.Task.WaitAsync(cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.Unauthorized)
            {
                Content = new StringContent(string.Empty),
            };
        }
    }

    private sealed class SessionFixture : IDisposable
    {
        public SessionFixture()
        {
            DirectoryPath = Path.Combine(
                Path.GetTempPath(),
                $"ClaudeUsage-session-{Guid.NewGuid():N}");
            Directory.CreateDirectory(DirectoryPath);
        }

        public string DirectoryPath { get; }

        public string StoragePath => Path.Combine(DirectoryPath, "claude-session.dat");

        public void Dispose()
        {
            try
            {
                Directory.Delete(DirectoryPath, recursive: true);
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
