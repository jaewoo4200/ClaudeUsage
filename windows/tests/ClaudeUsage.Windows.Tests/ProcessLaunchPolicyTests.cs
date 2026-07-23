using System.IO;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class ProcessLaunchPolicyTests
{
    [Fact]
    public void CodexAppServerUsesExistingWritableUserWorkingDirectory()
    {
        var workingDirectory = CodexAppServerClient.ResolveWritableWorkingDirectory();

        Assert.True(Path.IsPathFullyQualified(workingDirectory));
        Assert.True(Directory.Exists(workingDirectory));
        Assert.DoesNotContain(
            $"{Path.DirectorySeparatorChar}WindowsApps{Path.DirectorySeparatorChar}",
            workingDirectory,
            StringComparison.OrdinalIgnoreCase);
    }
}
