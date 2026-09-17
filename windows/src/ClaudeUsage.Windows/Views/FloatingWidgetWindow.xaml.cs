using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Threading;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using Microsoft.Win32;
using Forms = System.Windows.Forms;
using WpfButtonBase = System.Windows.Controls.Primitives.ButtonBase;
using WpfScrollBar = System.Windows.Controls.Primitives.ScrollBar;

namespace ClaudeUsage.Windows.Views;

public sealed class WidgetWindowEventArgs(WidgetPanelKind panelKind) : EventArgs
{
    public WidgetPanelKind PanelKind { get; } = panelKind;
}

public partial class FloatingWidgetWindow : Window
{
    // WPF's transparent HWND includes the inset that carries the shadow,
    // whereas an NSPanel shadow lives outside its frame. Clamp the transparent
    // edge by 8 px so the visible 240/480 px card remains 20 px from the work
    // area, matching the macOS panel placement.
    internal const int ShadowInset = 12;
    internal const int VisibleSurfaceWorkAreaMargin = 20;
    internal const int WorkAreaMargin = VisibleSurfaceWorkAreaMargin - ShadowInset;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;

    private readonly AppSettings _settings;
    private readonly Func<AppSettings, bool> _saveSettings;
    private bool _hasRestoredPosition;
    private bool _clampQueued;
    private bool _isApplyingPlacement;
    private bool _isExiting;

    public FloatingWidgetWindow(
        WidgetViewModel viewModel,
        AppSettings settings,
        WidgetPanelKind panelKind = WidgetPanelKind.Combined)
        : this(viewModel, settings, panelKind, SettingsStore.Save)
    {
    }

    internal FloatingWidgetWindow(
        WidgetViewModel viewModel,
        AppSettings settings,
        WidgetPanelKind panelKind,
        Func<AppSettings, bool> saveSettings)
    {
        ArgumentNullException.ThrowIfNull(viewModel);
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(saveSettings);

        _settings = settings;
        _saveSettings = saveSettings;
        PanelKind = panelKind;
        PositionKey = panelKind switch
        {
            WidgetPanelKind.Claude => WidgetPositionKeys.Claude,
            WidgetPanelKind.Codex => WidgetPositionKeys.Codex,
            _ => WidgetPositionKeys.Combined,
        };

        ThemeResourceManager.Initialize(settings);
        InitializeComponent();
        // Keep native Show() passive for the entire window lifetime. Callers
        // opt into activation only for interactions that explicitly need it;
        // tray and flyout toggles preserve the user's foreground window.
        ShowActivated = false;
        DataContext = viewModel;
        WidgetHost.PanelKind = panelKind;
        Topmost = settings.WidgetAlwaysOnTop;

        _settings.PropertyChanged += OnSettingsPropertyChanged;
        SourceInitialized += OnSourceInitialized;
        DpiChanged += (_, _) => QueueClamp();
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
    }

    public event EventHandler<WidgetWindowEventArgs>? SettingsRequested;

    public event EventHandler<WidgetWindowEventArgs>? HideRequested;

    public WidgetPanelKind PanelKind { get; }

    public string PositionKey { get; }

    /// <summary>
    /// Visual regression runs exercise real pointer movement without replacing
    /// the user's saved desktop placement.
    /// </summary>
    internal bool PersistPositionChanges { get; set; } = true;

    internal bool ExitApplicationOnHideForDiagnostics { get; set; }

    public void ShowClamped(bool activate = false)
    {
        if (!IsVisible)
        {
            Show();
        }

        if (activate)
        {
            Activate();
            Focus();
        }

        QueueClamp();
    }

    public void SavePositionAndHide()
    {
        PersistPosition();
        Hide();
    }

    public void CloseForExit()
    {
        _isExiting = true;
        Close();
    }

