using System.IO;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class ClaudeLoginProfileCleanupTests
{
    [Fact]
    public async Task StartupCleanup_RemovesOnlyLoginProfilesAndPreservesSessionData()
    {
        var parent = Directory.CreateTempSubdirectory("claudeusage-profile-cleanup-");
        try
        {
            var profileRoot = Directory.CreateDirectory(
                Path.Combine(parent.FullName, "WebView2")).FullName;
            var staleProfile = Directory.CreateDirectory(
                Path.Combine(profileRoot, "login-stale")).FullName;
            await File.WriteAllTextAsync(Path.Combine(staleProfile, "Cookies"), "temporary");
            var unrelatedDirectory = Directory.CreateDirectory(
                Path.Combine(profileRoot, "shared-runtime")).FullName;
            var sessionPath = Path.Combine(parent.FullName, "claude-session.dat");
            await File.WriteAllTextAsync(sessionPath, "encrypted-session");

            await ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(profileRoot);

            Assert.False(Directory.Exists(staleProfile));
            Assert.True(Directory.Exists(unrelatedDirectory));
            Assert.Equal("encrypted-session", await File.ReadAllTextAsync(sessionPath));
        }
        finally
        {
            parent.Delete(recursive: true);
        }
    }

    [Fact]
    public async Task StartupCleanup_SkipsActivelyLeasedProfileAndRetriesNextRun()
    {
        var parent = Directory.CreateTempSubdirectory("claudeusage-profile-lease-");
        try
        {
            var profileRoot = Directory.CreateDirectory(
                Path.Combine(parent.FullName, "WebView2")).FullName;
            var activeProfile = Path.Combine(profileRoot, "login-active");

            using (ClaudeLoginProfileCleanup.AcquireProfileLease(profileRoot, activeProfile))
            {
                await ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(profileRoot);
                Assert.True(Directory.Exists(activeProfile));
            }

            await ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(profileRoot);
            Assert.False(Directory.Exists(activeProfile));
        }
        finally
        {
            parent.Delete(recursive: true);
        }
    }

    [Fact]
    public async Task ConcurrentCleanupCalls_AreSafeAndIdempotent()
    {
        var parent = Directory.CreateTempSubdirectory("claudeusage-profile-concurrent-");
        try
        {
            var profileRoot = Directory.CreateDirectory(
                Path.Combine(parent.FullName, "WebView2")).FullName;
            for (var index = 0; index < 8; index++)
            {
                var profile = Directory.CreateDirectory(
                    Path.Combine(profileRoot, $"login-{index}")).FullName;
                await File.WriteAllTextAsync(Path.Combine(profile, "data"), "temporary");
            }

            await Task.WhenAll(
                ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(profileRoot),
                ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(profileRoot));

            Assert.Empty(Directory.GetDirectories(profileRoot, "login-*"));
        }
        finally
        {
            parent.Delete(recursive: true);
        }
    }

    [Fact]
    public async Task CanceledCleanup_LeavesProfileForNextStartup()
    {
        var parent = Directory.CreateTempSubdirectory("claudeusage-profile-cancel-");
        try
        {
            var profileRoot = Directory.CreateDirectory(
                Path.Combine(parent.FullName, "WebView2")).FullName;
            var staleProfile = Directory.CreateDirectory(
                Path.Combine(profileRoot, "login-stale")).FullName;
            using var cancellation = new CancellationTokenSource();
            cancellation.Cancel();

            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(
                    profileRoot,
                    cancellation.Token));

            Assert.True(Directory.Exists(staleProfile));
        }
        finally
        {
            parent.Delete(recursive: true);
        }
    }

    [Fact]
    public async Task DeleteProfile_RejectsPathsOutsideDirectLoginProfileRoot()
    {
        var parent = Directory.CreateTempSubdirectory("claudeusage-profile-boundary-");
        try
        {
            var profileRoot = Directory.CreateDirectory(
                Path.Combine(parent.FullName, "WebView2")).FullName;
            var outsidePath = Directory.CreateDirectory(
                Path.Combine(parent.FullName, "login-outside")).FullName;

            await Assert.ThrowsAsync<ArgumentException>(() =>
                ClaudeLoginProfileCleanup.DeleteProfileWithRetryAsync(
                    profileRoot,
                    outsidePath));

            Assert.True(Directory.Exists(outsidePath));
        }
        finally
        {
            parent.Delete(recursive: true);
        }
    }
}
