using System.Windows;
using MediaBrush = System.Windows.Media.Brush;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaDrawingContext = System.Windows.Media.DrawingContext;
using MediaPen = System.Windows.Media.Pen;
using MediaPenLineCap = System.Windows.Media.PenLineCap;
using MediaStreamGeometry = System.Windows.Media.StreamGeometry;
using MediaSweepDirection = System.Windows.Media.SweepDirection;
using WpfPoint = System.Windows.Point;
using WpfSize = System.Windows.Size;

namespace ClaudeUsage.Windows.Views;

public sealed class WidgetUsageRing : FrameworkElement
{
    public static readonly DependencyProperty ProgressProperty = DependencyProperty.Register(
        nameof(Progress),
        typeof(double),
        typeof(WidgetUsageRing),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty TrackProperty = DependencyProperty.Register(
        nameof(Track),
        typeof(MediaBrush),
        typeof(WidgetUsageRing),
        new FrameworkPropertyMetadata(MediaBrushes.Transparent, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty FillProperty = DependencyProperty.Register(
        nameof(Fill),
        typeof(MediaBrush),
        typeof(WidgetUsageRing),
        new FrameworkPropertyMetadata(MediaBrushes.DodgerBlue, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty StrokeThicknessProperty = DependencyProperty.Register(
        nameof(StrokeThickness),
        typeof(double),
        typeof(WidgetUsageRing),
        new FrameworkPropertyMetadata(5d, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Progress
    {
        get => (double)GetValue(ProgressProperty);
        set => SetValue(ProgressProperty, value);
    }

    public MediaBrush Track
    {
        get => (MediaBrush)GetValue(TrackProperty);
        set => SetValue(TrackProperty, value);
    }

    public MediaBrush Fill
    {
        get => (MediaBrush)GetValue(FillProperty);
        set => SetValue(FillProperty, value);
    }

    public double StrokeThickness
    {
        get => (double)GetValue(StrokeThicknessProperty);
        set => SetValue(StrokeThicknessProperty, value);
    }

    protected override void OnRender(MediaDrawingContext drawingContext)
    {
        base.OnRender(drawingContext);

        if (ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }

        var maximumThickness = Math.Max(1, Math.Min(ActualWidth, ActualHeight) / 2);
        var thickness = Math.Clamp(StrokeThickness, 1, maximumThickness);
        var radius = Math.Max(0, (Math.Min(ActualWidth, ActualHeight) - thickness) / 2);
        var center = new WpfPoint(ActualWidth / 2, ActualHeight / 2);
        if (radius <= 0)
        {
            return;
        }

        var trackPen = CreatePen(Track, thickness);
        drawingContext.DrawEllipse(null, trackPen, center, radius, radius);

        var fraction = Math.Clamp(Progress / 100d, 0d, 1d);
        if (fraction <= 0)
        {
            return;
        }

        var progressPen = CreatePen(Fill, thickness);
        if (fraction >= 0.9999)
        {
            drawingContext.DrawEllipse(null, progressPen, center, radius, radius);
            return;
        }

        var start = PointOnCircle(center, radius, -90);
        var end = PointOnCircle(center, radius, -90 + (fraction * 360));
        var geometry = new MediaStreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(start, isFilled: false, isClosed: false);
            context.ArcTo(
                end,
                new WpfSize(radius, radius),
                rotationAngle: 0,
                isLargeArc: fraction > 0.5,
                MediaSweepDirection.Clockwise,
                isStroked: true,
                isSmoothJoin: false);
        }

        geometry.Freeze();
        drawingContext.DrawGeometry(null, progressPen, geometry);
    }

    private static MediaPen CreatePen(MediaBrush brush, double thickness) => new(brush, thickness)
    {
        StartLineCap = MediaPenLineCap.Round,
        EndLineCap = MediaPenLineCap.Round,
    };

    private static WpfPoint PointOnCircle(WpfPoint center, double radius, double angleDegrees)
    {
        var radians = angleDegrees * Math.PI / 180d;
        return new WpfPoint(
            center.X + (radius * Math.Cos(radians)),
            center.Y + (radius * Math.Sin(radians)));
    }
}
