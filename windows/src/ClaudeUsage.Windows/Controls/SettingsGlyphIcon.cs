using System.Windows;
using System.Windows.Media;
using WpfBrush = System.Windows.Media.Brush;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfPen = System.Windows.Media.Pen;
using WpfPoint = System.Windows.Point;
using WpfRect = System.Windows.Rect;
using WpfSize = System.Windows.Size;

namespace ClaudeUsage.Windows.Controls;

public enum SettingsGlyph
{
    Layout,
    AlwaysOnTop,
    Spark,
    Character,
    Sensitivity,
    Animation,
    History,
}

/// <summary>
/// Font-independent settings glyphs matching the SF Symbol roles used by the
/// macOS settings surface. Drawing the small marks as vectors keeps them stable
/// across Windows font and language configurations.
/// </summary>
public sealed class SettingsGlyphIcon : FrameworkElement
{
    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(
        nameof(Glyph),
        typeof(SettingsGlyph),
        typeof(SettingsGlyphIcon),
        new FrameworkPropertyMetadata(SettingsGlyph.Layout, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CircleBrushProperty = DependencyProperty.Register(
        nameof(CircleBrush),
        typeof(WpfBrush),
        typeof(SettingsGlyphIcon),
        new FrameworkPropertyMetadata(WpfBrushes.Transparent, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty GlyphBrushProperty = DependencyProperty.Register(
        nameof(GlyphBrush),
        typeof(WpfBrush),
        typeof(SettingsGlyphIcon),
        new FrameworkPropertyMetadata(WpfBrushes.Black, FrameworkPropertyMetadataOptions.AffectsRender));

    public SettingsGlyphIcon()
    {
        Width = 36;
        Height = 36;
        Focusable = false;
        IsHitTestVisible = false;
        SnapsToDevicePixels = true;
    }

    public SettingsGlyph Glyph
    {
        get => (SettingsGlyph)GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    public WpfBrush CircleBrush
    {
        get => (WpfBrush)GetValue(CircleBrushProperty);
        set => SetValue(CircleBrushProperty, value);
    }

    public WpfBrush GlyphBrush
    {
        get => (WpfBrush)GetValue(GlyphBrushProperty);
        set => SetValue(GlyphBrushProperty, value);
    }

    protected override WpfSize MeasureOverride(WpfSize availableSize) => new(36, 36);

    protected override void OnRender(DrawingContext context)
    {
        base.OnRender(context);
        var scale = Math.Min(ActualWidth, ActualHeight) / 36d;
        if (scale <= 0)
        {
            return;
        }

        var center = new WpfPoint(ActualWidth / 2, ActualHeight / 2);
        context.DrawEllipse(CircleBrush, null, center, 18 * scale, 18 * scale);
        context.PushTransform(new TranslateTransform(center.X - (18 * scale), center.Y - (18 * scale)));
        context.PushTransform(new ScaleTransform(scale, scale));

        var pen = new WpfPen(GlyphBrush, 1.8)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
            LineJoin = PenLineJoin.Round,
        };

        switch (Glyph)
        {
            case SettingsGlyph.Layout:
                DrawLayout(context, pen);
                break;
            case SettingsGlyph.AlwaysOnTop:
                DrawAlwaysOnTop(context, pen);
                break;
            case SettingsGlyph.Spark:
                DrawSpark(context);
                break;
            case SettingsGlyph.Character:
                DrawCharacter(context);
                break;
            case SettingsGlyph.Sensitivity:
                DrawSensitivity(context, pen);
                break;
            case SettingsGlyph.Animation:
                DrawAnimation(context, pen);
                break;
            case SettingsGlyph.History:
                DrawHistory(context, pen);
                break;
        }

        context.Pop();
        context.Pop();
    }

    private static void DrawLayout(DrawingContext context, WpfPen pen)
    {
        context.DrawRoundedRectangle(null, pen, new WpfRect(9.5, 11, 7, 5.5), 1, 1);
        context.DrawRoundedRectangle(null, pen, new WpfRect(9.5, 20, 7, 5), 1, 1);
        context.DrawRoundedRectangle(null, pen, new WpfRect(20, 11, 6.5, 14), 1, 1);
    }

    private static void DrawAlwaysOnTop(DrawingContext context, WpfPen pen)
    {
        context.DrawRoundedRectangle(null, pen, new WpfRect(9.5, 10.5, 12.5, 11), 1.5, 1.5);
        context.DrawRoundedRectangle(null, pen, new WpfRect(14, 14.5, 12.5, 11), 1.5, 1.5);
    }

    private void DrawSpark(DrawingContext context)
    {
        var geometry = Geometry.Parse("M20,7 L11,19 H17 L15,29 L26,15 H20 Z");
        context.DrawGeometry(GlyphBrush, null, geometry);
    }

    private void DrawCharacter(DrawingContext context)
    {
        context.DrawEllipse(GlyphBrush, null, new WpfPoint(12, 14), 2.2, 3);
        context.DrawEllipse(GlyphBrush, null, new WpfPoint(17, 11.5), 2.2, 3);
        context.DrawEllipse(GlyphBrush, null, new WpfPoint(22, 12), 2.2, 3);
        context.DrawEllipse(GlyphBrush, null, new WpfPoint(25, 16), 2.1, 2.8);
        context.DrawEllipse(GlyphBrush, null, new WpfPoint(18.5, 21), 6.2, 5.4);
    }

    private void DrawSensitivity(DrawingContext context, WpfPen pen)
    {
        context.DrawEllipse(null, pen, new WpfPoint(18, 18), 8.5, 8.5);
        context.DrawLine(pen, new WpfPoint(18, 18), new WpfPoint(22.5, 13));
        context.DrawEllipse(GlyphBrush, null, new WpfPoint(18, 18), 1.6, 1.6);
        context.DrawLine(pen, new WpfPoint(18, 8), new WpfPoint(18, 10.5));
        context.DrawLine(pen, new WpfPoint(9.5, 13), new WpfPoint(11.6, 14.2));
        context.DrawLine(pen, new WpfPoint(26.5, 13), new WpfPoint(24.4, 14.2));
    }

    private static void DrawAnimation(DrawingContext context, WpfPen pen)
    {
        context.DrawEllipse(null, pen, new WpfPoint(20.5, 9.5), 2.2, 2.2);
        context.DrawLine(pen, new WpfPoint(19, 13), new WpfPoint(16, 19));
        context.DrawLine(pen, new WpfPoint(16, 19), new WpfPoint(21, 21));
        context.DrawLine(pen, new WpfPoint(16.5, 16), new WpfPoint(11, 15));
        context.DrawLine(pen, new WpfPoint(17.5, 14.5), new WpfPoint(23, 16));
        context.DrawLine(pen, new WpfPoint(21, 21), new WpfPoint(25.5, 26));
        context.DrawLine(pen, new WpfPoint(16, 19), new WpfPoint(12.5, 25.5));
    }

    private static void DrawHistory(DrawingContext context, WpfPen pen)
    {
        context.DrawLine(pen, new WpfPoint(10, 9), new WpfPoint(10, 26));
        context.DrawLine(pen, new WpfPoint(10, 26), new WpfPoint(27, 26));
        var trend = new StreamGeometry();
        using (var geometry = trend.Open())
        {
            geometry.BeginFigure(new WpfPoint(12, 22), false, false);
            geometry.PolyLineTo(
                [new WpfPoint(16, 18), new WpfPoint(19.5, 20), new WpfPoint(24.5, 13)],
                true,
                false);
        }

        context.DrawGeometry(null, pen, trend);
    }
}
