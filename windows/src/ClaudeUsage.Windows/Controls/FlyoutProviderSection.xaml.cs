using System.Windows;
using WpfUserControl = System.Windows.Controls.UserControl;

namespace ClaudeUsage.Windows.Controls;

public partial class FlyoutProviderSection : WpfUserControl
{
    public static readonly DependencyProperty ProviderProperty = DependencyProperty.Register(
        nameof(Provider),
        typeof(ProviderBrand),
        typeof(FlyoutProviderSection),
        new FrameworkPropertyMetadata(ProviderBrand.Claude));

    public static readonly DependencyProperty HeadingProperty = DependencyProperty.Register(
        nameof(Heading),
        typeof(string),
        typeof(FlyoutProviderSection),
        new FrameworkPropertyMetadata(string.Empty));

    public static readonly DependencyProperty EmptyMessageProperty = DependencyProperty.Register(
        nameof(EmptyMessage),
        typeof(string),
        typeof(FlyoutProviderSection),
        new FrameworkPropertyMetadata(string.Empty));

    public FlyoutProviderSection()
    {
        InitializeComponent();
    }

    public event EventHandler? RetryRequested;

    public ProviderBrand Provider
    {
        get => (ProviderBrand)GetValue(ProviderProperty);
        set => SetValue(ProviderProperty, value);
    }

    public string Heading
    {
        get => (string)GetValue(HeadingProperty);
        set => SetValue(HeadingProperty, value);
    }

    public string EmptyMessage
    {
        get => (string)GetValue(EmptyMessageProperty);
        set => SetValue(EmptyMessageProperty, value);
    }

    private void OnRetryClick(object sender, RoutedEventArgs e) =>
        RetryRequested?.Invoke(this, EventArgs.Empty);
}
