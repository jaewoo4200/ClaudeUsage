using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace ClaudeUsage.Windows.Views;

internal enum FlyoutCloseAction
{
    Hide,
    Close,
    ShutdownApplication,
}

public partial class FlyoutWindow : Window
{
    private static readonly DependencyPropertyKey ClaudeUsageTitlePropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(ClaudeUsageTitle),
            typeof(string),
            typeof(FlyoutWindow),
            new FrameworkPropertyMetadata("Claude usage"));

    private static readonly DependencyPropertyKey CodexUsageTitlePropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(CodexUsageTitle),
            typeof(string),
            typeof(FlyoutWindow),
            new FrameworkPropertyMetadata("Codex usage"));

    private static readonly DependencyPropertyKey WidgetActionTextPropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(WidgetActionText),
            typeof(string),
            typeof(FlyoutWindow),
            new FrameworkPropertyMetadata("Show widget"));

    public static readonly DependencyProperty ClaudeUsageTitleProperty =
        ClaudeUsageTitlePropertyKey.DependencyProperty;

    public static readonly DependencyProperty CodexUsageTitleProperty =
        CodexUsageTitlePropertyKey.DependencyProperty;

    public static readonly DependencyProperty WidgetActionTextProperty =
        WidgetActionTextPropertyKey.DependencyProperty;

    private readonly UsageCoordinator _coordinator;
    private readonly AppSettings _settings;
    private bool _isExiting;
    private bool _workAreaPlacementQueued;

    public FlyoutWindow(
        UsageViewModel usageViewModel,
        WidgetViewModel widgetViewModel,
        UsageCoordinator coordinator,
        AppSettings settings)
    {
        UsageViewModel = usageViewModel ?? throw new ArgumentNullException(nameof(usageViewModel));
        ArgumentNullException.ThrowIfNull(widgetViewModel);
        _coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));

        InitializeComponent();
        DataContext = widgetViewModel;
        _settings.PropertyChanged += OnSettingsPropertyChanged;
        ThemeResourceManager.ResourcesChanged += OnResourcesChanged;
        DpiChanged += OnDpiChanged;
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        UpdatePresentationText();
    }

    public event EventHandler? ClaudeLoginRequested;

    public event EventHandler? ClaudeLogoutRequested;

    public event EventHandler? OpenCodexUsageRequested;

    public event EventHandler? SettingsRequested;

    public event EventHandler? ToggleWidgetRequested;

    public event EventHandler? UsageHistoryRequested;

    public event EventHandler? QuitRequested;

    public UsageViewModel UsageViewModel { get; }

    public string ClaudeUsageTitle => (string)GetValue(ClaudeUsageTitleProperty);

    public string CodexUsageTitle => (string)GetValue(CodexUsageTitleProperty);

    public string WidgetActionText => (string)GetValue(WidgetActionTextProperty);

    internal bool ForceKeepOpenForDiagnostics { get; set; }

    internal bool PersistSettingsChanges { get; set; } = true;

    public void ToggleVisibility()
    {
        if (IsVisible)
        {
            Hide();
            return;
        }

        ShowNearNotificationArea();
    }

    public void ShowNearNotificationArea()
    {
        UpdatePresentationText();
        Show();
        Activate();
        UpdateLayout();
        PlaceInsideCurrentWorkArea(anchorToCursor: true);
    }

    public void ChooseExecutable()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = ThemeResourceManager.GetString(
                "Flyout.CodexPickerTitle",
                "Choose Codex executable"),
            Filter = ThemeResourceManager.GetString(
                "Flyout.CodexPickerFilter",
                "Codex executable (codex.exe)|codex.exe|Executable files (*.exe)|*.exe"),
            CheckFileExists = true,
            Multiselect = false,
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        _settings.CodexExecutablePath = dialog.FileName;
        if (PersistSettingsChanges)
        {
            SettingsStore.Save(_settings);
        }
        _ = _coordinator.RefreshAsync();
    }

    public void CloseForExit()
    {
        _isExiting = true;
        Close();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        switch (ResolveCloseAction(_isExiting, ForceKeepOpenForDiagnostics))
        {
            case FlyoutCloseAction.Hide:
                e.Cancel = true;
                Hide();
                return;
            case FlyoutCloseAction.ShutdownApplication:
                _isExiting = true;
                QueueApplicationShutdown();
                break;
            case FlyoutCloseAction.Close:
                break;
            default:
                throw new ArgumentOutOfRangeException();
        }

        base.OnClosing(e);
    }

    internal static FlyoutCloseAction ResolveCloseAction(
        bool isExiting,
        bool forceKeepOpenForDiagnostics) =>
        isExiting
            ? FlyoutCloseAction.Close
            : forceKeepOpenForDiagnostics
                ? FlyoutCloseAction.ShutdownApplication
                : FlyoutCloseAction.Hide;

    private static void QueueApplicationShutdown()
    {
        var application = System.Windows.Application.Current;
        if (application is not null
            && !application.Dispatcher.HasShutdownStarted
            && !application.Dispatcher.HasShutdownFinished)
        {
            _ = application.Dispatcher.BeginInvoke(
                application.Shutdown,
                DispatcherPriority.ApplicationIdle);
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        ThemeResourceManager.ResourcesChanged -= OnResourcesChanged;
        DpiChanged -= OnDpiChanged;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        base.OnClosed(e);
    }

    private void OnDeactivated(object sender, EventArgs e)
    {
        if (!ForceKeepOpenForDiagnostics && !_settings.KeepFlyoutOpen)
        {
            Hide();
        }
    }

    private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Hide();
            e.Handled = true;
        }
    }

    private void OnRefreshClick(object sender, RoutedEventArgs e) => _ = _coordinator.RefreshAsync();

    private void OnProviderRetryRequested(object? sender, EventArgs e) =>
        _ = _coordinator.RefreshAsync();

    private void OnClaudeLoginClick(object sender, RoutedEventArgs e) =>
        ClaudeLoginRequested?.Invoke(this, EventArgs.Empty);

    private void OnClaudeLogoutClick(object sender, RoutedEventArgs e) =>
        ClaudeLogoutRequested?.Invoke(this, EventArgs.Empty);

    private void OnOpenCodexUsageClick(object sender, RoutedEventArgs e) =>
        OpenCodexUsageRequested?.Invoke(this, EventArgs.Empty);

    private void OnSettingsClick(object sender, RoutedEventArgs e) =>
        SettingsRequested?.Invoke(this, EventArgs.Empty);

    private void OnToggleWidgetClick(object sender, RoutedEventArgs e) =>
        ToggleWidgetRequested?.Invoke(this, EventArgs.Empty);

    private void OnUsageHistoryClick(object sender, RoutedEventArgs e) =>
        UsageHistoryRequested?.Invoke(this, EventArgs.Empty);

    private void OnQuitClick(object sender, RoutedEventArgs e) =>
        RaiseQuitRequested(this, QuitRequested);

    internal static void RaiseQuitRequested(object sender, EventHandler? quitRequested) =>
        quitRequested?.Invoke(sender, EventArgs.Empty);

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppSettings.Language) or nameof(AppSettings.FloatingWidgetVisible))
        {
            UpdatePresentationText();
        }
    }

    private void OnResourcesChanged(object? sender, EventArgs e) => UpdatePresentationText();

    private void OnDpiChanged(object sender, System.Windows.DpiChangedEventArgs e) =>
        QueueVisibleWorkAreaPlacement();

    private void OnDisplaySettingsChanged(object? sender, EventArgs e) =>
        DispatchVisibleWorkAreaPlacement();

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category is UserPreferenceCategory.Desktop or UserPreferenceCategory.General)
        {
            DispatchVisibleWorkAreaPlacement();
        }
    }

    private void DispatchVisibleWorkAreaPlacement()
    {
        if (!Dispatcher.HasShutdownStarted && !Dispatcher.HasShutdownFinished)
        {
            _ = Dispatcher.BeginInvoke(QueueVisibleWorkAreaPlacement, DispatcherPriority.Background);
        }
    }

    private void QueueVisibleWorkAreaPlacement()
    {
        if (_workAreaPlacementQueued || !IsVisible)
        {
            return;
        }

        _workAreaPlacementQueued = true;
        _ = Dispatcher.BeginInvoke(() =>
        {
            _workAreaPlacementQueued = false;
            if (IsVisible)
            {
                PlaceInsideCurrentWorkArea(anchorToCursor: false);
            }
        }, DispatcherPriority.Loaded);
    }

    private void UpdatePresentationText()
    {
        var korean = _settings.Language == AppLanguage.Korean;
        SetValue(ClaudeUsageTitlePropertyKey, korean ? "Claude 사용량" : "Claude usage");
        SetValue(CodexUsageTitlePropertyKey, korean ? "Codex 사용량" : "Codex usage");
        SetValue(
            WidgetActionTextPropertyKey,
            _settings.FloatingWidgetVisible
                ? ThemeResourceManager.GetString("UI.HideWidget", korean ? "위젯 숨기기" : "Hide widget")
                : ThemeResourceManager.GetString("UI.ShowWidget", korean ? "위젯 켜기" : "Show widget"));
    }

    private void PlaceInsideCurrentWorkArea(bool anchorToCursor)
    {
        var handle = new WindowInteropHelper(this).Handle;
        var cursor = Forms.Cursor.Position;
        var screen = anchorToCursor
            ? Forms.Screen.FromPoint(cursor)
            : Forms.Screen.FromHandle(handle);
        var workArea = screen.WorkingArea;
        var screenBounds = screen.Bounds;
        const int margin = 12;
        const int trayGap = 12;

        var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(this);
        MaxHeight = Math.Max(240, (workArea.Height - (2 * margin)) / dpi.DpiScaleY);
        FlyoutScroll.MaxHeight = Math.Max(150, Math.Min(560, MaxHeight - 104));
        InvalidateMeasure();
        UpdateLayout();

        if (!GetWindowRect(handle, out var bounds))
        {
            return;
        }

        var width = Math.Max(1, bounds.Right - bounds.Left);
        var height = Math.Max(1, bounds.Bottom - bounds.Top);
        var x = bounds.Left;
        var y = bounds.Top;
        if (anchorToCursor)
        {
            var taskbarEdge = ResolveTaskbarEdge(cursor, screenBounds, workArea);
            x = cursor.X - width + 24;
            y = cursor.Y - height - trayGap;
            switch (taskbarEdge)
            {
                case TaskbarEdge.Top:
                    y = cursor.Y + trayGap;
                    break;
                case TaskbarEdge.Left:
                    x = cursor.X + trayGap;
                    y = cursor.Y - height + 24;
                    break;
                case TaskbarEdge.Right:
                    x = cursor.X - width - trayGap;
                    y = cursor.Y - height + 24;
                    break;
            }
        }

        var minimumX = workArea.Left + margin;
        var minimumY = workArea.Top + margin;
        var maximumX = Math.Max(minimumX, workArea.Right - width - margin);
        var maximumY = Math.Max(minimumY, workArea.Bottom - height - margin);
        x = Math.Clamp(x, minimumX, maximumX);
        y = Math.Clamp(y, minimumY, maximumY);

        _ = SetWindowPos(handle, IntPtr.Zero, x, y, 0, 0, 0x0001 | 0x0004 | 0x0010);
    }

    private static TaskbarEdge ResolveTaskbarEdge(
        System.Drawing.Point cursor,
        System.Drawing.Rectangle screen,
        System.Drawing.Rectangle workArea)
    {
        if (workArea.Top > screen.Top)
        {
            return TaskbarEdge.Top;
        }

        if (workArea.Bottom < screen.Bottom)
        {
            return TaskbarEdge.Bottom;
        }

        if (workArea.Left > screen.Left)
        {
            return TaskbarEdge.Left;
        }

        if (workArea.Right < screen.Right)
        {
            return TaskbarEdge.Right;
        }

        var distances = new (TaskbarEdge Edge, int Distance)[]
        {
            (TaskbarEdge.Top, Math.Abs(cursor.Y - screen.Top)),
            (TaskbarEdge.Bottom, Math.Abs(screen.Bottom - cursor.Y)),
            (TaskbarEdge.Left, Math.Abs(cursor.X - screen.Left)),
            (TaskbarEdge.Right, Math.Abs(screen.Right - cursor.X)),
        };
        return distances.MinBy(item => item.Distance).Edge;
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetWindowRect(IntPtr window, out NativeRect rectangle);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    private enum TaskbarEdge
    {
        Top,
        Bottom,
        Left,
        Right,
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
