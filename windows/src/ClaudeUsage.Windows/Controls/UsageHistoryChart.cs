using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Media;
using ClaudeUsage.Windows.ViewModels;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;
using FontFamily = System.Windows.Media.FontFamily;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;

namespace ClaudeUsage.Windows.Controls;

public sealed class UsageHistoryChart : FrameworkElement
{
    private const double RightLabelWidth = 34;
    private const double BottomLabelHeight = 25;
    private const double YAxisLabelGap = 4;

    public static readonly DependencyProperty SeriesProperty = DependencyProperty.Register(
        nameof(Series),
        typeof(IReadOnlyList<UsageHistoryChartSeries>),
        typeof(UsageHistoryChart),
        new FrameworkPropertyMetadata(
            Array.Empty<UsageHistoryChartSeries>(),
            FrameworkPropertyMetadataOptions.AffectsRender,
            OnSeriesChanged));

    public IReadOnlyList<UsageHistoryChartSeries> Series
    {
        get => (IReadOnlyList<UsageHistoryChartSeries>)GetValue(SeriesProperty);
        set => SetValue(SeriesProperty, value);
    }

    protected override AutomationPeer OnCreateAutomationPeer() =>
        new UsageHistoryChartAutomationPeer(this);

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (ActualWidth <= RightLabelWidth + 20 || ActualHeight <= BottomLabelHeight + 20)
        {
            return;
        }

        var plot = new Rect(0, 2, ActualWidth - RightLabelWidth, ActualHeight - BottomLabelHeight - 2);
        var divider = ResourceBrush("DividerBrush", "#286B7684");
        var tertiary = ResourceBrush("TertiaryTextBrush", "#FF8B95A1");
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;

        DrawYAxis(drawingContext, plot, divider, tertiary, dpi);

        var points = Series.SelectMany(series => series.Points).ToArray();
        if (points.Length == 0)
        {
            return;
        }

        var start = points.Min(point => point.Timestamp);
        var end = points.Max(point => point.Timestamp);
        if (end <= start)
        {
            start = start.AddMinutes(-1);
            end = end.AddMinutes(1);
        }

        DrawXAxis(drawingContext, plot, divider, tertiary, dpi, start, end);

