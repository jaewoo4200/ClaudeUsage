using System.Drawing;
using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class WidgetWorkAreaLayoutPolicyTests
{
    [Fact]
    public void AvailableDipUsesPhysicalMarginAndPerMonitorScale()
    {
        Assert.Equal(671, WidgetWorkAreaLayoutPolicy.AvailableDip(1366, 2));
        Assert.Equal(372, WidgetWorkAreaLayoutPolicy.AvailableDip(768, 2));
    }

    [Fact]
    public void SeparateWidgetsKeepOriginalHorizontalDefaultWhenBothFit()
    {
        var workArea = new Rectangle(0, 0, 1920, 1080);
        var claude = WidgetWorkAreaLayoutPolicy.ResolveDefaultPlacement(workArea, 240, 300, 0);
        var codex = WidgetWorkAreaLayoutPolicy.ResolveDefaultPlacement(workArea, 240, 300, 1);

        Assert.False(claude.UsesVerticalCascade);
        Assert.False(codex.UsesVerticalCascade);
        Assert.Equal(12, claude.Top);
        Assert.Equal(12, codex.Top);
        Assert.True(codex.Left + 240 < claude.Left);
    }

    [Fact]
    public void SeparateWidgetsCascadeVerticallyWithoutOverlapWhenWidthIsNarrow()
    {
        var workArea = new Rectangle(0, 0, 479, 1000);
        var claude = WidgetWorkAreaLayoutPolicy.ResolveDefaultPlacement(workArea, 240, 300, 0);
        var codex = WidgetWorkAreaLayoutPolicy.ResolveDefaultPlacement(workArea, 240, 300, 1);

        Assert.True(claude.UsesVerticalCascade);
        Assert.True(codex.UsesVerticalCascade);
        Assert.Equal(claude.Left, codex.Left);
        Assert.True(claude.Top + 300 < codex.Top);
        Assert.InRange(codex.Top + 300, workArea.Top, workArea.Bottom - 12);
    }
}
