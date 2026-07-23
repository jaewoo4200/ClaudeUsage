using System.Collections;
using System.ComponentModel;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;
using FontFamily = System.Windows.Media.FontFamily;
using Path = System.Windows.Shapes.Path;
using Point = System.Windows.Point;
using Rectangle = System.Windows.Shapes.Rectangle;
using Size = System.Windows.Size;
using UserControl = System.Windows.Controls.UserControl;

namespace ClaudeUsage.Windows.Controls;

public enum CompanionPresentationMode
{
    Compact,
    Summary,
    Wide,
}

/// <summary>
/// Compact quota-ring companion used by the flyout and floating widgets.
/// Character art is drawn in a stable 100x100 coordinate space so animation
/// never changes the surrounding quota-card measurement.
/// </summary>
public partial class CompanionControl : UserControl
{
    internal static bool ForceMotionForDiagnostics { get; set; }

    private static readonly Brush Ink = FrozenBrush("#FF111827");
    private static readonly Brush White = FrozenBrush("#FFF9FAFB");
    private static readonly Brush SoftInk = FrozenBrush("#FF374151");

    public static readonly DependencyProperty CompanionProperty = DependencyProperty.Register(
        nameof(Companion),
        typeof(CompanionKind),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(CompanionKind.Mimo, OnCharacterChanged));

    public static readonly DependencyProperty MoodProperty = DependencyProperty.Register(
        nameof(Mood),
        typeof(PetMood),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(PetMood.Waiting, OnCharacterChanged));

    public static readonly DependencyProperty AnimationModeProperty = DependencyProperty.Register(
        nameof(AnimationMode),
        typeof(MimoAnimationMode),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(MimoAnimationMode.Automatic, OnMotionChanged));

    public static readonly DependencyProperty ReducedMotionProperty = DependencyProperty.Register(
        nameof(ReducedMotion),
        typeof(bool),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(false, OnMotionChanged));

    public static readonly DependencyProperty BubbleTextProperty = DependencyProperty.Register(
        nameof(BubbleText),
        typeof(string),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(string.Empty, OnTextChanged));

    public static readonly DependencyProperty MoodTitleProperty = DependencyProperty.Register(
        nameof(MoodTitle),
        typeof(string),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(string.Empty, OnTextChanged));

    public static readonly DependencyProperty DetailTextProperty = DependencyProperty.Register(
        nameof(DetailText),
        typeof(string),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(string.Empty, OnTextChanged));

    public static readonly DependencyProperty PressureProperty = DependencyProperty.Register(
        nameof(Pressure),
        typeof(double),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(0d, OnPressureChanged));

    public static readonly DependencyProperty AvatarSizeProperty = DependencyProperty.Register(
        nameof(AvatarSize),
        typeof(double),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(66d, OnAvatarSizeChanged, CoerceAvatarSize));

    public static readonly DependencyProperty TrendPointsProperty = DependencyProperty.Register(
        nameof(TrendPoints),
        typeof(IEnumerable<double>),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(null, OnTrendChanged));

    public static readonly DependencyProperty ShowDetailsProperty = DependencyProperty.Register(
        nameof(ShowDetails),
        typeof(bool),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(true, OnShowDetailsChanged));

    public static readonly DependencyProperty PresentationModeProperty = DependencyProperty.Register(
        nameof(PresentationMode),
        typeof(CompanionPresentationMode),
        typeof(CompanionControl),
        new FrameworkPropertyMetadata(CompanionPresentationMode.Compact, OnPresentationModeChanged));

    private readonly DispatcherTimer _poseTimer;
    private readonly DispatcherTimer _blinkTimer;
    private readonly SystemMotionSettings _systemMotionSettings;
    private readonly List<MotionPart> _leftParts = [];
    private readonly List<MotionPart> _rightParts = [];
    private readonly List<MotionPart> _headParts = [];
    private readonly List<MotionPart> _leftLegParts = [];
    private readonly List<MotionPart> _rightLegParts = [];
    private readonly List<MotionPart> _tailParts = [];
    private readonly List<TranslationPart> _positiveTranslationParts = [];
    private readonly List<TranslationPart> _negativeTranslationParts = [];
    private readonly List<FrameworkElement> _effectOpacityParts = [];
    private readonly List<ScaleTransform> _eyeScales = [];
    private Canvas? _drawingCanvas;

    public CompanionControl()
        : this(SystemMotionSettings.Current)
    {
    }

