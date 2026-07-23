using System.Windows;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.ViewModels;
using WpfMessageBox = System.Windows.MessageBox;

namespace ClaudeUsage.Windows.Views;

public partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsViewModel viewModel)
    {
        ArgumentNullException.ThrowIfNull(viewModel);
        ThemeResourceManager.Initialize(viewModel.Settings);
        InitializeComponent();
        ViewModel = viewModel;
        DataContext = viewModel;
    }

    public SettingsViewModel ViewModel { get; }

    public event EventHandler? ClearHistoryRequested;

    public event EventHandler? OpenHistoryRequested;

    public event EventHandler? ClaudeLoginRequested;

    public event EventHandler? ClaudeLogoutRequested;

    public event EventHandler? OpenCodexUsageRequested;

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();

    private void OnClaudeLoginClick(object sender, RoutedEventArgs e) =>
        ClaudeLoginRequested?.Invoke(this, EventArgs.Empty);

    private void OnClaudeLogoutClick(object sender, RoutedEventArgs e)
    {
        var result = WpfMessageBox.Show(
            this,
            Text("Settings.ClaudeLogoutConfirmMessage", "Only the saved Claude session is deleted."),
            Text("Settings.ClaudeLogoutConfirmTitle", "Disconnect Claude?"),
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result == MessageBoxResult.Yes)
        {
            ClaudeLogoutRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnClearHistoryClick(object sender, RoutedEventArgs e)
    {
        var result = WpfMessageBox.Show(
            this,
            Text("Settings.ClearHistoryConfirmMessage", "Only ClaudeUsage local history is deleted."),
            Text("Settings.ClearHistoryConfirmTitle", "Clear usage history?"),
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result == MessageBoxResult.Yes)
        {
            ClearHistoryRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnOpenHistoryClick(object sender, RoutedEventArgs e) =>
        OpenHistoryRequested?.Invoke(this, EventArgs.Empty);

    private void OnOpenCodexUsageClick(object sender, RoutedEventArgs e) =>
        OpenCodexUsageRequested?.Invoke(this, EventArgs.Empty);

    private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == System.Windows.Input.Key.Escape)
        {
            Close();
            e.Handled = true;
        }
    }

    private static string Text(string key, string fallback) =>
        ThemeResourceManager.GetString(key, fallback);
}
