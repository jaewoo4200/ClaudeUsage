using System.Windows;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.ViewModels;
using WpfMessageBox = System.Windows.MessageBox;

namespace ClaudeUsage.Windows.Views;

public partial class UsageHistoryDashboardWindow : Window
{
    public UsageHistoryDashboardWindow(UsageHistoryDashboardViewModel viewModel)
    {
        ArgumentNullException.ThrowIfNull(viewModel);
        InitializeComponent();
        ViewModel = viewModel;
        DataContext = viewModel;
    }

    public UsageHistoryDashboardViewModel ViewModel { get; }

    public event EventHandler? ClearHistoryRequested;

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