    private void OnSourceInitialized(object? sender, EventArgs e) =>
        Dispatcher.BeginInvoke(RestoreAndClamp, DispatcherPriority.Loaded);

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (!_hasRestoredPosition)
        {
            RestoreAndClamp();
        }
    }

    private void RestoreAndClamp()
    {
        if (_isApplyingPlacement || !IsInitialized)
        {
            return;
        }

        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        _isApplyingPlacement = true;
        try
        {
            UpdateLayout();
            if (!GetWindowRect(handle, out var bounds))
            {
                return;
            }

            _settings.WidgetPositions.TryGetValue(PositionKey, out var saved);
            var screen = FindScreen(saved?.MonitorDeviceName)
                         ?? Forms.Screen.FromPoint(Forms.Cursor.Position);
            UpdateMaximumSize(screen);
            UpdateLayout();

            if (!GetWindowRect(handle, out bounds))
            {
                return;
            }

            var width = Math.Max(1, bounds.Right - bounds.Left);
            var height = Math.Max(1, bounds.Bottom - bounds.Top);
            var defaultSlot = PanelKind == WidgetPanelKind.Codex ? 1 : 0;
            var defaultPlacement = WidgetWorkAreaLayoutPolicy.ResolveDefaultPlacement(
                screen.WorkingArea,
                width,
                height,
                defaultSlot,
                WorkAreaMargin);
            var desiredLeft = saved?.Left ?? defaultPlacement.Left;
            var desiredTop = saved?.Top ?? defaultPlacement.Top;
            PlaceClamped(handle, screen, width, height, desiredLeft, desiredTop);
            _hasRestoredPosition = true;
            PersistPosition();
        }
        finally
        {
            _isApplyingPlacement = false;
        }
    }

    private void ClampToCurrentWorkArea()
    {
        if (_isApplyingPlacement || !_hasRestoredPosition)
        {
            return;
        }

        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero || !GetWindowRect(handle, out var bounds))
        {
            return;
        }

        _isApplyingPlacement = true;
        try
        {
            var screen = Forms.Screen.FromHandle(handle);
            UpdateMaximumSize(screen);
            UpdateLayout();
            if (!GetWindowRect(handle, out bounds))
            {
                return;
            }

            var width = Math.Max(1, bounds.Right - bounds.Left);
            var height = Math.Max(1, bounds.Bottom - bounds.Top);
            PlaceClamped(handle, screen, width, height, bounds.Left, bounds.Top);
            PersistPosition();
        }
        finally
        {
            _isApplyingPlacement = false;
        }
    }

    private void PlaceClamped(
        IntPtr handle,
        Forms.Screen screen,
        int width,
        int height,
        int desiredLeft,
        int desiredTop)
    {
        var workArea = screen.WorkingArea;
        var minimumLeft = workArea.Left + WorkAreaMargin;
        var minimumTop = workArea.Top + WorkAreaMargin;
        var maximumLeft = Math.Max(minimumLeft, workArea.Right - width - WorkAreaMargin);
        var maximumTop = Math.Max(minimumTop, workArea.Bottom - height - WorkAreaMargin);
        var left = Math.Clamp(desiredLeft, minimumLeft, maximumLeft);
        var top = Math.Clamp(desiredTop, minimumTop, maximumTop);
        _ = SetWindowPos(
            handle,
            IntPtr.Zero,
            left,
            top,
            0,
            0,
            SwpNoSize | SwpNoZOrder | SwpNoActivate);
    }

    private void UpdateMaximumSize(Forms.Screen screen)
    {
        var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(this);
        MaxWidth = WidgetWorkAreaLayoutPolicy.AvailableDip(
            screen.WorkingArea.Width,
            dpi.DpiScaleX,
            WorkAreaMargin);
        MaxHeight = WidgetWorkAreaLayoutPolicy.AvailableDip(
            screen.WorkingArea.Height,
            dpi.DpiScaleY,
            WorkAreaMargin);
    }

    private void PersistPosition()
    {
        if (!PersistPositionChanges)
        {
            return;
        }

        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero || !GetWindowRect(handle, out var bounds))
        {
            return;
        }

        var screen = Forms.Screen.FromHandle(handle);
        _settings.WidgetPositions[PositionKey] = new WidgetWindowPosition
        {
            Left = bounds.Left,
            Top = bounds.Top,
            MonitorDeviceName = screen.DeviceName,
        };
        _ = _saveSettings(_settings);
    }

    private static Forms.Screen? FindScreen(string? deviceName)
    {
        if (string.IsNullOrWhiteSpace(deviceName))
        {
            return null;
        }

        return Forms.Screen.AllScreens.FirstOrDefault(screen =>
            string.Equals(screen.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase));
    }

    private void QueueClamp()
    {
        if (_clampQueued || !_hasRestoredPosition)
        {
            return;
        }

        _clampQueued = true;
        _ = Dispatcher.BeginInvoke(() =>
        {
            _clampQueued = false;
            ClampToCurrentWorkArea();
        }, DispatcherPriority.Background);
    }

    private void OnSizeChanged(object sender, SizeChangedEventArgs e) => QueueClamp();

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
    {
        if (!Dispatcher.HasShutdownStarted && !Dispatcher.HasShutdownFinished)
        {
            _ = Dispatcher.BeginInvoke(QueueClamp, DispatcherPriority.Background);
        }
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category is UserPreferenceCategory.Desktop or UserPreferenceCategory.General)
        {
            OnDisplaySettingsChanged(sender, e);
        }
    }

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppSettings.WidgetAlwaysOnTop))
        {
            Topmost = _settings.WidgetAlwaysOnTop;
        }
        else if (e.PropertyName is nameof(AppSettings.WidgetLayout)
                 or nameof(AppSettings.CompanionEnabled))
        {
            QueueClamp();
        }
    }

    private void OnMouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (e.LeftButton != System.Windows.Input.MouseButtonState.Pressed
            || e.ClickCount > 1
            || IsInteractiveElement(e.OriginalSource as DependencyObject))
        {
            return;
        }

        try
        {
            DragMove();
            ClampToCurrentWorkArea();
            e.Handled = true;
        }
        catch (InvalidOperationException)
        {
            // The mouse button may have been released before DragMove entered.
        }
    }

    private void OnMouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left
            || IsInteractiveElement(e.OriginalSource as DependencyObject))
        {
            return;
        }

        SettingsRequested?.Invoke(this, new WidgetWindowEventArgs(PanelKind));
        e.Handled = true;
    }

    private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            if (QueueDiagnosticExit())
            {
                e.Handled = true;
                return;
            }

            SavePositionAndHide();
            HideRequested?.Invoke(this, new WidgetWindowEventArgs(PanelKind));
            e.Handled = true;
            return;
        }

        if (e.Key == Key.F2)
        {
            SettingsRequested?.Invoke(this, new WidgetWindowEventArgs(PanelKind));
            e.Handled = true;
            return;
        }

        if (PanelKind != WidgetPanelKind.Combined
            || DataContext is not WidgetViewModel { IsPagedLayout: true } viewModel)
        {
            return;
        }

        switch (e.Key)
        {
            case Key.Left:
                viewModel.PreviousProviderCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.Right:
                viewModel.NextProviderCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.Home:
                viewModel.PagedProviderKind = WidgetProviderKind.Claude;
                e.Handled = true;
                break;
            case Key.End:
                viewModel.PagedProviderKind = WidgetProviderKind.Codex;
                e.Handled = true;
                break;
        }
    }

    private static bool IsInteractiveElement(DependencyObject? element)
    {
        for (var current = element; current is not null; current = GetParent(current))
        {
            if (current is WpfButtonBase
                or System.Windows.Controls.Primitives.Thumb
                or WpfScrollBar
                or System.Windows.Controls.Primitives.Selector
                or System.Windows.Controls.TextBox)
            {
                return true;
            }
        }

        return false;
    }

    private static DependencyObject? GetParent(DependencyObject element) =>
        element is System.Windows.Media.Visual or System.Windows.Media.Media3D.Visual3D
            ? System.Windows.Media.VisualTreeHelper.GetParent(element)
            : LogicalTreeHelper.GetParent(element);

    private void OnSettingsMenuClick(object sender, RoutedEventArgs e) =>
        SettingsRequested?.Invoke(this, new WidgetWindowEventArgs(PanelKind));

    private void OnHideMenuClick(object sender, RoutedEventArgs e)
    {
        if (QueueDiagnosticExit())
        {
            return;
        }

        SavePositionAndHide();
        HideRequested?.Invoke(this, new WidgetWindowEventArgs(PanelKind));
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        PersistPosition();
        if (ExitApplicationOnHideForDiagnostics && !_isExiting)
        {
            QueueDiagnosticExit();
            return;
        }

        if (_isExiting)
        {
            return;
        }

        e.Cancel = true;
        Hide();
        HideRequested?.Invoke(this, new WidgetWindowEventArgs(PanelKind));
    }

    private bool QueueDiagnosticExit()
    {
        if (!ExitApplicationOnHideForDiagnostics)
        {
            return false;
        }

        _isExiting = true;
        var application = System.Windows.Application.Current;
        if (application is not null
            && !application.Dispatcher.HasShutdownStarted
            && !application.Dispatcher.HasShutdownFinished)
        {
            _ = application.Dispatcher.BeginInvoke(
                application.Shutdown,
                DispatcherPriority.ApplicationIdle);
        }

        return true;
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        SourceInitialized -= OnSourceInitialized;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetWindowRect(IntPtr window, out NativeRect rectangle);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