    internal CompanionControl(SystemMotionSettings systemMotionSettings)
    {
        _systemMotionSettings = systemMotionSettings
            ?? throw new ArgumentNullException(nameof(systemMotionSettings));
        InitializeComponent();
        _poseTimer = new DispatcherTimer(DispatcherPriority.Background);
        _poseTimer.Tick += OnPoseTimerTick;
        _blinkTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(4.4),
        };
        _blinkTimer.Tick += OnBlinkTimerTick;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        IsVisibleChanged += OnIsVisibleChanged;
        AvatarHost.SizeChanged += (_, _) => UpdateQuotaRing();
    }

    public CompanionKind Companion
    {
        get => (CompanionKind)GetValue(CompanionProperty);
        set => SetValue(CompanionProperty, value);
    }

    public PetMood Mood
    {
        get => (PetMood)GetValue(MoodProperty);
        set => SetValue(MoodProperty, value);
    }

    public MimoAnimationMode AnimationMode
    {
        get => (MimoAnimationMode)GetValue(AnimationModeProperty);
        set => SetValue(AnimationModeProperty, value);
    }

    public bool ReducedMotion
    {
        get => (bool)GetValue(ReducedMotionProperty);
        set => SetValue(ReducedMotionProperty, value);
    }

    public string BubbleText
    {
        get => (string)GetValue(BubbleTextProperty);
        set => SetValue(BubbleTextProperty, value);
    }

    public string MoodTitle
    {
        get => (string)GetValue(MoodTitleProperty);
        set => SetValue(MoodTitleProperty, value);
    }

    public string DetailText
    {
        get => (string)GetValue(DetailTextProperty);
        set => SetValue(DetailTextProperty, value);
    }

    public double Pressure
    {
        get => (double)GetValue(PressureProperty);
        set => SetValue(PressureProperty, value);
    }

    public double AvatarSize
    {
        get => (double)GetValue(AvatarSizeProperty);
        set => SetValue(AvatarSizeProperty, value);
    }

    public IEnumerable<double>? TrendPoints
    {
        get => (IEnumerable<double>?)GetValue(TrendPointsProperty);
        set => SetValue(TrendPointsProperty, value);
    }

    public bool ShowDetails
    {
        get => (bool)GetValue(ShowDetailsProperty);
        set => SetValue(ShowDetailsProperty, value);
    }

    public CompanionPresentationMode PresentationMode
    {
        get => (CompanionPresentationMode)GetValue(PresentationModeProperty);
        set => SetValue(PresentationModeProperty, value);
    }

    private bool EffectiveReducedMotion => ReducedMotion
                                           || (!ForceMotionForDiagnostics
                                               && _systemMotionSettings.ReduceMotion);

    internal bool EffectiveReducedMotionForDiagnostics => EffectiveReducedMotion;

    private static object CoerceAvatarSize(DependencyObject sender, object value) =>
        Math.Clamp((double)value, 30, 120);

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        ThemeResourceManager.ResourcesChanged -= OnResourcesChanged;
        ThemeResourceManager.ResourcesChanged += OnResourcesChanged;
        PropertyChangedEventManager.RemoveHandler(
            _systemMotionSettings,
            OnSystemMotionSettingsChanged,
            nameof(SystemMotionSettings.AnimationsEnabled));
        PropertyChangedEventManager.AddHandler(
            _systemMotionSettings,
            OnSystemMotionSettingsChanged,
            nameof(SystemMotionSettings.AnimationsEnabled));
        DetailsHost.Visibility = ShowDetails ? Visibility.Visible : Visibility.Collapsed;
        ApplyPresentationMode();
        RebuildCharacter();
        UpdateStateVisuals();
        UpdateQuotaRing();
        DrawSparkline();
        ConfigureMotion();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        ThemeResourceManager.ResourcesChanged -= OnResourcesChanged;
        PropertyChangedEventManager.RemoveHandler(
            _systemMotionSettings,
            OnSystemMotionSettingsChanged,
            nameof(SystemMotionSettings.AnimationsEnabled));
        StopMotion();
    }

    private void OnSystemMotionSettingsChanged(object? sender, PropertyChangedEventArgs e) =>
        ConfigureMotion();

    private void OnIsVisibleChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (IsLoaded && IsVisible)
        {
            ConfigureMotion();
        }
        else
        {
            StopMotion();
        }
    }

    private void OnResourcesChanged(object? sender, EventArgs e)
    {
        RebuildCharacter();
        UpdateStateVisuals();
        UpdateQuotaRing();
        DrawSparkline();
        UpdateAccessibility();
    }

    private static void OnCharacterChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var control = (CompanionControl)sender;
        if (control.CharacterCanvas is null)
        {
            return;
        }

        control.RebuildCharacter();
        control.UpdateStateVisuals();
        control.UpdateQuotaRing();
        control.DrawSparkline();
        control.ConfigureMotion();
    }

    private static void OnMotionChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var control = (CompanionControl)sender;
        if (control.CharacterCanvas is not null)
        {
            control.ConfigureMotion();
        }
    }

    private static void OnTextChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e) =>
        ((CompanionControl)sender).UpdateAccessibility();

    private static void OnPressureChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var control = (CompanionControl)sender;
        control.UpdateQuotaRing();
        if (control.Companion is CompanionKind.Mimo or CompanionKind.Pico)
        {
            control.RebuildCharacter();
        }
    }

    private static void OnAvatarSizeChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var control = (CompanionControl)sender;
        control.MinHeight = (double)e.NewValue;
        control.UpdateQuotaRing();
    }

    private static void OnTrendChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e) =>
        ((CompanionControl)sender).DrawSparkline();

    private static void OnShowDetailsChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var control = (CompanionControl)sender;
        if (control.DetailsHost is not null)
        {
            control.DetailsHost.Visibility = (bool)e.NewValue ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private static void OnPresentationModeChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var control = (CompanionControl)sender;
        if (control.DetailsHost is not null)
        {
            control.ApplyPresentationMode();
        }
    }

    private void ConfigureMotion()
    {
        StopMotion();
        var interval = AnimationMode.UpdateInterval(Mood);
        var staticPose = EffectiveReducedMotion || interval is null;
        ApplyPose(animate: false, forceStatic: staticPose);

        if (staticPose || !IsLoaded || !IsVisible)
        {
            return;
        }

        _poseTimer.Interval = interval!.Value;
        _poseTimer.Start();
        if (Mood is not PetMood.Sleepy and not PetMood.Tired)
        {
            _blinkTimer.Start();
        }
    }

    private void StopMotion()
    {
        _poseTimer.Stop();
        _blinkTimer.Stop();
        foreach (var eye in _eyeScales)
        {
            eye.BeginAnimation(ScaleTransform.ScaleYProperty, null);
            eye.ScaleY = Mood == PetMood.Sleepy ? 0.38 : 1;
        }
    }

    private void OnPoseTimerTick(object? sender, EventArgs e)
    {
        ApplyPose(animate: true, forceStatic: false);
    }

    private void OnBlinkTimerTick(object? sender, EventArgs e)
    {
        if (EffectiveReducedMotion || !IsVisible)
        {
            return;
        }

        foreach (var scale in _eyeScales)
        {
            scale.BeginAnimation(
                ScaleTransform.ScaleYProperty,
                new DoubleAnimation
                {
                    From = 1,
                    To = 0.16,
                    Duration = TimeSpan.FromMilliseconds(70),
                    AutoReverse = true,
                    FillBehavior = FillBehavior.Stop,
                });
        }
    }

    private void ApplyPose(bool animate, bool forceStatic)
    {
        var interval = AnimationMode.UpdateInterval(Mood) ?? TimeSpan.FromSeconds(1);
        var intervalMs = Math.Max(1L, (long)interval.TotalMilliseconds);
        var bucket = forceStatic ? 0 : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / intervalMs;
        var pose = CompanionPoseResolver.Resolve(Companion, Mood, bucket, forceStatic || EffectiveReducedMotion);
        var duration = animate && !EffectiveReducedMotion
            ? AnimationMode.TransitionDuration(Mood)
            : TimeSpan.Zero;
        ApplyAngle(_leftParts, pose.LeftPartAngle, duration);
        ApplyAngle(_rightParts, pose.RightPartAngle, duration);
        ApplyAngle(_headParts, pose.HeadAngle, duration);
        ApplyAngle(_leftLegParts, pose.LeftLegAngle, duration);
        ApplyAngle(_rightLegParts, pose.RightLegAngle, duration);
        ApplyAngle(_tailParts, pose.TailAngle, duration);
        ApplyTranslation(_positiveTranslationParts, pose.VerticalOffset, duration);
        ApplyTranslation(_negativeTranslationParts, -pose.VerticalOffset, duration);
        ApplyOpacity(_effectOpacityParts, pose.EffectOpacity, duration);
    }

    private static void ApplyAngle(IEnumerable<MotionPart> parts, double angle, TimeSpan duration)
    {
        foreach (var part in parts)
        {
            var target = part.BaseAngle + angle;
            if (duration <= TimeSpan.Zero)
            {
                part.Transform.BeginAnimation(RotateTransform.AngleProperty, null);
                part.Transform.Angle = target;
                continue;
            }

            part.Transform.BeginAnimation(
                RotateTransform.AngleProperty,
                new DoubleAnimation(target, new Duration(duration))
                {
                    EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut },
                    FillBehavior = FillBehavior.HoldEnd,
                },
                HandoffBehavior.SnapshotAndReplace);
        }
    }

    private static void ApplyTranslation(IEnumerable<TranslationPart> parts, double offset, TimeSpan duration)
    {
        foreach (var part in parts)
        {
            if (duration <= TimeSpan.Zero)
            {
                part.Transform.BeginAnimation(TranslateTransform.YProperty, null);
                part.Transform.Y = offset;
                continue;
            }

            part.Transform.BeginAnimation(
                TranslateTransform.YProperty,
                new DoubleAnimation(offset, new Duration(duration))
                {
                    EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut },
                    FillBehavior = FillBehavior.HoldEnd,
                },
                HandoffBehavior.SnapshotAndReplace);
        }
    }

    private static void ApplyOpacity(IEnumerable<FrameworkElement> parts, double opacity, TimeSpan duration)
    {
        foreach (var part in parts)
        {
            if (duration <= TimeSpan.Zero)
            {
                part.BeginAnimation(OpacityProperty, null);
                part.Opacity = opacity;
                continue;
            }

            part.BeginAnimation(
                OpacityProperty,
                new DoubleAnimation(opacity, new Duration(duration))
                {
                    EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut },
                    FillBehavior = FillBehavior.HoldEnd,
                },
                HandoffBehavior.SnapshotAndReplace);
        }
    }

    private void RebuildCharacter()
    {
        CharacterCanvas.Children.Clear();
        _drawingCanvas = CharacterCanvas;
        _leftParts.Clear();
        _rightParts.Clear();
        _headParts.Clear();
        _leftLegParts.Clear();
        _rightLegParts.Clear();
        _tailParts.Clear();
        _positiveTranslationParts.Clear();
        _negativeTranslationParts.Clear();
        _effectOpacityParts.Clear();
        _eyeScales.Clear();

        switch (Companion)
        {
            case CompanionKind.Mimo:
                BuildMimo();
                break;
            case CompanionKind.Lumi:
                BuildLumi();
                break;
            case CompanionKind.Kumo:
                BuildKumo();
                break;
            case CompanionKind.Dot:
                BuildDot();
                break;
            case CompanionKind.Navi:
                BuildNavi();
                break;
            case CompanionKind.Bori:
                BuildBori();
                break;
            case CompanionKind.Muru:
                BuildMuru();
                break;
            case CompanionKind.Tori:
                BuildTori();
                break;
            case CompanionKind.Pico:
                BuildPico();
                break;
            default:
                throw new ArgumentOutOfRangeException();
        }

        // Kumo owns the complete weather layer in the macOS source. Adding the shared
        // status glyph as well would duplicate its bolt/drop/sparkle treatment.
        if (Companion != CompanionKind.Kumo)
        {
            AddStatusGlyph();
        }
        NameText.Text = Companion.DisplayName();
        UpdateAccessibility();
        ApplyPose(false, EffectiveReducedMotion || AnimationMode == MimoAnimationMode.Still);
    }

    private void BuildMimo()
    {
        var state = StateBrush();
        var level = UsageLevelBrush();
        var secondary = TryFindResource("AccentSecondaryBrush") as Brush ?? FrozenBrush("#FF32A9D6");
        var body = TryFindResource("AppIconGradientBrush") as Brush ?? Gradient("#FFFF8A32", "#FFFF5F11");

        var leftLeg = AddCanvasGroup(() =>
        {
            Mark(AddRoundedRectangle(33.25, 66.5, 9.5, 15, level, FrozenBrush("#33FFFFFF"), 4.75, 0.7), "Companion.Mimo.Leg.Left");
            Mark(AddCapsule(28.5, 79.7, 14, 7, level), "Companion.Mimo.Foot.Left");
        }, "Companion.Mimo.LegGroup.Left");
        Register(leftLeg, MotionSide.LeftLeg, originX: 0.38, originY: 0.665);

        var rightLeg = AddCanvasGroup(() =>
        {
            Mark(AddRoundedRectangle(57.25, 66.5, 9.5, 15, secondary, FrozenBrush("#33FFFFFF"), 4.75, 0.7), "Companion.Mimo.Leg.Right");
            Mark(AddCapsule(57.5, 79.7, 14, 7, secondary), "Companion.Mimo.Foot.Right");
        }, "Companion.Mimo.LegGroup.Right");
        Register(rightLeg, MotionSide.RightLeg, originX: 0.62, originY: 0.665);

        var leftArm = AddCanvasGroup(() =>
        {
            Mark(AddRoundedRectangle(18.25, 38.5, 9.5, 22, level, FrozenBrush("#33FFFFFF"), 4.75, 0.7), "Companion.Mimo.Arm.Left");
            Mark(AddEllipse(17.5, 58, 11, 11, level, null), "Companion.Mimo.Hand.Left");
        }, "Companion.Mimo.ArmGroup.Left");
        Register(leftArm, MotionSide.Left, originX: 0.23, originY: 0.385);

        var rightArm = AddCanvasGroup(() =>
        {
            Mark(AddRoundedRectangle(72.25, 38.5, 9.5, 22, secondary, FrozenBrush("#33FFFFFF"), 4.75, 0.7), "Companion.Mimo.Arm.Right");
            Mark(AddEllipse(71.5, 58, 11, 11, secondary, null), "Companion.Mimo.Hand.Right");
        }, "Companion.Mimo.ArmGroup.Right");
        Register(rightArm, MotionSide.Right, originX: 0.77, originY: 0.385);

        Mark(AddCapsule(15.75, 34, 10.5, 25, MutedBrush(level, 0.7)), "Companion.Mimo.Earpiece.Left");
        Mark(AddCapsule(73.75, 34, 10.5, 25, MutedBrush(secondary, 0.7)), "Companion.Mimo.Earpiece.Right");

        Mark(AddRoundedRectangle(22, 21.5, 56, 58, body, FrozenBrush("#47FFFFFF"), 18, 1.2), "Companion.Mimo.Body");
        Mark(AddRoundedRectangle(28.5, 30.5, 43, 25, Ink, null, 10), "Companion.Mimo.Screen");
        BuildFace(50, 43.5, 78, state);

        if (Mood == PetMood.Focused)
        {
            Mark(AddRoundedRectangle(23, 58, 54, 25, Gradient("#FF1F2433", "#FF0B0F1C"), FrozenBrush("#57FFFFFF"), 4.5, 0.8), "Companion.Mimo.Laptop.Lid");
            Mark(AddEllipse(45.25, 68.25, 9.5, 9.5, state, null), "Companion.Mimo.Laptop.Logo");
            AddEllipse(48.75, 71.75, 2.5, 2.5, FrozenBrush("#E6FFFFFF"), null);

            Mark(
                AddPolygon([new(21, 49.5), new(79, 49.5), new(75.5, 57.5), new(24.5, 57.5)], Gradient("#EBFFFFFF", "#9EFFFFFF"), null),
                "Companion.Mimo.KeyboardDeck");
            for (var row = 0; row < 2; row++)
            {
                for (var column = 0; column < 5; column++)
                {
                    var key = AddCapsule(35.5 + column * 6.2, 51 + row * 2.2, 5, 1.2, row == 1 && column == 2 ? MutedBrush(state, 0.72) : FrozenBrush("#7A000000"));
                    Mark(key, $"Companion.Mimo.Keyboard.Key.{row}.{column}");
                }
            }

            Mark(AddEllipse(29.5, 47, 9, 9, level, FrozenBrush("#40FFFFFF"), 0.6), "Companion.Mimo.LaptopHand.Left");
            Mark(AddEllipse(61.5, 47, 9, 9, secondary, FrozenBrush("#40FFFFFF"), 0.6), "Companion.Mimo.LaptopHand.Right");
        }
        else
        {
            Mark(AddEllipse(46.25, 66.75, 7.5, 7.5, FrozenBrush("#EBFFFFFF"), state, 1.2), "Companion.Mimo.Status");
        }
    }

    private void BuildLumi()
    {
        var state = StateBrush();
        if (Mood is PetMood.Focused or PetMood.Refreshed)
        {
            Mark(
                AddPolygon([new(21, 31), new(79, 31), new(50, 89)], FrozenBrush("#29FFD14D"), null),
                "Companion.Lumi.Beam");
        }

        AddCapsule(46.25, 40, 7.5, 38, FrozenBrush("#FF336D9E"));
        Mark(
            AddRoundedRectangle(28.5, 73, 43, 10, FrozenBrush("#FF1F3A4D"), FrozenBrush("#52FFFFFF"), 5, 0.7),
            "Companion.Lumi.Base");
        var shade = AddCanvasGroup(() =>
        {
            Mark(
                AddPolygon([new(40, 17), new(60, 17), new(75, 53), new(25, 53)], Gradient("#FFFFD147", "#FFFF8C2D"), FrozenBrush("#61FFFFFF")),
                "Companion.Lumi.Shade");
            Mark(AddRoundedRectangle(36.5, 31.5, 27, 13, Ink, null, 4.5), "Companion.Lumi.Screen");
            BuildFace(50, 38.5, 62, state);
        }, "Companion.Lumi.ShadeGroup");
        Register(shade, MotionSide.Head, originX: 0.5, originY: 0.53);
        RegisterEffectOpacity(shade);
    }

    private void BuildKumo()
    {
        var state = StateBrush();
        var top = Mood == PetMood.Tired ? FrozenBrush("#FF626E80") : FrozenBrush("#FFC7E8FA");
        var bottom = Mood is PetMood.Sleepy or PetMood.Tired ? FrozenBrush("#FF7A94AD") : FrozenBrush("#FF6BC1ED");

        if (Mood == PetMood.Refreshed)
        {
            var sunGroup = AddCanvasGroup(() =>
            {
                const double centerX = 72;
                const double centerY = 30;
                var sun = FrozenBrush("#FFFFB82E");
                for (var index = 0; index < 8; index++)
                {
                    var angle = index * Math.PI / 4;
                    AddLine(
                        centerX + Math.Cos(angle) * 12,
                        centerY + Math.Sin(angle) * 12,
                        centerX + Math.Cos(angle) * 15,
                        centerY + Math.Sin(angle) * 15,
                        sun,
                        2);
                }

                Mark(AddEllipse(62, 20, 20, 20, sun, null), "Companion.Kumo.Sun");
            }, "Companion.Kumo.SunGroup");
            Register(sunGroup, MotionSide.Head, originX: 0.72, originY: 0.30);
        }

        var cloud = AddCanvasGroup(() =>
        {
            AddCapsule(19, 39, 62, 34, Gradient(((SolidColorBrush)top).Color, ((SolidColorBrush)bottom).Color));
            AddEllipse(20, 29, 33, 33, top, null);
            AddEllipse(36, 20, 42, 42, top, null);
            AddEllipse(61, 31, 30, 30, top, null);
            BuildFace(50, 52, 78, FrozenBrush("#FF153F5C"));
        }, "Companion.Kumo.CloudGroup");
        if (state is SolidColorBrush shadowColor)
        {
            cloud.Effect = new DropShadowEffect
            {
                Color = shadowColor.Color,
                Opacity = 0.18,
                BlurRadius = 4,
                ShadowDepth = 0,
            };
        }

        if (Mood == PetMood.Focused)
        {
            Mark(
                AddPolygon([new(48, 69), new(39, 84), new(48, 81), new(43, 94), new(62, 75), new(53, 77)], FrozenBrush("#FFFFBD1E"), null),
                "Companion.Kumo.Bolt");
        }
        else if (Mood == PetMood.Sleepy)
        {
            var firstDrop = Mark(
                AddPath("M 34,75 C 34,70 38,66 38,66 C 38,66 42,70 42,75 C 42,79 34,79 34,75 Z", FrozenBrush("#FF339EE5"), null, 0),
                "Companion.Kumo.Raindrop.0");
            var secondDrop = Mark(
                AddPath("M 52,78 C 52,73 56,69 56,69 C 56,69 60,73 60,78 C 60,82 52,82 52,78 Z", FrozenBrush("#FF339EE5"), null, 0),
                "Companion.Kumo.Raindrop.1");
            RegisterTranslation(firstDrop, positive: true);
            RegisterTranslation(secondDrop, positive: true);
        }
        else if (Mood == PetMood.Tired)
        {
            for (var index = 0; index < 3; index++)
            {
                AddCapsule(34 + index * 14, 73 + index % 2 * 4, 2.5, 15, FrozenBrush("#FF3394E0"));
            }
        }
        else if (Mood == PetMood.Refreshed)
        {
            Mark(AddText("✦", 16, 64, 14, state), "Companion.Kumo.WeatherSparkle");
        }
    }

    private void BuildDot()
    {
        var state = StateBrush();
        var left = Mark(AddRoundedRectangle(13.5, 23.5, 11, 11, state, null, 2), "Companion.Dot.Pixel.TopLeft");
        var right = Mark(AddRoundedRectangle(76.75, 37.75, 8.5, 8.5, FrozenBrush("#FF43E0B2"), null, 1.5), "Companion.Dot.Pixel.Right");
        var lowerLeft = Mark(
            AddRoundedRectangle(19.25, 70.25, 7.5, 7.5, FrozenBrush("#C76B47D1"), null, 1.4),
            "Companion.Dot.Pixel.BottomLeft");
        RegisterTranslation(left, positive: true);
        RegisterTranslation(right, positive: false);
        RegisterTranslation(lowerLeft, positive: false);

        Mark(AddRoundedRectangle(22.5, 21, 55, 58, Gradient("#FF6B47D1", "#FF2CA6BD"), FrozenBrush("#57FFFFFF"), 10, 0.8), "Companion.Dot.Body");
        AddRoundedRectangle(29, 29.5, 42, 27, Ink, null, 5.5);
        BuildFace(50, 43, 78, state);
        AddCapsule(36.5, 69, 10, 2, state);
        AddCapsule(50, 69, 6, 2, FrozenBrush("#B8FFFFFF"));
        AddCapsule(59.5, 69, 4, 2, FrozenBrush("#6BFFFFFF"));
    }

    private void BuildNavi()
    {
        var state = StateBrush();
        var orbit = Mark(AddEllipse(9, 30, 82, 40, null, FrozenBrush("#8C6E80EB"), 1.6), "Companion.Navi.Orbit");
        orbit.RenderTransform = new RotateTransform(-14);
        orbit.RenderTransformOrigin = new Point(0.5, 0.5);
        var leftProvider = AddProviderDot(8, 42, "C", FrozenBrush("#FFFF6F1F"), "Companion.Navi.Provider.C");
        var rightProvider = AddProviderDot(76, 42, "G", FrozenBrush("#FF447BFF"), "Companion.Navi.Provider.G");
        RegisterTranslation(leftProvider, positive: true);
        RegisterTranslation(rightProvider, positive: false);
        AddSolarPanel(14, 37.5, "Left");
        AddSolarPanel(66, 37.5, "Right");
        Mark(AddEllipse(27, 27, 46, 46, Gradient("#FF3D75F5", "#FF6A42CC"), FrozenBrush("#61FFFFFF"), 0.8), "Companion.Navi.Body");
        AddRoundedRectangle(33.5, 38, 33, 19, Ink, null, 4.5);
        BuildFace(50, 47.5, 66, state);
        if (Mood is PetMood.Focused or PetMood.Refreshed)
        {
            Mark(
                AddPolygon([new(43, 68), new(57, 68), new(55, 86), new(50, 92), new(45, 86)], FrozenBrush("#FFFF8A1F"), null),
                "Companion.Navi.Flame");
        }
    }

    private void BuildBori()
    {
        var state = StateBrush();
        var orange = FrozenBrush("#FFF27421");
        var cream = FrozenBrush("#FFFFDFA6");
        var tail = AddBoriTail(orange, cream);
        Register(tail, MotionSide.Tail, originX: 0.5, originY: 1);
        Mark(AddRoundedRectangle(30.5, 46, 39, 40, MutedBrush(orange, 0.92), null, 14), "Companion.Bori.Body");

        var headGroup = AddCanvasGroup(() =>
        {
            Mark(AddPolygon([new(18.5, 35), new(29.5, 7), new(40.5, 35)], orange, null), "Companion.Bori.Ear.Left");
            Mark(AddPolygon([new(59.5, 35), new(70.5, 7), new(81.5, 35)], orange, null), "Companion.Bori.Ear.Right");
            Mark(
                AddPolygon([new(24.5, 31), new(29.5, 15.5), new(35.5, 31)], FrozenBrush("#D9FFDFA6"), null),
                "Companion.Bori.EarInner.Left");
            Mark(
                AddPolygon([new(64.5, 31), new(70.5, 15.5), new(75.5, 31)], FrozenBrush("#D9FFDFA6"), null),
                "Companion.Bori.EarInner.Right");
            Mark(
                AddRoundedRectangle(24, 21, 52, 42, Gradient("#FFFF7321", "#FFD13F17"), FrozenBrush("#47FFFFFF"), 17, 0.8),
                "Companion.Bori.Head");
            AddCapsule(37.5, 43, 25, 14, cream);
            BuildFace(50, 40.5, 70, FrozenBrush("#FF291713"));
            if (Mood == PetMood.Focused)
            {
                AddEllipse(33.25, 30.5, 14, 14, null, state, 1.4);
                AddEllipse(52.75, 30.5, 14, 14, null, state, 1.4);
                AddCapsule(47.25, 36.6, 5.5, 1.8, state);
            }
        }, "Companion.Bori.HeadGroup");
        Register(headGroup, MotionSide.Head, originX: 0.5, originY: 0.42);

        if (Mood == PetMood.Focused)
        {
            Mark(AddRoundedRectangle(30, 69, 40, 16, Ink, null, 2.5), "Companion.Bori.Laptop");
            Mark(AddEllipse(47.5, 74.5, 5, 5, state, null), "Companion.Bori.LaptopStatus");
        }
    }

    private void BuildMuru()
    {
        var state = StateBrush();
        Mark(AddRoundedRectangle(34.5, 38, 31, 50, FrozenBrush("#FFF0D19F"), FrozenBrush("#57FFFFFF"), 15.5, 0.8), "Companion.Muru.Body");
        BuildFace(50, 60, 68, FrozenBrush("#FF332119"));
        var cap = AddCanvasGroup(() =>
        {
            Mark(
                AddPath(
                    "M 17,49 C 22.3,11 77.7,11 83,49 C 68.5,42.2 31.5,42.2 17,49 Z",
                    Gradient(Mood == PetMood.Tired ? "#FF9E3333" : "#FFE54848", "#FFB92F38"),
                    FrozenBrush("#57FFFFFF"),
                    0.8),
                "Companion.Muru.Cap");
            Mark(AddEllipse(29.5, 22.5, 9, 9, FrozenBrush("#D1FFFFFF"), null), "Companion.Muru.CapSpot.Left");
            Mark(AddEllipse(60.5, 27.5, 7, 7, FrozenBrush("#ADFFFFFF"), null), "Companion.Muru.CapSpot.Right");
            Mark(AddEllipse(47.25, 18.25, 5.5, 5.5, FrozenBrush("#B8FFFFFF"), null), "Companion.Muru.CapSpot.Center");
        }, "Companion.Muru.CapGroup");
        Register(cap, MotionSide.Head, originX: 0.5, originY: 0.49);
        if (Mood == PetMood.Focused)
        {
            Mark(AddRoundedRectangle(69, 64, 16, 16, state, Ink, 2.5, 0.7), "Companion.Muru.Book");
            AddLine(77, 65.5, 77, 78.5, Ink, 0.8);
        }
        else if (Mood == PetMood.Refreshed)
        {
            var leftLeaf = Mark(AddEllipse(39, 8, 13, 8, FrozenBrush("#FF3DB85A"), null), "Companion.Muru.Leaf.Left");
            leftLeaf.RenderTransform = new RotateTransform(-32);
            leftLeaf.RenderTransformOrigin = new Point(1, 0.5);
            var rightLeaf = Mark(AddEllipse(48, 8, 13, 8, FrozenBrush("#FF3DB85A"), null), "Companion.Muru.Leaf.Right");
            rightLeaf.RenderTransform = new RotateTransform(32);
            rightLeaf.RenderTransformOrigin = new Point(0, 0.5);
        }
    }

    private void BuildTori()
    {
        if (Mood is PetMood.Sleepy or PetMood.Tired)
        {
            Mark(AddCapsule(24, 72, 52, 3.5, FrozenBrush("#B88D5729")), "Companion.Tori.Perch.0");
            Mark(AddCapsule(27, 77.3, 46, 3.5, FrozenBrush("#B88D5729")), "Companion.Tori.Perch.1");
            Mark(AddCapsule(30, 82.6, 40, 3.5, FrozenBrush("#B88D5729")), "Companion.Tori.Perch.2");
        }

        var leftWing = AddCanvasGroup(() =>
        {
            AddPath("M 35.5,54 C 25,35 10.5,43.4 10.5,73 C 21,69.2 29.5,62.4 35.5,54 Z", FrozenBrush("#FF3D8FDB"), null, 0);
        }, "Companion.Tori.Wing.Left");
        var rightWing = AddCanvasGroup(() =>
        {
            AddPath("M 64.5,54 C 75,35 89.5,43.4 89.5,73 C 79,69.2 70.5,62.4 64.5,54 Z", FrozenBrush("#FF3D8FDB"), null, 0);
        }, "Companion.Tori.Wing.Right");
        Register(leftWing, MotionSide.Left, originX: 0.355, originY: 0.54);
        Register(rightWing, MotionSide.Right, originX: 0.645, originY: 0.54);
        Mark(AddEllipse(25, 25, 50, 50, Gradient("#FFF9B829", "#FFF27619"), FrozenBrush("#52FFFFFF"), 0.8), "Companion.Tori.Body");
        BuildFace(50, 47, 68, FrozenBrush("#FF261B12"));
        Mark(
            AddPolygon([new(44.5, 52), new(55.5, 52), new(50, 62)], FrozenBrush("#FFE94B1B"), null),
            "Companion.Tori.Beak");
    }

    private void BuildPico()
    {
        var state = StateBrush();
        var pink = FrozenBrush("#FFF55C85");
        var tail = Mark(AddCapsule(74.5, 44, 9, 38, FrozenBrush("#DBF55C85")), "Companion.Pico.Tail");
        Register(tail, MotionSide.Tail, originX: 0.5, originY: 1);
        Mark(AddRoundedRectangle(26, 31, 48, 52, Gradient("#FFF55C85", "#FF4D3D7A"), FrozenBrush("#4DFFFFFF"), 13, 0.8), "Companion.Pico.Body");
        var leftEar = AddCatEar(left: true, fill: pink);
        var rightEar = AddCatEar(left: false, fill: pink);
        Register(leftEar, MotionSide.Left);
        Register(rightEar, MotionSide.Right);
        AddRoundedRectangle(32, 31.5, 36, 23, Ink, null, 5.5);
        BuildFace(50, 42.5, 70, state);
        Mark(AddRoundedRectangle(39, 65.75, 22, 8.5, null, FrozenBrush("#B8FFFFFF"), 1.8, 1.3), "Companion.Pico.BatteryTrack");
        var remaining = Math.Clamp(1 - Pressure / 100, 0.08, 1);
        Mark(AddRoundedRectangle(40.2, 67.25, 20 * remaining, 5.5, state, null, 1.2), "Companion.Pico.BatteryFill");
    }

    private void BuildFace(double centerX, double centerY, double scale, Brush color)
    {
        var eyeOffset = scale * 0.105;
        var eyeWidth = scale * 0.09;
        var eyeHeight = Mood switch
        {
            PetMood.Waiting => scale * 0.045,
            PetMood.Sleepy => scale * 0.025,
            _ => scale * 0.038,
        };

        if (Mood == PetMood.Tired)
        {
            AddCross(centerX - eyeOffset, centerY - 2, scale * 0.055, color);
            AddCross(centerX + eyeOffset, centerY - 2, scale * 0.055, color);
        }
        else
        {
            FrameworkElement left = Mood == PetMood.Waiting
                ? AddEllipse(centerX - eyeOffset - eyeHeight / 2, centerY - eyeHeight / 2 - 2, eyeHeight, eyeHeight, color, null)
                : AddCapsule(centerX - eyeOffset - eyeWidth / 2, centerY - eyeHeight / 2 - 2, eyeWidth, eyeHeight, color);
            FrameworkElement right = Mood == PetMood.Waiting
                ? AddEllipse(centerX + eyeOffset - eyeHeight / 2, centerY - eyeHeight / 2 - 2, eyeHeight, eyeHeight, color, null)
                : AddCapsule(centerX + eyeOffset - eyeWidth / 2, centerY - eyeHeight / 2 - 2, eyeWidth, eyeHeight, color);
            ConfigureEye(left, Mood == PetMood.Focused ? -11 : 0);
            ConfigureEye(right, Mood == PetMood.Focused ? 11 : 0);
        }

        switch (Mood)
        {
            case PetMood.Waiting:
            case PetMood.Focused:
                AddEllipse(centerX - 1.5, centerY + scale * 0.07, 3, 3, color, null);
                break;
            case PetMood.Refreshed:
                AddLine(centerX - 4, centerY + 5, centerX, centerY + 9, color, 1.5);
                AddLine(centerX, centerY + 9, centerX + 6, centerY + 3, color, 1.5);
                break;
            case PetMood.Tired when Companion == CompanionKind.Mimo:
            {
                var width = scale * 0.12;
                var height = scale * 0.045;
                var left = centerX - width / 2;
                var top = centerY + scale * 0.045;
                AddCanvasGroup(() =>
                {
                    AddLine(left, top + height * 0.7, left + width * 0.33, top + height * 0.3, color, 1.4);
                    AddLine(left + width * 0.33, top + height * 0.3, left + width * 0.66, top + height * 0.7, color, 1.4);
                    AddLine(left + width * 0.66, top + height * 0.7, left + width, top + height * 0.3, color, 1.4);
                }, "Companion.Mimo.Mouth.Wavy");
                break;
            }
            default:
                AddCapsule(centerX - scale * 0.045, centerY + scale * 0.07, scale * 0.09, Math.Max(1.4, scale * 0.022), color);
                break;
        }
    }

    private void ConfigureEye(FrameworkElement eye, double rotation)
    {
        var scale = new ScaleTransform(1, Mood == PetMood.Sleepy ? 0.38 : 1);
        var transforms = new TransformGroup();
        transforms.Children.Add(scale);
        if (Math.Abs(rotation) > 0.01)
        {
            transforms.Children.Add(new RotateTransform(rotation));
        }

        eye.RenderTransform = transforms;
        eye.RenderTransformOrigin = new Point(0.5, 0.5);
        _eyeScales.Add(scale);
    }

    private void AddCross(double centerX, double centerY, double radius, Brush color)
    {
        AddLine(centerX - radius, centerY - radius, centerX + radius, centerY + radius, color, 1.8);
        AddLine(centerX + radius, centerY - radius, centerX - radius, centerY + radius, color, 1.8);
    }

    private void AddStatusGlyph()
    {
        if (Mood == PetMood.Tired)
        {
            Mark(
                AddPath(
                    "M 77,20 C 77,15 82,10 82,10 C 82,10 87,15 87,20 C 87,25 77,25 77,20 Z",
                    StateBrush(),
                    null,
                    0),
                "Companion.StatusGlyph.Drop");
            return;
        }

        var (glyph, x, y) = Mood switch
        {
            PetMood.Focused => ("ϟ", 79d, 6d),
            PetMood.Sleepy => ("z", 82d, 7d),
            PetMood.Refreshed => ("✦", 80d, 5d),
            _ => (string.Empty, 0d, 0d),
        };
        if (glyph.Length > 0)
        {
            AddText(glyph, x, y, Mood == PetMood.Tired ? 9 : 15, StateBrush());
        }
    }

    private Brush StateBrush()
    {
        var key = Mood switch
        {
            PetMood.Waiting => "TertiaryTextBrush",
            PetMood.Calm or PetMood.Refreshed => "SuccessBrush",
            PetMood.Focused => "AccentBrush",
            PetMood.Sleepy => "WarningBrush",
            PetMood.Tired => "DangerBrush",
            _ => "AccentBrush",
        };
        return TryFindResource(key) as Brush ?? FrozenBrush("#FF22A6DE");
    }

    private Brush UsageLevelBrush()
    {
        var key = Pressure switch
        {
            >= 90 => "DangerBrush",
            >= 70 => "WarningBrush",
            _ => "AccentBrush",
        };
        return TryFindResource(key) as Brush ?? FrozenBrush("#FFFF6F0F");
    }

    private void UpdateStateVisuals()
    {
        if (MoodBadge is null || MoodText is null)
        {
            return;
        }

        var state = StateBrush();
        MoodText.Foreground = state;
        MoodBadge.Background = MutedBrush(state, 0.12);
    }

    private static Brush MutedBrush(Brush source, double opacity)
    {
        if (source is not SolidColorBrush solid)
        {
            return source;
        }

        var color = solid.Color;
        var muted = Color.FromArgb(
            (byte)Math.Round(color.A * Math.Clamp(opacity, 0, 1)),
            color.R,
            color.G,
            color.B);
        var brush = new SolidColorBrush(muted);
        brush.Freeze();
        return brush;
    }

    private void ApplyPresentationMode()
    {
        if (DetailsHost is null)
        {
            return;
        }

        var centered = PresentationMode is CompanionPresentationMode.Summary or CompanionPresentationMode.Wide;
        AvatarHost.VerticalAlignment = centered ? VerticalAlignment.Center : VerticalAlignment.Top;
        DetailsHost.VerticalAlignment = centered ? VerticalAlignment.Center : VerticalAlignment.Top;

        switch (PresentationMode)
        {
            case CompanionPresentationMode.Summary:
                DetailsHost.Margin = new Thickness(12, 0, 0, 0);
                NameRow.Height = new GridLength(18);
                DetailRow.Height = new GridLength(20);
                NameText.FontSize = 13;
                MoodBadge.Margin = new Thickness(6, 0, 0, 0);
                MoodBadge.Padding = new Thickness(6, 2, 6, 2);
                MoodBadge.CornerRadius = new CornerRadius(9);
                MoodText.FontSize = 10;
                BubbleMessage.Margin = new Thickness(0, 3, 0, 2);
                BubbleMessage.FontSize = 11;
                BubbleMessage.FontWeight = FontWeights.Medium;
                BubbleMessage.LineHeight = 14;
                BubbleMessage.MaxHeight = 28;
                DetailMessage.FontSize = 10;
                DetailMessage.FontWeight = FontWeights.SemiBold;
                SparklineCanvas.Width = 60;
                SparklineCanvas.Height = 20;
                SparklineCanvas.Margin = new Thickness(8, 0, 0, 0);
                break;

            case CompanionPresentationMode.Wide:
                ApplyCompactTypography(sparklineWidth: 30, detailsSpacing: 10);
                break;

            case CompanionPresentationMode.Compact:
            default:
                ApplyCompactTypography(sparklineWidth: 34, detailsSpacing: 9);
                break;
        }

        DrawSparkline();
    }

    private void ApplyCompactTypography(double sparklineWidth, double detailsSpacing)
    {
        DetailsHost.Margin = new Thickness(detailsSpacing, 0, 0, 0);
        NameRow.Height = new GridLength(16);
        DetailRow.Height = new GridLength(14);
        NameText.FontSize = 12;
        MoodBadge.Margin = new Thickness(5, 0, 0, 0);
        MoodBadge.Padding = new Thickness(5, 1, 5, 1);
        MoodBadge.CornerRadius = new CornerRadius(7);
        MoodText.FontSize = 8.5;
        BubbleMessage.Margin = new Thickness(0, 2, 0, 1);
        BubbleMessage.FontSize = 9.2;
        BubbleMessage.FontWeight = FontWeights.SemiBold;
        BubbleMessage.LineHeight = 12;
        BubbleMessage.MaxHeight = 36;
        DetailMessage.FontSize = 8.5;
        DetailMessage.FontWeight = FontWeights.Medium;
        SparklineCanvas.Width = sparklineWidth;
        SparklineCanvas.Height = 13;
        SparklineCanvas.Margin = new Thickness(4, 0, 0, 0);
    }

    private void UpdateQuotaRing()
    {
        if (QuotaProgress is null)
        {
            return;
        }

        var thickness = Math.Max(2, AvatarSize * 0.055);
        QuotaTrack.Stroke = TryFindResource("AccentMutedBrush") as Brush
                            ?? TryFindResource("TrackBrush") as Brush
                            ?? FrozenBrush("#1F0EA5E9");
        QuotaTrack.StrokeThickness = thickness;
        QuotaTrack.Margin = new Thickness(thickness / 2);
        QuotaProgress.Stroke = StateBrush();
        QuotaProgress.StrokeThickness = thickness;
        var size = AvatarHost.ActualWidth > 0 ? AvatarHost.ActualWidth : AvatarSize;
        var center = size / 2;
        var radius = Math.Max(1, center - thickness);
        var progress = Math.Clamp(Pressure / 100, 0.04, 1);
        var geometry = new PathGeometry();
        var figure = new PathFigure { StartPoint = new Point(center, center - radius) };
        if (progress >= 0.9999)
        {
            figure.Segments.Add(new ArcSegment(new Point(center, center + radius), new Size(radius, radius), 0, false, SweepDirection.Clockwise, true));
            figure.Segments.Add(new ArcSegment(new Point(center, center - radius), new Size(radius, radius), 0, false, SweepDirection.Clockwise, true));
        }
        else
        {
            var angle = -90 + progress * 360;
            var radians = angle * Math.PI / 180;
            var end = new Point(center + radius * Math.Cos(radians), center + radius * Math.Sin(radians));
            figure.Segments.Add(new ArcSegment(end, new Size(radius, radius), 0, progress > 0.5, SweepDirection.Clockwise, true));
        }

        geometry.Figures.Add(figure);
        QuotaProgress.Data = geometry;
    }

    private void DrawSparkline()
    {
        if (SparklineCanvas is null)
        {
            return;
        }

        SparklineCanvas.Children.Clear();
        var points = TrendPoints?.Where(double.IsFinite).ToArray() ?? [];
        SparklineCanvas.Visibility = points.Length > 1 ? Visibility.Visible : Visibility.Collapsed;
        if (points.Length < 2)
        {
            return;
        }

        var width = double.IsFinite(SparklineCanvas.Width) ? SparklineCanvas.Width : 34;
        var height = double.IsFinite(SparklineCanvas.Height) ? SparklineCanvas.Height : 13;
        var minimum = points.Min();
        var maximum = points.Max();
        var range = Math.Max(8, maximum - minimum);
        var polyline = new Polyline
        {
            Stroke = StateBrush(),
            StrokeThickness = 1.8,
            StrokeLineJoin = PenLineJoin.Round,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
        };
        for (var index = 0; index < points.Length; index++)
        {
            var x = width * index / (points.Length - 1);
            var normalized = (points[index] - minimum) / range;
            var y = height - (height * normalized * 0.8 + height * 0.1);
            polyline.Points.Add(new Point(x, y));
        }

        SparklineCanvas.Children.Add(polyline);
    }

    private void UpdateAccessibility()
    {
        if (NameText is null)
        {
            return;
        }

        var mood = string.IsNullOrWhiteSpace(MoodTitle)
            ? ThemeResourceManager.GetString($"Companion.Mood.{Mood}", Mood.ToString())
            : MoodTitle;
        var name = string.Join(", ", new[] { Companion.DisplayName(), mood, BubbleText, DetailText }
            .Where(value => !string.IsNullOrWhiteSpace(value)));
        AutomationProperties.SetName(this, name);
        AutomationProperties.SetHelpText(
            this,
            ThemeResourceManager.GetString("Companion.AccessibilityHelp", "A companion that reacts to usage"));
    }

    private Ellipse AddEllipse(double left, double top, double width, double height, Brush? fill, Brush? stroke, double strokeThickness = 0)
    {
        var shape = new Ellipse
        {
            Width = width,
            Height = height,
            Fill = fill,
            Stroke = stroke,
            StrokeThickness = stroke is null ? 0 : strokeThickness,
        };
        return Place(shape, left, top);
    }

    private Grid AddProviderDot(double left, double top, string label, Brush fill, string automationId)
    {
        var group = new Grid
        {
            Width = 16,
            Height = 16,
            IsHitTestVisible = false,
        };
        group.Children.Add(new Ellipse
        {
            Fill = fill,
            Stroke = FrozenBrush("#61FFFFFF"),
            StrokeThickness = 0.8,
        });
        var text = new TextBlock
        {
            Text = label,
            FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI"),
            FontSize = 7.5,
            FontWeight = FontWeights.Black,
            Foreground = White,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            VerticalAlignment = System.Windows.VerticalAlignment.Center,
            TextAlignment = System.Windows.TextAlignment.Center,
        };
        Mark(text, automationId);
        group.Children.Add(text);
        return Place(group, left, top);
    }

    private Canvas AddSolarPanel(double left, double top, string side)
    {
        var group = new Canvas
        {
            Width = 20,
            Height = 25,
            IsHitTestVisible = false,
        };
        group.Children.Add(new Rectangle
        {
            Width = 20,
            Height = 25,
            RadiusX = 1.8,
            RadiusY = 1.8,
            Fill = FrozenBrush("#FF1F3D78"),
        });
        for (var index = 0; index < 3; index++)
        {
            var y = 6.25 * (index + 1);
            var line = new Line
            {
                X1 = 2.5,
                X2 = 17.5,
                Y1 = y,
                Y2 = y,
                Stroke = FrozenBrush("#52FFFFFF"),
                StrokeThickness = 0.6,
            };
            Mark(line, $"Companion.Navi.SolarPanel.{side}.Line.{index}");
            group.Children.Add(line);
        }

        Mark(group, $"Companion.Navi.SolarPanel.{side}");
        return Place(group, left, top);
    }

    private Canvas AddBoriTail(Brush orange, Brush cream)
    {
        var group = new Canvas
        {
            Width = 18,
            Height = 52,
            IsHitTestVisible = false,
        };
        group.Children.Add(new Rectangle
        {
            Width = 18,
            Height = 52,
            RadiusX = 9,
            RadiusY = 9,
            Fill = orange,
        });
        var tip = new Rectangle
        {
            Width = 18,
            Height = 17,
            RadiusX = 9,
            RadiusY = 9,
            Fill = cream,
        };
        Canvas.SetTop(tip, 35);
        Mark(tip, "Companion.Bori.TailTip");
        group.Children.Add(tip);
        Mark(group, "Companion.Bori.Tail");
        return Place(group, 68, 32);
    }

    private Canvas AddCatEar(bool left, Brush fill)
    {
        var group = new Canvas
        {
            Width = 20,
            Height = 25,
            IsHitTestVisible = false,
        };
        group.Children.Add(new Polygon
        {
            Points = left
                ? new PointCollection([new(0, 25), new(10, 0), new(20, 25)])
                : new PointCollection([new(0, 25), new(10, 0), new(20, 25)]),
            Fill = fill,
            StrokeLineJoin = PenLineJoin.Round,
        });
        var inner = new Polygon
        {
            Points = left
                ? new PointCollection([new(5.5, 19), new(10, 7), new(14.5, 19)])
                : new PointCollection([new(5.5, 19), new(10, 7), new(14.5, 19)]),
            Fill = FrozenBrush("#73FFFFFF"),
            StrokeLineJoin = PenLineJoin.Round,
        };
        Mark(inner, left ? "Companion.Pico.EarInner.Left" : "Companion.Pico.EarInner.Right");
        group.Children.Add(inner);
        Mark(group, left ? "Companion.Pico.Ear.Left" : "Companion.Pico.Ear.Right");
        return Place(group, left ? 21 : 59, 10.5);
    }

    private Rectangle AddRoundedRectangle(double left, double top, double width, double height, Brush? fill, Brush? stroke, double radius, double strokeThickness = 0)
    {
        var shape = new Rectangle
        {
            Width = width,
            Height = height,
            Fill = fill,
            Stroke = stroke,
            StrokeThickness = stroke is null ? 0 : strokeThickness,
            RadiusX = radius,
            RadiusY = radius,
        };
        return Place(shape, left, top);
    }

    private Rectangle AddCapsule(double left, double top, double width, double height, Brush fill) =>
        AddRoundedRectangle(left, top, width, height, fill, null, Math.Min(width, height) / 2);

    private Line AddLine(double x1, double y1, double x2, double y2, Brush stroke, double thickness)
    {
        var line = new Line
        {
            X1 = x1,
            Y1 = y1,
            X2 = x2,
            Y2 = y2,
            Stroke = stroke,
            StrokeThickness = thickness,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
        };
        DrawingCanvas.Children.Add(line);
        return line;
    }

    private Polygon AddPolygon(IEnumerable<Point> points, Brush? fill, Brush? stroke)
    {
        var polygon = new Polygon
        {
            Points = new PointCollection(points),
            Fill = fill,
            Stroke = stroke,
            StrokeThickness = stroke is null ? 0 : 1,
            StrokeLineJoin = PenLineJoin.Round,
        };
        DrawingCanvas.Children.Add(polygon);
        return polygon;
    }

    private Path AddPath(string data, Brush? fill, Brush? stroke, double strokeThickness)
    {
        var path = new Path
        {
            Data = Geometry.Parse(data),
            Fill = fill,
            Stroke = stroke,
            StrokeThickness = stroke is null ? 0 : strokeThickness,
            StrokeLineJoin = PenLineJoin.Round,
        };
        DrawingCanvas.Children.Add(path);
        return path;
    }

    private TextBlock AddText(string text, double left, double top, double fontSize, Brush foreground)
    {
        var block = new TextBlock
        {
            Text = text,
            FontFamily = new FontFamily("Segoe UI Symbol, Segoe UI"),
            FontSize = fontSize,
            FontWeight = FontWeights.Bold,
            Foreground = foreground,
        };
        return Place(block, left, top);
    }

    private T Place<T>(T element, double left, double top) where T : FrameworkElement
    {
        Canvas.SetLeft(element, left);
        Canvas.SetTop(element, top);
        DrawingCanvas.Children.Add(element);
        return element;
    }

    private Canvas AddCanvasGroup(Action draw, string? automationId = null)
    {
        var group = new Canvas
        {
            Width = 100,
            Height = 100,
            IsHitTestVisible = false,
            ClipToBounds = false,
        };
        if (!string.IsNullOrWhiteSpace(automationId))
        {
            Mark(group, automationId);
        }

        DrawingCanvas.Children.Add(group);
        var previous = _drawingCanvas;
        _drawingCanvas = group;
        try
        {
            draw();
        }
        finally
        {
            _drawingCanvas = previous;
        }

        return group;
    }

    private Canvas DrawingCanvas => _drawingCanvas ?? CharacterCanvas;

    private void Register(
        FrameworkElement element,
        MotionSide side,
        double baseAngle = 0,
        double originX = 0.5,
        double originY = 0.5)
    {
        var transform = new RotateTransform(baseAngle);
        element.RenderTransform = transform;
        element.RenderTransformOrigin = new Point(originX, originY);
        var part = new MotionPart(transform, baseAngle);
        switch (side)
        {
            case MotionSide.Left:
                _leftParts.Add(part);
                break;
            case MotionSide.Right:
                _rightParts.Add(part);
                break;
            case MotionSide.Head:
                _headParts.Add(part);
                break;
            case MotionSide.LeftLeg:
                _leftLegParts.Add(part);
                break;
            case MotionSide.RightLeg:
                _rightLegParts.Add(part);
                break;
            case MotionSide.Tail:
                _tailParts.Add(part);
                break;
        }
    }

    private void RegisterTranslation(FrameworkElement element, bool positive)
    {
        var transform = new TranslateTransform();
        element.RenderTransform = transform;
        (positive ? _positiveTranslationParts : _negativeTranslationParts).Add(new TranslationPart(transform));
    }

    private void RegisterEffectOpacity(FrameworkElement element) => _effectOpacityParts.Add(element);

    private static LinearGradientBrush Gradient(string start, string end) =>
        Gradient((Color)ColorConverter.ConvertFromString(start), (Color)ColorConverter.ConvertFromString(end));

    private static LinearGradientBrush Gradient(Color start, Color end)
    {
        var brush = new LinearGradientBrush(start, end, new Point(0, 0), new Point(1, 1));
        brush.Freeze();
        return brush;
    }

    private static SolidColorBrush FrozenBrush(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    private static T Mark<T>(T element, string automationId)
        where T : DependencyObject
    {
        AutomationProperties.SetAutomationId(element, automationId);
        return element;
    }

    private enum MotionSide
    {
        Left,
        Right,
        Head,
        LeftLeg,
        RightLeg,
        Tail,
    }

    private sealed record MotionPart(RotateTransform Transform, double BaseAngle);
    private sealed record TranslationPart(TranslateTransform Transform);
}
