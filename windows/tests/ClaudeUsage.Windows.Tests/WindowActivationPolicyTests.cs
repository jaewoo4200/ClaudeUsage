using System.Windows;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class WindowActivationPolicyTests
{
    [Theory]
    [InlineData(WindowState.Minimized, WindowState.Normal)]
    [InlineData(WindowState.Normal, WindowState.Normal)]
    [InlineData(WindowState.Maximized, WindowState.Maximized)]
    public void ExistingWindow_ReopensInExpectedState(
        WindowState currentState,
        WindowState expectedState)
    {
        Assert.Equal(
            expectedState,
            WindowActivationPolicy.ResolveRestoredState(currentState));
    }
}
