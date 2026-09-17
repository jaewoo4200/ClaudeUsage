using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace ClaudeUsage.Windows.Services;

/// <summary>
/// Applies a preferred Mac-parity size when it fits, then constrains the
/// window to the current monitor's work area at its current per-monitor DPI.
/// </summary>
public static class WindowWorkAreaSizingBehavior
{
    private static readonly ConditionalWeakTable<Window, SizingSubscription> Subscriptions = new();

    public static readonly DependencyProperty IsEnabledProperty = DependencyProperty.RegisterAttached(
        "IsEnabled",
        typeof(bool),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(false, OnIsEnabledChanged));

    public static readonly DependencyProperty PreferredClientWidthProperty = DependencyProperty.RegisterAttached(
        "PreferredClientWidth",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(double.NaN));

    public static readonly DependencyProperty PreferredClientHeightProperty = DependencyProperty.RegisterAttached(
        "PreferredClientHeight",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(double.NaN));

    public static readonly DependencyProperty MinimumClientWidthProperty = DependencyProperty.RegisterAttached(
        "MinimumClientWidth",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(0d));

    public static readonly DependencyProperty MinimumClientHeightProperty = DependencyProperty.RegisterAttached(
        "MinimumClientHeight",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(0d));

    public static readonly DependencyProperty PreferredOuterWidthProperty = DependencyProperty.RegisterAttached(
        "PreferredOuterWidth",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(double.NaN));

    public static readonly DependencyProperty PreferredOuterHeightProperty = DependencyProperty.RegisterAttached(
        "PreferredOuterHeight",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(double.NaN));

    public static readonly DependencyProperty MinimumOuterWidthProperty = DependencyProperty.RegisterAttached(
        "MinimumOuterWidth",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(0d));

    public static readonly DependencyProperty MinimumOuterHeightProperty = DependencyProperty.RegisterAttached(
        "MinimumOuterHeight",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(0d));

    public static readonly DependencyProperty PhysicalMarginPixelsProperty = DependencyProperty.RegisterAttached(
        "PhysicalMarginPixels",
        typeof(double),
        typeof(WindowWorkAreaSizingBehavior),
        new PropertyMetadata(12d));

    public static void SetIsEnabled(DependencyObject element, bool value) =>
        element.SetValue(IsEnabledProperty, value);

    public static bool GetIsEnabled(DependencyObject element) =>
        (bool)element.GetValue(IsEnabledProperty);

    public static void SetPreferredClientWidth(DependencyObject element, double value) =>
        element.SetValue(PreferredClientWidthProperty, value);

    public static double GetPreferredClientWidth(DependencyObject element) =>
        (double)element.GetValue(PreferredClientWidthProperty);

    public static void SetPreferredClientHeight(DependencyObject element, double value) =>
        element.SetValue(PreferredClientHeightProperty, value);

    public static double GetPreferredClientHeight(DependencyObject element) =>
        (double)element.GetValue(PreferredClientHeightProperty);

    public static void SetMinimumClientWidth(DependencyObject element, double value) =>
        element.SetValue(MinimumClientWidthProperty, value);

    public static double GetMinimumClientWidth(DependencyObject element) =>
        (double)element.GetValue(MinimumClientWidthProperty);

    public static void SetMinimumClientHeight(DependencyObject element, double value) =>
        element.SetValue(MinimumClientHeightProperty, value);

    public static double GetMinimumClientHeight(DependencyObject element) =>
        (double)element.GetValue(MinimumClientHeightProperty);

    public static void SetPreferredOuterWidth(DependencyObject element, double value) =>
        element.SetValue(PreferredOuterWidthProperty, value);

    public static double GetPreferredOuterWidth(DependencyObject element) =>
        (double)element.GetValue(PreferredOuterWidthProperty);

    public static void SetPreferredOuterHeight(DependencyObject element, double value) =>
        element.SetValue(PreferredOuterHeightProperty, value);

    public static double GetPreferredOuterHeight(DependencyObject element) =>
        (double)element.GetValue(PreferredOuterHeightProperty);

