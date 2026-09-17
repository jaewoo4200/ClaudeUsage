using System.Windows;
using System.Windows.Controls;
using ClaudeUsage.Core.Models;
using UserControl = System.Windows.Controls.UserControl;

namespace ClaudeUsage.Windows.Controls;

public partial class SettingsCompanionPreview : UserControl
{
    public static readonly DependencyProperty CompanionProperty = DependencyProperty.Register(
        nameof(Companion),
        typeof(CompanionKind),
        typeof(SettingsCompanionPreview),
        new FrameworkPropertyMetadata(CompanionKind.Mimo));

    public static readonly DependencyProperty AvatarSizeProperty = DependencyProperty.Register(
        nameof(AvatarSize),
        typeof(double),
        typeof(SettingsCompanionPreview),
        new FrameworkPropertyMetadata(40d));

    public static readonly DependencyProperty FrameSizeProperty = DependencyProperty.Register(
        nameof(FrameSize),
        typeof(double),
        typeof(SettingsCompanionPreview),
        new FrameworkPropertyMetadata(40d));

    public static readonly DependencyProperty MoodProperty = DependencyProperty.Register(
        nameof(Mood),
        typeof(PetMood),
        typeof(SettingsCompanionPreview),
        new FrameworkPropertyMetadata(PetMood.Calm));

    public static readonly DependencyProperty PressureProperty = DependencyProperty.Register(
        nameof(Pressure),
        typeof(double),
        typeof(SettingsCompanionPreview),
        new FrameworkPropertyMetadata(0d));

    public static readonly DependencyProperty AnimationModeProperty = DependencyProperty.Register(
        nameof(AnimationMode),
        typeof(MimoAnimationMode),
        typeof(SettingsCompanionPreview),
        new FrameworkPropertyMetadata(MimoAnimationMode.Still));

    public static readonly DependencyProperty ReducedMotionProperty = DependencyProperty.Register(
        nameof(ReducedMotion),
        typeof(bool),
        typeof(SettingsCompanionPreview),
        new FrameworkPropertyMetadata(true));

    public SettingsCompanionPreview()
    {
        InitializeComponent();
    }

    public CompanionKind Companion
    {
        get => (CompanionKind)GetValue(CompanionProperty);
        set => SetValue(CompanionProperty, value);
    }

    public double AvatarSize
    {
        get => (double)GetValue(AvatarSizeProperty);
        set => SetValue(AvatarSizeProperty, value);
    }

    public double FrameSize
    {
        get => (double)GetValue(FrameSizeProperty);
        set => SetValue(FrameSizeProperty, value);
    }

    public PetMood Mood
    {
        get => (PetMood)GetValue(MoodProperty);
        set => SetValue(MoodProperty, value);
    }

    public double Pressure
    {
        get => (double)GetValue(PressureProperty);
        set => SetValue(PressureProperty, value);
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
}