        drawingContext.PushClip(new RectangleGeometry(plot));
        var showPoints = points.Length < 80;
        foreach (var series in Series)
        {
            DrawSeries(drawingContext, plot, series, start, end, showPoints);
        }
        drawingContext.Pop();
    }

    private static void DrawYAxis(
        DrawingContext context,
        Rect plot,
        Brush divider,
        Brush text,
        double dpi)
    {
        var gridPen = new Pen(divider, 1);
        gridPen.Freeze();
        foreach (var value in new[] { 0, 25, 50, 75, 100 })
        {
            var y = plot.Bottom - (value / 100d * plot.Height);
            context.DrawLine(gridPen, new Point(plot.Left, y), new Point(plot.Right, y));
            var label = Text($"{value}%", 10.5, text, dpi);
            context.DrawText(label, new Point(plot.Right + YAxisLabelGap, y - label.Height / 2));
        }
    }

    private static void DrawXAxis(
        DrawingContext context,
        Rect plot,
        Brush divider,
        Brush text,
        double dpi,
        DateTimeOffset start,
        DateTimeOffset end)
    {
        var gridBrush = divider.CloneCurrentValue();
        gridBrush.Opacity *= 0.7;
        gridBrush.Freeze();
        var gridPen = new Pen(gridBrush, 1);
        gridPen.Freeze();
        var span = end - start;
        for (var index = 1; index <= 4; index++)
        {
            var ratio = index / 5d;
            var x = plot.Left + ratio * plot.Width;
            context.DrawLine(gridPen, new Point(x, plot.Top), new Point(x, plot.Bottom));
            var timestamp = start + TimeSpan.FromTicks((long)(span.Ticks * ratio));
            var label = Text(FormatXAxisLabel(timestamp.LocalDateTime, span), 10.5, text, dpi);
            context.DrawText(label, new Point(x - label.Width / 2, plot.Bottom + 7));
        }
    }

    private static void DrawSeries(
        DrawingContext context,
        Rect plot,
        UsageHistoryChartSeries series,
        DateTimeOffset start,
        DateTimeOffset end,
        bool showPoints)
    {
        var ordered = series.Points.OrderBy(point => point.Timestamp).ToArray();
        if (ordered.Length == 0)
        {
            return;
        }

        var totalTicks = Math.Max(1L, (end - start).Ticks);
        Point Map(UsageHistoryChartPoint point)
        {
            var xRatio = (point.Timestamp - start).Ticks / (double)totalTicks;
            var yRatio = Math.Clamp(point.Utilization, 0, 100) / 100d;
            return new Point(
                plot.Left + xRatio * plot.Width,
                plot.Bottom - yRatio * plot.Height);
        }

        var geometry = new StreamGeometry();
        using (var geometryContext = geometry.Open())
        {
            geometryContext.BeginFigure(Map(ordered[0]), false, false);
            if (ordered.Length > 1)
            {
                geometryContext.PolyLineTo(ordered.Skip(1).Select(Map).ToArray(), true, false);
            }
        }
        geometry.Freeze();

        var pen = new Pen(series.Brush, 2)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        context.DrawGeometry(null, pen, geometry);

        if (!showPoints)
        {
            return;
        }

        foreach (var point in ordered)
        {
            // Swift Charts' symbolSize(14) is an area, which is approximately a
            // 2.1-point radius. Matching that keeps dense history series from
            // looking heavier on Windows.
            context.DrawEllipse(series.Brush, null, Map(point), 2.1, 2.1);
        }
    }

    internal static string FormatXAxisLabel(
        DateTime timestamp,
        TimeSpan span,
        CultureInfo? culture = null)
    {
        culture ??= CultureInfo.CurrentCulture;
        if (span <= TimeSpan.FromDays(2))
        {
            return timestamp.ToString(culture.DateTimeFormat.ShortTimePattern, culture);
        }

        // MonthDayPattern preserves the locale's ordering and separators while
        // avoiding a redundant year on the one- and two-week dashboard ranges.
        var pattern = culture.DateTimeFormat.MonthDayPattern
            .Replace("MMMM", "MMM", StringComparison.Ordinal)
            .Replace("dddd", "ddd", StringComparison.Ordinal);
        return timestamp.ToString(pattern, culture);
    }

    internal string BuildAutomationSummary(IReadOnlyList<UsageHistoryChartSeries>? series = null)
    {
        series ??= Series;
        var populated = series
            .Where(item => item.Points.Count > 0)
            .ToArray();
        if (populated.Length == 0)
        {
            return ResourceString("History.ChartAccessibilityEmpty", "No usage samples.");
        }

        var details = populated.Select(item =>
        {
            var values = item.Points
                .Select(point => Math.Clamp(point.Utilization, 0, 100))
                .ToArray();
            var latest = item.Points
                .OrderBy(point => point.Timestamp)
                .Last()
                .Utilization;
            return string.Format(
                CultureInfo.CurrentCulture,
                ResourceString(
                    "History.ChartAccessibilitySeries",
                    "{0}: {1} samples, latest {2:0.#}%, range {3:0.#}–{4:0.#}%."),
                item.Label,
                values.Length,
                Math.Clamp(latest, 0, 100),
                values.Min(),
                values.Max());
        });

        return string.Format(
            CultureInfo.CurrentCulture,
            ResourceString(
                "History.ChartAccessibilitySummary",
                "{0} series. {1}"),
            populated.Length,
            string.Join(" ", details));
    }

    private static void OnSeriesChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs args)
    {
        if (dependencyObject is not UsageHistoryChart chart
            || FrameworkElementAutomationPeer.FromElement(chart) is not UsageHistoryChartAutomationPeer peer)
        {
            return;
        }

        peer.NotifySeriesChanged(
            args.OldValue as IReadOnlyList<UsageHistoryChartSeries>,
            args.NewValue as IReadOnlyList<UsageHistoryChartSeries>);
    }

    private Brush ResourceBrush(string key, string fallback) =>
        TryFindResource(key) as Brush ?? new SolidColorBrush((Color)ColorConverter.ConvertFromString(fallback));

    private string ResourceString(string key, string fallback) =>
        TryFindResource(key) as string ?? fallback;

    private static FormattedText Text(string value, double size, Brush brush, double dpi) => new(
        value,
        CultureInfo.CurrentUICulture,
        System.Windows.FlowDirection.LeftToRight,
        new Typeface(new FontFamily("Segoe UI Variable Text, Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal),
        size,
        brush,
        dpi);

    private sealed class UsageHistoryChartAutomationPeer(UsageHistoryChart owner)
        : FrameworkElementAutomationPeer(owner)
    {
        private UsageHistoryChart Chart => (UsageHistoryChart)Owner;

        protected override string GetClassNameCore() => nameof(UsageHistoryChart);

        protected override AutomationControlType GetAutomationControlTypeCore() =>
            AutomationControlType.Custom;

        protected override string GetNameCore()
        {
            var explicitName = base.GetNameCore();
            return string.IsNullOrWhiteSpace(explicitName)
                ? Chart.ResourceString("History.ChartTitle", "Usage history chart")
                : explicitName;
        }

        protected override string GetHelpTextCore()
        {
            var explicitHelpText = base.GetHelpTextCore();
            return string.IsNullOrWhiteSpace(explicitHelpText)
                ? Chart.BuildAutomationSummary()
                : explicitHelpText;
        }

        internal void NotifySeriesChanged(
            IReadOnlyList<UsageHistoryChartSeries>? oldSeries,
            IReadOnlyList<UsageHistoryChartSeries>? newSeries)
        {
            RaisePropertyChangedEvent(
                AutomationElementIdentifiers.HelpTextProperty,
                Chart.BuildAutomationSummary(oldSeries ?? Array.Empty<UsageHistoryChartSeries>()),
                Chart.BuildAutomationSummary(newSeries ?? Array.Empty<UsageHistoryChartSeries>()));
        }
    }
}
