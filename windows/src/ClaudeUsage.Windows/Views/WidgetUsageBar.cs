using System.Windows;
using MediaBrush = System.Windows.Media.Brush;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaDrawingContext = System.Windows.Media.DrawingContext;

namespace ClaudeUsage.Windows.Views;

public sealed class WidgetUsageBar : FrameworkElement
{
    public static readonly DependencyProperty ProgressProperty = DependencyProperty.Register(
        nameof(Progress),
        typeof(double),
        typeof(WidgetUsageBar),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty TrackProperty = DependencyProperty.Register(
        nameof(Track),
        typeof(MediaBrush),
        typeof(WidgetUsageBar),
        new FrameworkPropertyMetadata(MediaBrushes.Transparent, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty FillProperty = DependencyProperty.Register(
        nameof(Fill),
        typeof(MediaBrush),
        typeof(WidgetUsageBar),
        new FrameworkPropertyMetadata(MediaBrushes.DodgerBlue, FrameworkPropertyMetadataOptions.AffectsRender));

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

    protected override void OnRender(MediaDrawingContext drawingContext)
    {
        base.OnRender(drawingContext);

        if (ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }

        var radius = ActualHeight / 2;
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        drawingContext.DrawRoundedRectangle(Track, null, bounds, radius, radius);

        var fraction = Math.Clamp(Progress / 100d, 0d, 1d);
        if (fraction <= 0)
        {
            return;
        }

        var progressBounds = new Rect(0, 0, ActualWidth * fraction, ActualHeight);
        drawingContext.DrawRoundedRectangle(Fill, null, progressBounds, radius, radius);
    }
}
