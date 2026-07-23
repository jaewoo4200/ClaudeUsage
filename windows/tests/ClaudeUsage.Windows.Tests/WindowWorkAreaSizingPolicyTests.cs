using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class WindowWorkAreaSizingPolicyTests
{
    [Fact]
    public void SufficientWorkAreaKeepsPreferredSettingsClientSize()
    {
        var result = WindowWorkAreaSizingPolicy.Calculate(new WindowWorkAreaSizingRequest(
            WorkAreaWidthPixels: 1920,
            WorkAreaHeightPixels: 1080,
            DpiScaleX: 1,
            DpiScaleY: 1,
            PreferredWidth: 420,
            PreferredHeight: 600,
            MinimumWidth: 320,
            MinimumHeight: 280,
            NonClientWidth: 16,
            NonClientHeight: 39,
            PreferredSizeIsClient: true));

        Assert.Equal(436, result.PreferredOuterWidth);
        Assert.Equal(639, result.PreferredOuterHeight);
        Assert.Equal(result.PreferredOuterWidth, result.TargetOuterWidth);
        Assert.Equal(result.PreferredOuterHeight, result.TargetOuterHeight);
    }

    [Fact]
    public void ThirteenSixtySixBySevenSixtyEightAtTwoHundredPercentConstrainsClientWindows()
    {
        var settings = CalculateClient(420, 600, 320, 280);
        var history = CalculateClient(760, 560, 640, 480);

        Assert.Equal(671, settings.AvailableOuterWidth);
        Assert.Equal(372, settings.AvailableOuterHeight);
        Assert.Equal(436, settings.TargetOuterWidth);
        Assert.Equal(372, settings.TargetOuterHeight);
        Assert.Equal(336, settings.MinimumOuterWidth);
        Assert.Equal(319, settings.MinimumOuterHeight);

        Assert.Equal(671, history.TargetOuterWidth);
        Assert.Equal(372, history.TargetOuterHeight);
        Assert.Equal(656, history.MinimumOuterWidth);
        Assert.Equal(372, history.MinimumOuterHeight);
    }

    [Fact]
    public void ThirteenSixtySixBySevenSixtyEightAtTwoHundredPercentConstrainsLoginOuterSize()
    {
        var result = WindowWorkAreaSizingPolicy.Calculate(new WindowWorkAreaSizingRequest(
            WorkAreaWidthPixels: 1366,
            WorkAreaHeightPixels: 768,
            DpiScaleX: 2,
            DpiScaleY: 2,
            PreferredWidth: 560,
            PreferredHeight: 780,
            MinimumWidth: 360,
            MinimumHeight: 320,
            NonClientWidth: 16,
            NonClientHeight: 39,
            PreferredSizeIsClient: false));

        Assert.Equal(671, result.AvailableOuterWidth);
        Assert.Equal(372, result.AvailableOuterHeight);
        Assert.Equal(560, result.TargetOuterWidth);
        Assert.Equal(372, result.TargetOuterHeight);
        Assert.Equal(360, result.MinimumOuterWidth);
        Assert.Equal(320, result.MinimumOuterHeight);
    }

    private static WindowWorkAreaSizingResult CalculateClient(
        double preferredWidth,
        double preferredHeight,
        double minimumWidth,
        double minimumHeight) =>
        WindowWorkAreaSizingPolicy.Calculate(new WindowWorkAreaSizingRequest(
            WorkAreaWidthPixels: 1366,
            WorkAreaHeightPixels: 768,
            DpiScaleX: 2,
            DpiScaleY: 2,
            PreferredWidth: preferredWidth,
            PreferredHeight: preferredHeight,
            MinimumWidth: minimumWidth,
            MinimumHeight: minimumHeight,
            NonClientWidth: 16,
            NonClientHeight: 39,
            PreferredSizeIsClient: true));
}
