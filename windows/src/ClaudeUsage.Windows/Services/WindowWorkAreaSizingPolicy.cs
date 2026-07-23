namespace ClaudeUsage.Windows.Services;

internal readonly record struct WindowWorkAreaSizingRequest(
    double WorkAreaWidthPixels,
    double WorkAreaHeightPixels,
    double DpiScaleX,
    double DpiScaleY,
    double PreferredWidth,
    double PreferredHeight,
    double MinimumWidth,
    double MinimumHeight,
    double NonClientWidth,
    double NonClientHeight,
    bool PreferredSizeIsClient,
    double PhysicalMarginPixels = 12);

internal readonly record struct WindowWorkAreaSizingResult(
    double AvailableOuterWidth,
    double AvailableOuterHeight,
    double PreferredOuterWidth,
    double PreferredOuterHeight,
    double MinimumOuterWidth,
    double MinimumOuterHeight,
    double TargetOuterWidth,
    double TargetOuterHeight);

/// <summary>
/// Converts a monitor's physical-pixel work area into WPF window constraints.
/// The margin intentionally stays in physical pixels so the same amount of the
/// desktop remains visible at every per-monitor DPI.
/// </summary>
internal static class WindowWorkAreaSizingPolicy
{
    internal static WindowWorkAreaSizingResult Calculate(WindowWorkAreaSizingRequest request)
    {
        var scaleX = PositiveOrDefault(request.DpiScaleX, 1);
        var scaleY = PositiveOrDefault(request.DpiScaleY, 1);
        var margin = NonNegative(request.PhysicalMarginPixels);
        var availableWidth = Math.Max(
            1,
            (NonNegative(request.WorkAreaWidthPixels) - (2 * margin)) / scaleX);
        var availableHeight = Math.Max(
            1,
            (NonNegative(request.WorkAreaHeightPixels) - (2 * margin)) / scaleY);

        var chromeWidth = request.PreferredSizeIsClient
            ? NonNegative(request.NonClientWidth)
            : 0;
        var chromeHeight = request.PreferredSizeIsClient
            ? NonNegative(request.NonClientHeight)
            : 0;
        var preferredWidth = NonNegative(request.PreferredWidth) + chromeWidth;
        var preferredHeight = NonNegative(request.PreferredHeight) + chromeHeight;
        var requestedMinimumWidth = NonNegative(request.MinimumWidth) + chromeWidth;
        var requestedMinimumHeight = NonNegative(request.MinimumHeight) + chromeHeight;
        var minimumWidth = Math.Min(requestedMinimumWidth, availableWidth);
        var minimumHeight = Math.Min(requestedMinimumHeight, availableHeight);

        return new WindowWorkAreaSizingResult(
            availableWidth,
            availableHeight,
            preferredWidth,
            preferredHeight,
            minimumWidth,
            minimumHeight,
            Math.Clamp(preferredWidth, minimumWidth, availableWidth),
            Math.Clamp(preferredHeight, minimumHeight, availableHeight));
    }

    private static double NonNegative(double value) =>
        double.IsFinite(value) ? Math.Max(0, value) : 0;

    private static double PositiveOrDefault(double value, double fallback) =>
        double.IsFinite(value) && value > 0 ? value : fallback;
}
