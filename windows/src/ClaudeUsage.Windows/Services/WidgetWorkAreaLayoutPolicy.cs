using System.Drawing;

namespace ClaudeUsage.Windows.Services;

internal readonly record struct WidgetDefaultPlacement(int Left, int Top, bool UsesVerticalCascade);

internal static class WidgetWorkAreaLayoutPolicy
{
    internal static double AvailableDip(int workAreaPixels, double dpiScale, int physicalMargin = 12)
    {
        var scale = double.IsFinite(dpiScale) && dpiScale > 0 ? dpiScale : 1;
        var margin = Math.Max(0, physicalMargin);
        return Math.Max(1, (workAreaPixels - (2d * margin)) / scale);
    }

    internal static WidgetDefaultPlacement ResolveDefaultPlacement(
        Rectangle workArea,
        int widgetWidth,
        int widgetHeight,
        int slotIndex,
        int physicalMargin = 12,
        int gap = 16,
        int slotCount = 2)
    {
        var width = Math.Max(1, widgetWidth);
        var height = Math.Max(1, widgetHeight);
        var slot = Math.Max(0, slotIndex);
        var slots = Math.Max(slot + 1, slotCount);
        var margin = Math.Max(0, physicalMargin);
        var spacing = Math.Max(0, gap);
        var usableWidth = Math.Max(0, workArea.Width - (2 * margin));
        var requiredHorizontalWidth = ((long)slots * width) + ((long)(slots - 1) * spacing);
        var useVerticalCascade = requiredHorizontalWidth > usableWidth;

        var desiredLeft = useVerticalCascade
            ? workArea.Right - width - margin
            : workArea.Right - width - margin - (slot * (width + spacing));
        var desiredTop = useVerticalCascade
            ? workArea.Top + margin + (slot * (height + spacing))
            : workArea.Top + margin;

        var minimumLeft = workArea.Left + margin;
        var minimumTop = workArea.Top + margin;
        var maximumLeft = Math.Max(minimumLeft, workArea.Right - width - margin);
        var maximumTop = Math.Max(minimumTop, workArea.Bottom - height - margin);
        return new WidgetDefaultPlacement(
            Math.Clamp(desiredLeft, minimumLeft, maximumLeft),
            Math.Clamp(desiredTop, minimumTop, maximumTop),
            useVerticalCascade);
    }
}