    public static void SetMinimumOuterWidth(DependencyObject element, double value) =>
        element.SetValue(MinimumOuterWidthProperty, value);

    public static double GetMinimumOuterWidth(DependencyObject element) =>
        (double)element.GetValue(MinimumOuterWidthProperty);

    public static void SetMinimumOuterHeight(DependencyObject element, double value) =>
        element.SetValue(MinimumOuterHeightProperty, value);

    public static double GetMinimumOuterHeight(DependencyObject element) =>
        (double)element.GetValue(MinimumOuterHeightProperty);

    public static void SetPhysicalMarginPixels(DependencyObject element, double value) =>
        element.SetValue(PhysicalMarginPixelsProperty, value);

    public static double GetPhysicalMarginPixels(DependencyObject element) =>
        (double)element.GetValue(PhysicalMarginPixelsProperty);

    private static void OnIsEnabledChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs e)
    {
        if (dependencyObject is not Window window)
        {
            throw new InvalidOperationException(
                $"{nameof(WindowWorkAreaSizingBehavior)} can only be attached to a Window.");
        }

        if ((bool)e.NewValue)
        {
            Subscriptions.GetValue(window, static value => new SizingSubscription(value)).Attach();
        }
        else if (Subscriptions.TryGetValue(window, out var subscription))
        {
            subscription.Detach();
            Subscriptions.Remove(window);
        }
    }

    private sealed class SizingSubscription(Window window)
    {
        private const int WmEnterSizeMove = 0x0231;
        private const int WmExitSizeMove = 0x0232;
        private const uint SwpNoSize = 0x0001;
        private const uint SwpNoZOrder = 0x0004;
        private const uint SwpNoActivate = 0x0010;

        private readonly Window _window = window;
        private HwndSource? _source;
        private bool _attached;
        private bool _applyQueued;
        private bool _restorePreferredRequested;
        private bool _hasApplied;
        private bool _clientSizeReleased;
        private bool _isApplying;
        private bool _isInNativeMoveSize;

        internal void Attach()
        {
            if (_attached)
            {
                return;
            }

            _attached = true;
            _window.SourceInitialized += OnSourceInitialized;
            _window.Loaded += OnLoaded;
            _window.ContentRendered += OnContentRendered;
            _window.DpiChanged += OnDpiChanged;
            _window.LocationChanged += OnLocationChanged;
            _window.StateChanged += OnStateChanged;
            _window.Closed += OnClosed;
            SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;

            var handle = new WindowInteropHelper(_window).Handle;
            if (handle != IntPtr.Zero)
            {
                AttachWindowHook(handle);
                QueueApply(restorePreferred: true);
            }
        }

        internal void Detach()
        {
            if (!_attached)
            {
                return;
            }

            _attached = false;
            _window.SourceInitialized -= OnSourceInitialized;
            _window.Loaded -= OnLoaded;
            _window.ContentRendered -= OnContentRendered;
            _window.DpiChanged -= OnDpiChanged;
            _window.LocationChanged -= OnLocationChanged;
            _window.StateChanged -= OnStateChanged;
            _window.Closed -= OnClosed;
            SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
            if (_source is not null)
            {
                _source.RemoveHook(WindowMessageHook);
                _source = null;
            }
        }

        private void OnSourceInitialized(object? sender, EventArgs e)
        {
            AttachWindowHook(new WindowInteropHelper(_window).Handle);
            QueueApply(restorePreferred: true);
        }

        private void OnLoaded(object sender, RoutedEventArgs e) =>
            QueueApply(restorePreferred: !_hasApplied);

        private void OnContentRendered(object? sender, EventArgs e) =>
            QueueApply(restorePreferred: !_hasApplied);

        private void OnDpiChanged(object sender, System.Windows.DpiChangedEventArgs e) =>
            QueueApply(restorePreferred: true);

        private void OnLocationChanged(object? sender, EventArgs e)
        {
            if (!_isInNativeMoveSize)
            {
                QueueApply(restorePreferred: false);
            }
        }

        private void OnStateChanged(object? sender, EventArgs e)
        {
            if (_window.WindowState == WindowState.Normal)
            {
                QueueApply(restorePreferred: false);
            }
        }

        private void OnDisplaySettingsChanged(object? sender, EventArgs e) =>
            QueueApply(restorePreferred: true);

        private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
        {
            if (e.Category is UserPreferenceCategory.Desktop or UserPreferenceCategory.General)
            {
                QueueApply(restorePreferred: true);
            }
        }

        private void OnClosed(object? sender, EventArgs e) => Detach();

        private void AttachWindowHook(IntPtr handle)
        {
            if (_source is not null || handle == IntPtr.Zero)
            {
                return;
            }

            _source = HwndSource.FromHwnd(handle);
            _source?.AddHook(WindowMessageHook);
        }

        private IntPtr WindowMessageHook(
            IntPtr window,
            int message,
            IntPtr wordParameter,
            IntPtr longParameter,
            ref bool handled)
        {
            switch (message)
            {
                case WmEnterSizeMove:
                    _isInNativeMoveSize = true;
                    break;
                case WmExitSizeMove:
                    _isInNativeMoveSize = false;
                    QueueApply(restorePreferred: false);
                    break;
            }

            return IntPtr.Zero;
        }

        private void QueueApply(bool restorePreferred)
        {
            if (!_attached
                || _window.Dispatcher.HasShutdownStarted
                || _window.Dispatcher.HasShutdownFinished)
            {
                return;
            }

            if (!_window.Dispatcher.CheckAccess())
            {
                _ = _window.Dispatcher.BeginInvoke(
                    () => QueueApply(restorePreferred),
                    DispatcherPriority.Background);
                return;
            }

            _restorePreferredRequested |= restorePreferred;
            if (_isInNativeMoveSize || _applyQueued)
            {
                return;
            }

            _applyQueued = true;
            _ = _window.Dispatcher.BeginInvoke(() =>
            {
                _applyQueued = false;
                if (_isInNativeMoveSize)
                {
                    return;
                }

                var shouldRestorePreferred = _restorePreferredRequested;
                _restorePreferredRequested = false;
                Apply(shouldRestorePreferred);
            }, DispatcherPriority.Loaded);
        }

        private void Apply(bool restorePreferred)
        {
            if (_isApplying || !_attached || _window.WindowState == WindowState.Minimized)
            {
                return;
            }

            var handle = new WindowInteropHelper(_window).Handle;
            if (handle == IntPtr.Zero)
            {
                return;
            }

            var preferredClientWidth = GetPreferredClientWidth(_window);
            var preferredClientHeight = GetPreferredClientHeight(_window);
            var usesClientSize = IsPositiveFinite(preferredClientWidth)
                                 && IsPositiveFinite(preferredClientHeight);
            var preferredWidth = usesClientSize
                ? preferredClientWidth
                : GetPreferredOuterWidth(_window);
            var preferredHeight = usesClientSize
                ? preferredClientHeight
                : GetPreferredOuterHeight(_window);
            if (!IsPositiveFinite(preferredWidth) || !IsPositiveFinite(preferredHeight))
            {
                return;
            }

            _isApplying = true;
            try
            {
                var dpi = VisualTreeHelper.GetDpi(_window);
                var scaleX = dpi.DpiScaleX > 0 ? dpi.DpiScaleX : 1;
                var scaleY = dpi.DpiScaleY > 0 ? dpi.DpiScaleY : 1;
                var screen = Forms.Screen.FromHandle(handle);
                var (nonClientWidth, nonClientHeight) = MeasureNonClientSize(handle, scaleX, scaleY);
                var result = WindowWorkAreaSizingPolicy.Calculate(new WindowWorkAreaSizingRequest(
                    screen.WorkingArea.Width,
                    screen.WorkingArea.Height,
                    scaleX,
                    scaleY,
                    preferredWidth,
                    preferredHeight,
                    usesClientSize ? GetMinimumClientWidth(_window) : GetMinimumOuterWidth(_window),
                    usesClientSize ? GetMinimumClientHeight(_window) : GetMinimumOuterHeight(_window),
                    nonClientWidth,
                    nonClientHeight,
                    usesClientSize,
                    GetPhysicalMarginPixels(_window)));

                _window.SizeToContent = SizeToContent.Manual;
                if (usesClientSize && !_clientSizeReleased && _window.Content is FrameworkElement content)
                {
                    content.ClearValue(FrameworkElement.WidthProperty);
                    content.ClearValue(FrameworkElement.HeightProperty);
                    _clientSizeReleased = true;
                }

                // Clear stale constraints first so moving from a large monitor
                // to a smaller one cannot leave MinWidth greater than MaxWidth.
                _window.MinWidth = 0;
                _window.MinHeight = 0;
                _window.MaxWidth = result.AvailableOuterWidth;
                _window.MaxHeight = result.AvailableOuterHeight;
                _window.MinWidth = result.MinimumOuterWidth;
                _window.MinHeight = result.MinimumOuterHeight;

                var width = restorePreferred || !_hasApplied
                    ? result.TargetOuterWidth
                    : Math.Clamp(CurrentWidth(), result.MinimumOuterWidth, result.AvailableOuterWidth);
                var height = restorePreferred || !_hasApplied
                    ? result.TargetOuterHeight
                    : Math.Clamp(CurrentHeight(), result.MinimumOuterHeight, result.AvailableOuterHeight);
                _window.Width = width;
                _window.Height = height;
                _hasApplied = true;

                if (_window.WindowState == WindowState.Normal)
                {
                    ClampPosition(handle, screen.WorkingArea, GetPhysicalMarginPixels(_window));
                }
            }
            finally
            {
                _isApplying = false;
            }
        }

        private double CurrentWidth() =>
            IsPositiveFinite(_window.ActualWidth) ? _window.ActualWidth : _window.Width;

        private double CurrentHeight() =>
            IsPositiveFinite(_window.ActualHeight) ? _window.ActualHeight : _window.Height;

        private static (double Width, double Height) MeasureNonClientSize(
            IntPtr handle,
            double scaleX,
            double scaleY)
        {
            if (!GetWindowRect(handle, out var outer) || !GetClientRect(handle, out var client))
            {
                return (0, 0);
            }

            var outerWidth = Math.Max(0, outer.Right - outer.Left);
            var outerHeight = Math.Max(0, outer.Bottom - outer.Top);
            var clientWidth = Math.Max(0, client.Right - client.Left);
            var clientHeight = Math.Max(0, client.Bottom - client.Top);
            return (
                Math.Max(0, outerWidth - clientWidth) / scaleX,
                Math.Max(0, outerHeight - clientHeight) / scaleY);
        }

        private static void ClampPosition(IntPtr handle, System.Drawing.Rectangle workArea, double marginValue)
        {
            if (!GetWindowRect(handle, out var bounds))
            {
                return;
            }

            var margin = double.IsFinite(marginValue)
                ? Math.Max(0, (int)Math.Round(marginValue))
                : 0;
            var width = Math.Max(1, bounds.Right - bounds.Left);
            var height = Math.Max(1, bounds.Bottom - bounds.Top);
            var minimumLeft = workArea.Left + margin;
            var minimumTop = workArea.Top + margin;
            var maximumLeft = Math.Max(minimumLeft, workArea.Right - width - margin);
            var maximumTop = Math.Max(minimumTop, workArea.Bottom - height - margin);
            var left = Math.Clamp(bounds.Left, minimumLeft, maximumLeft);
            var top = Math.Clamp(bounds.Top, minimumTop, maximumTop);
            if (left == bounds.Left && top == bounds.Top)
            {
                return;
            }

            _ = SetWindowPos(
                handle,
                IntPtr.Zero,
                left,
                top,
                0,
                0,
                SwpNoSize | SwpNoZOrder | SwpNoActivate);
        }

        private static bool IsPositiveFinite(double value) => double.IsFinite(value) && value > 0;

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr window, out NativeRect rectangle);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetClientRect(IntPtr window, out NativeRect rectangle);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetWindowPos(
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
}
