using ClaudeUsage.Windows.Views;

namespace ClaudeUsage.Windows.Tests;

public sealed class FlyoutQuitRoutingTests
{
    [Fact]
    public void QuitRequest_IsRaisedForTheApplicationLifecycleOwner()
    {
        var sender = new object();
        object? observedSender = null;
        var invocationCount = 0;
        EventHandler handler = (actualSender, _) =>
        {
            observedSender = actualSender;
            invocationCount++;
        };

        FlyoutWindow.RaiseQuitRequested(sender, handler);

        Assert.Same(sender, observedSender);
        Assert.Equal(1, invocationCount);
    }

    [Fact]
    public void QuitRequest_WithoutLifecycleOwnerDoesNotShutdownDirectly()
    {
        FlyoutWindow.RaiseQuitRequested(new object(), quitRequested: null);
    }
}
