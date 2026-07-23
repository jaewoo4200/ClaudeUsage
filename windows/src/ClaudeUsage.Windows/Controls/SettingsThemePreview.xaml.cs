using System.Windows;
using System.Windows.Controls;
using ClaudeUsage.Windows.Services;
using UserControl = System.Windows.Controls.UserControl;

namespace ClaudeUsage.Windows.Controls;

public partial class SettingsThemePreview : UserControl
{
    public static readonly DependencyProperty ThemeProperty = DependencyProperty.Register(
        nameof(Theme),
        typeof(ThemeKind),
        typeof(SettingsThemePreview),
        new FrameworkPropertyMetadata(ThemeKind.Daangn));

    public SettingsThemePreview()
    {
        InitializeComponent();
    }

    public ThemeKind Theme
    {
        get => (ThemeKind)GetValue(ThemeProperty);
        set => SetValue(ThemeProperty, value);
    }
}
