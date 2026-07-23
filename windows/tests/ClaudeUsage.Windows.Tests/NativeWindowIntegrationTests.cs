using System.IO;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using ClaudeUsage.Core.History;
using System.Windows.Interop;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Windows.Views;
using Forms = System.Windows.Forms;

namespace ClaudeUsage.Windows.Tests;

public sealed class NativeWindowIntegrationTests
{
    private const int WidgetWorkAreaMargin = FloatingWidgetWindow.WorkAreaMargin;
    private const int StandardWindowWorkAreaMargin = 12;
    private const uint WmEnterSizeMove = 0x0231;
    private const uint WmExitSizeMove = 0x0232;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;

    [Fact]
    public void FloatingWidgetRestoresMovesClampsAndPersistsThroughARealHwnd()
    {
        RunOnStaThread(() =>
        {
            var settingsDirectory = Path.Combine(
                Path.GetTempPath(),
                $"claudeusage-native-widget-{Guid.NewGuid():N}");
            var settingsPath = Path.Combine(settingsDirectory, "settings.json");
            var persistenceTimestamp = new DateTimeOffset(
                2026,
                7,
                13,
                0,
                0,
                0,
                TimeSpan.Zero);
            var primaryScreen = Forms.Screen.PrimaryScreen
                                ?? throw new InvalidOperationException("No primary monitor is available.");
            var settings = new AppSettings
            {
                Appearance = AppearanceMode.Light,
                Language = AppLanguage.English,
                WidgetLayout = WidgetLayoutMode.Stacked,
            };
            settings.WidgetPositions[WidgetPositionKeys.Combined] = new WidgetWindowPosition
            {
                Left = primaryScreen.WorkingArea.Right + 10_000,
                Top = primaryScreen.WorkingArea.Bottom + 10_000,
                MonitorDeviceName = primaryScreen.DeviceName,
            };

            var persistenceCount = 0;
            bool SaveToTemporaryPath(AppSettings current)
            {
                persistenceCount++;
                return SettingsStore.Save(current, settingsPath, persistenceTimestamp);
            }

            var usage = new UsageViewModel(settings);
            var companion = new CompanionViewModel(language: AppLanguage.English);
            using var viewModel = new WidgetViewModel(usage, settings, companion);
            var window = new FloatingWidgetWindow(
                viewModel,
                settings,
                WidgetPanelKind.Combined,
                SaveToTemporaryPath)
            {
                Opacity = 0,
            };
            FloatingWidgetWindow? restoredWindow = null;

            try
            {
                window.ShowClamped();

                Assert.Equal(180, window.MinHeight);
                Assert.False(window.ShowActivated);
                Assert.False(window.IsActive);
                var windowInset = Assert.IsType<System.Windows.Controls.Border>(
                    window.FindName("WidgetWindowInset"));
                Assert.Equal(FloatingWidgetWindow.ShadowInset, windowInset.Margin.Left);
                Assert.Equal(FloatingWidgetWindow.ShadowInset, windowInset.Margin.Top);
                Assert.Equal(FloatingWidgetWindow.ShadowInset, windowInset.Margin.Right);
                Assert.Equal(FloatingWidgetWindow.ShadowInset, windowInset.Margin.Bottom);
                Assert.Equal(
                    FloatingWidgetWindow.VisibleSurfaceWorkAreaMargin,
                    FloatingWidgetWindow.WorkAreaMargin + FloatingWidgetWindow.ShadowInset);
                var shadowHost = Assert.IsType<System.Windows.Controls.Border>(
                    window.FindName("WidgetShadowHost"));
                var shadow = Assert.IsType<DropShadowEffect>(shadowHost.Effect);
                Assert.Equal(18, shadow.BlurRadius);
                Assert.Equal(4, shadow.ShadowDepth);
                Assert.Equal(0.24, shadow.Opacity, precision: 3);

                var handle = new WindowInteropHelper(window).Handle;
                Assert.NotEqual(IntPtr.Zero, handle);
                Assert.True(IsWindow(handle));
                var screen = Forms.Screen.FromHandle(handle);
                var restoredBounds = StabilizeWindow(window);
                AssertInsideWorkArea(restoredBounds, screen.WorkingArea);
                Assert.True(persistenceCount >= 1);
                AssertMatches(
                    restoredBounds,
                    screen.DeviceName,
                    settings.WidgetPositions[WidgetPositionKeys.Combined]);

                var width = restoredBounds.Right - restoredBounds.Left;
                var height = restoredBounds.Bottom - restoredBounds.Top;
                var allScreens = Forms.Screen.AllScreens;
                Assert.True(SetWindowPos(
                    handle,
                    IntPtr.Zero,
                    allScreens.Max(candidate => candidate.WorkingArea.Right) + width + 500,
                    allScreens.Max(candidate => candidate.WorkingArea.Bottom) + height + 500,
                    0,
                    0,
                    SwpNoSize | SwpNoZOrder | SwpNoActivate));
                Assert.True(GetWindowRect(handle, out var movedBounds));
                Assert.DoesNotContain(
                    allScreens,
                    candidate => Intersects(movedBounds, candidate.WorkingArea));

                var clampedBounds = StabilizeWindow(window);
                var clampedScreen = Forms.Screen.FromHandle(handle);
                Assert.False(HaveSameBounds(movedBounds, clampedBounds));
                AssertInsideWorkArea(clampedBounds, clampedScreen.WorkingArea);
                AssertMatches(
                    clampedBounds,
                    clampedScreen.DeviceName,
                    settings.WidgetPositions[WidgetPositionKeys.Combined]);
                Assert.True(persistenceCount >= 2);

                var stackedWidth = clampedBounds.Right - clampedBounds.Left;
                settings.WidgetLayout = WidgetLayoutMode.Horizontal;

                var resizedScreen = Forms.Screen.FromHandle(handle);
                var resizedBounds = StabilizeWindow(window);
                AssertInsideWorkArea(resizedBounds, resizedScreen.WorkingArea);
                Assert.True(
                    resizedBounds.Right - resizedBounds.Left > stackedWidth,
                    $"The horizontal widget did not expand its native HWND: stacked {Format(clampedBounds)}, horizontal {Format(resizedBounds)}.");
                var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(window);
                Assert.Equal(
                    WidgetWorkAreaLayoutPolicy.AvailableDip(
                        resizedScreen.WorkingArea.Width,
                        dpi.DpiScaleX,
                        WidgetWorkAreaMargin),
                    window.MaxWidth,
                    precision: 6);
                Assert.Equal(
                    WidgetWorkAreaLayoutPolicy.AvailableDip(
                        resizedScreen.WorkingArea.Height,
                        dpi.DpiScaleY,
                        WidgetWorkAreaMargin),
                    window.MaxHeight,
                    precision: 6);
                AssertMatches(
                    resizedBounds,
                    resizedScreen.DeviceName,
                    settings.WidgetPositions[WidgetPositionKeys.Combined]);

                var resizedWidth = resizedBounds.Right - resizedBounds.Left;
                var resizedHeight = resizedBounds.Bottom - resizedBounds.Top;
                var centeredLeft = resizedScreen.WorkingArea.Left
                                   + ((resizedScreen.WorkingArea.Width - resizedWidth) / 2);
                var centeredTop = resizedScreen.WorkingArea.Top
                                  + ((resizedScreen.WorkingArea.Height - resizedHeight) / 2);
                Assert.True(SetWindowPos(
                    handle,
                    IntPtr.Zero,
                    centeredLeft,
                    centeredTop,
                    0,
                    0,
                    SwpNoSize | SwpNoZOrder | SwpNoActivate));
                var savedBounds = StabilizeWindow(window);
                Assert.Equal(centeredLeft, savedBounds.Left);
                Assert.Equal(centeredTop, savedBounds.Top);
                AssertMatches(
                    savedBounds,
                    resizedScreen.DeviceName,
                    settings.WidgetPositions[WidgetPositionKeys.Combined]);

                window.CloseForExit();
                var persistedSettings = SettingsStore.Load(settingsPath, persistenceTimestamp);
                AssertMatches(
                    savedBounds,
                    resizedScreen.DeviceName,
                    persistedSettings.WidgetPositions[WidgetPositionKeys.Combined]);

                var restoredUsage = new UsageViewModel(persistedSettings);
                var restoredCompanion = new CompanionViewModel(language: AppLanguage.English);
                using var restoredViewModel = new WidgetViewModel(
                    restoredUsage,
                    persistedSettings,
                    restoredCompanion);
                restoredWindow = new FloatingWidgetWindow(
                    restoredViewModel,
                    persistedSettings,
                    WidgetPanelKind.Combined,
                    SaveToTemporaryPath)
                {
                    Opacity = 0,
                };
                restoredWindow.ShowClamped(activate: false);

                var restoredHandle = new WindowInteropHelper(restoredWindow).Handle;
                Assert.NotEqual(IntPtr.Zero, restoredHandle);
                var restoredAgainBounds = StabilizeWindow(restoredWindow);
                var restoredScreen = Forms.Screen.FromHandle(restoredHandle);
                AssertInsideWorkArea(restoredAgainBounds, restoredScreen.WorkingArea);
                Assert.Equal(savedBounds.Left, restoredAgainBounds.Left);
                Assert.Equal(savedBounds.Top, restoredAgainBounds.Top);
                AssertMatches(
                    restoredAgainBounds,
                    restoredScreen.DeviceName,
                    persistedSettings.WidgetPositions[WidgetPositionKeys.Combined]);
            }
            finally
            {
                if (restoredWindow?.IsLoaded == true)
                {
                    restoredWindow.CloseForExit();
                }

                if (window.IsLoaded)
                {
                    window.CloseForExit();
                }

                ThemeResourceManager.Shutdown();
                if (Directory.Exists(settingsDirectory))
                {
                    Directory.Delete(settingsDirectory, recursive: true);
                }
            }
        });
    }

    [Fact]
    public void SeparateProviderWidgetsPersistAndRestoreIndependentNativePositions()
    {
        RunOnStaThread(() =>
        {
            var settingsDirectory = Path.Combine(
                Path.GetTempPath(),
                $"claudeusage-native-separate-{Guid.NewGuid():N}");
            var settingsPath = Path.Combine(settingsDirectory, "settings.json");
            var timestamp = new DateTimeOffset(2026, 7, 13, 0, 0, 0, TimeSpan.Zero);
            var settings = new AppSettings
            {
                Appearance = AppearanceMode.Light,
                Language = AppLanguage.English,
                WidgetLayout = WidgetLayoutMode.Separate,
            };

            bool SaveToTemporaryPath(AppSettings current) =>
                SettingsStore.Save(current, settingsPath, timestamp);

            var usage = new UsageViewModel(settings);
            var companion = new CompanionViewModel(language: AppLanguage.English);
            using var viewModel = new WidgetViewModel(usage, settings, companion);
            var claudeWindow = new FloatingWidgetWindow(
                viewModel,
                settings,
                WidgetPanelKind.Claude,
                SaveToTemporaryPath)
            {
                Opacity = 0,
            };
            var codexWindow = new FloatingWidgetWindow(
                viewModel,
                settings,
                WidgetPanelKind.Codex,
                SaveToTemporaryPath)
            {
                Opacity = 0,
            };
            FloatingWidgetWindow? restoredClaudeWindow = null;
            FloatingWidgetWindow? restoredCodexWindow = null;

            try
            {
                claudeWindow.ShowClamped(activate: false);
                codexWindow.ShowClamped(activate: false);
                var claudeHandle = new WindowInteropHelper(claudeWindow).Handle;
                var codexHandle = new WindowInteropHelper(codexWindow).Handle;
                Assert.NotEqual(IntPtr.Zero, claudeHandle);
                Assert.NotEqual(IntPtr.Zero, codexHandle);

                var claudeBounds = StabilizeWindow(claudeWindow);
                var codexBounds = StabilizeWindow(codexWindow);
                var screen = Forms.Screen.FromHandle(claudeHandle);
                var claudeLeft = screen.WorkingArea.Left + WidgetWorkAreaMargin + 24;
                var claudeTop = screen.WorkingArea.Top + WidgetWorkAreaMargin + 24;
                var codexWidth = codexBounds.Right - codexBounds.Left;
                var codexLeft = Math.Max(
                    screen.WorkingArea.Left + WidgetWorkAreaMargin,
                    screen.WorkingArea.Right - codexWidth - WidgetWorkAreaMargin - 24);
                var codexTop = Math.Min(
                    screen.WorkingArea.Bottom - (codexBounds.Bottom - codexBounds.Top) - WidgetWorkAreaMargin,
                    screen.WorkingArea.Top + WidgetWorkAreaMargin + 96);

                Assert.True(SetWindowPos(
                    claudeHandle,
                    IntPtr.Zero,
                    claudeLeft,
                    claudeTop,
                    0,
                    0,
                    SwpNoSize | SwpNoZOrder | SwpNoActivate));
                Assert.True(SetWindowPos(
                    codexHandle,
                    IntPtr.Zero,
                    codexLeft,
                    codexTop,
                    0,
                    0,
                    SwpNoSize | SwpNoZOrder | SwpNoActivate));
                claudeBounds = StabilizeWindow(claudeWindow);
                codexBounds = StabilizeWindow(codexWindow);
                Assert.False(HaveSameBounds(claudeBounds, codexBounds));
                AssertMatches(
                    claudeBounds,
                    Forms.Screen.FromHandle(claudeHandle).DeviceName,
                    settings.WidgetPositions[WidgetPositionKeys.Claude]);
                AssertMatches(
                    codexBounds,
                    Forms.Screen.FromHandle(codexHandle).DeviceName,
                    settings.WidgetPositions[WidgetPositionKeys.Codex]);
                Assert.False(settings.WidgetPositions.ContainsKey(WidgetPositionKeys.Combined));

                claudeWindow.CloseForExit();
                codexWindow.CloseForExit();
                var persisted = SettingsStore.Load(settingsPath, timestamp);
                AssertMatches(
                    claudeBounds,
                    Forms.Screen.FromPoint(new System.Drawing.Point(claudeBounds.Left, claudeBounds.Top)).DeviceName,
                    persisted.WidgetPositions[WidgetPositionKeys.Claude]);
                AssertMatches(
                    codexBounds,
                    Forms.Screen.FromPoint(new System.Drawing.Point(codexBounds.Left, codexBounds.Top)).DeviceName,
                    persisted.WidgetPositions[WidgetPositionKeys.Codex]);

                var restoredUsage = new UsageViewModel(persisted);
                var restoredCompanion = new CompanionViewModel(language: AppLanguage.English);
                using var restoredViewModel = new WidgetViewModel(
                    restoredUsage,
                    persisted,
                    restoredCompanion);
                restoredClaudeWindow = new FloatingWidgetWindow(
                    restoredViewModel,
                    persisted,
                    WidgetPanelKind.Claude,
                    SaveToTemporaryPath)
                {
                    Opacity = 0,
                };
                restoredCodexWindow = new FloatingWidgetWindow(
                    restoredViewModel,
                    persisted,
                    WidgetPanelKind.Codex,
                    SaveToTemporaryPath)
                {
                    Opacity = 0,
                };
                restoredClaudeWindow.ShowClamped(activate: false);
                restoredCodexWindow.ShowClamped(activate: false);
                var restoredClaudeBounds = StabilizeWindow(restoredClaudeWindow);
                var restoredCodexBounds = StabilizeWindow(restoredCodexWindow);
                Assert.True(HaveSameBounds(claudeBounds, restoredClaudeBounds));
                Assert.True(HaveSameBounds(codexBounds, restoredCodexBounds));
            }
            finally
            {
                if (restoredClaudeWindow?.IsLoaded == true)
                {
                    restoredClaudeWindow.CloseForExit();
                }

                if (restoredCodexWindow?.IsLoaded == true)
                {
                    restoredCodexWindow.CloseForExit();
                }

                if (claudeWindow.IsLoaded)
                {
                    claudeWindow.CloseForExit();
                }

                if (codexWindow.IsLoaded)
                {
                    codexWindow.CloseForExit();
                }

                ThemeResourceManager.Shutdown();
                if (Directory.Exists(settingsDirectory))
                {
                    Directory.Delete(settingsDirectory, recursive: true);
                }
            }
        });
    }

    [Fact]
    public void SettingsWindowMovesWithinTheNativeWorkAreaAndKeepsMacResizePolicy()
    {
        RunOnStaThread(() =>
        {
            var historyPath = Path.Combine(
                Path.GetTempPath(),
                $"claudeusage-native-settings-{Guid.NewGuid():N}.json");
            var settings = new AppSettings
            {
                Appearance = AppearanceMode.Light,
                Language = AppLanguage.English,
            };
            var usage = new UsageViewModel(settings);
            var companion = new CompanionViewModel(language: AppLanguage.English);
            var history = new UsageHistoryService(new UsageHistoryStore(historyPath));
            using var viewModel = new SettingsViewModel(
                settings,
                usage,
                history,
                companion,
                persistChanges: false);
            var window = new SettingsWindow(viewModel)
            {
                Opacity = 0,
                ShowActivated = false,
            };

            try
            {
                AssertWindowMovesAndResizesWithinNativeWorkArea(
                    window,
                    System.Windows.ResizeMode.CanMinimize,
                    assertUserResizable: false);
            }
            finally
            {
                if (window.IsLoaded)
                {
                    window.Close();
                }

                ThemeResourceManager.Shutdown();
                if (File.Exists(historyPath))
                {
                    File.Delete(historyPath);
                }
            }
        });
    }

    [Fact]
    public void HistoryWindowMovesAndResizesWithinTheNativeWorkArea()
    {
        RunOnStaThread(() =>
        {
            var historyPath = Path.Combine(
                Path.GetTempPath(),
                $"claudeusage-native-history-{Guid.NewGuid():N}.json");
            var settings = new AppSettings
            {
                Appearance = AppearanceMode.Light,
                Language = AppLanguage.English,
            };
            var history = new UsageHistoryService(new UsageHistoryStore(historyPath));
            using var viewModel = new UsageHistoryDashboardViewModel(history, settings);
            var window = new UsageHistoryDashboardWindow(viewModel)
            {
                Opacity = 0,
                ShowActivated = false,
            };

            try
            {
                AssertWindowMovesAndResizesWithinNativeWorkArea(
                    window,
                    System.Windows.ResizeMode.CanResize,
                    assertUserResizable: true);
            }
            finally
            {
                if (window.IsLoaded)
                {
                    window.Close();
                }

                ThemeResourceManager.Shutdown();
                if (File.Exists(historyPath))
                {
                    File.Delete(historyPath);
                }
            }
        });
    }

    private static void AssertWindowMovesAndResizesWithinNativeWorkArea(
        System.Windows.Window window,
        System.Windows.ResizeMode expectedResizeMode,
        bool assertUserResizable)
    {
        window.Show();
        var handle = new WindowInteropHelper(window).Handle;
        Assert.NotEqual(IntPtr.Zero, handle);
        Assert.True(IsWindow(handle));
        Assert.Equal(expectedResizeMode, window.ResizeMode);

        var initialBounds = StabilizeWindow(window);
        var screen = Forms.Screen.FromHandle(handle);
        AssertInsideWorkArea(
            initialBounds,
            screen.WorkingArea,
            StandardWindowWorkAreaMargin);
        Assert.True(window.MinWidth > 0);
        Assert.True(window.MinHeight > 0);
        Assert.True(window.MaxWidth >= window.MinWidth);
        Assert.True(window.MaxHeight >= window.MinHeight);

        var offscreenLeft = Forms.Screen.AllScreens.Max(
            candidate => candidate.WorkingArea.Right) + 1_000;
        var offscreenTop = Forms.Screen.AllScreens.Max(
            candidate => candidate.WorkingArea.Bottom) + 1_000;
        _ = SendMessage(handle, WmEnterSizeMove, IntPtr.Zero, IntPtr.Zero);
        Assert.True(SetWindowPos(
            handle,
            IntPtr.Zero,
            offscreenLeft,
            offscreenTop,
            0,
            0,
            SwpNoSize | SwpNoZOrder | SwpNoActivate));
        window.UpdateLayout();
        FlushDispatcher(window.Dispatcher);
        Assert.True(GetWindowRect(handle, out var boundsDuringNativeMove));
        Assert.Equal(offscreenLeft, boundsDuringNativeMove.Left);
        Assert.Equal(offscreenTop, boundsDuringNativeMove.Top);
        Assert.DoesNotContain(
            Forms.Screen.AllScreens,
            candidate => Intersects(boundsDuringNativeMove, candidate.WorkingArea));

        _ = SendMessage(handle, WmExitSizeMove, IntPtr.Zero, IntPtr.Zero);
        var boundsAfterNativeMove = StabilizeWindow(window);
        var screenAfterNativeMove = Forms.Screen.FromHandle(handle);
        Assert.False(HaveSameBounds(boundsDuringNativeMove, boundsAfterNativeMove));
        AssertInsideWorkArea(
            boundsAfterNativeMove,
            screenAfterNativeMove.WorkingArea,
            StandardWindowWorkAreaMargin);
        if (!assertUserResizable)
        {
            Assert.Equal(
                initialBounds.Right - initialBounds.Left,
                boundsAfterNativeMove.Right - boundsAfterNativeMove.Left);
            Assert.Equal(
                initialBounds.Bottom - initialBounds.Top,
                boundsAfterNativeMove.Bottom - boundsAfterNativeMove.Top);
            return;
        }

        Assert.True(SetWindowPos(
            handle,
            IntPtr.Zero,
            initialBounds.Left,
            initialBounds.Top,
            1,
            1,
            SwpNoZOrder | SwpNoActivate));
        var minimumBounds = StabilizeWindow(window);
        var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(window);
        Assert.True(
            minimumBounds.Right - minimumBounds.Left
            >= Math.Floor(window.MinWidth * dpi.DpiScaleX) - 2);
        Assert.True(
            minimumBounds.Bottom - minimumBounds.Top
            >= Math.Floor(window.MinHeight * dpi.DpiScaleY) - 2);

        Assert.True(SetWindowPos(
            handle,
            IntPtr.Zero,
            Forms.Screen.AllScreens.Max(candidate => candidate.WorkingArea.Right) + 1_000,
            Forms.Screen.AllScreens.Max(candidate => candidate.WorkingArea.Bottom) + 1_000,
            Math.Max(1, screen.WorkingArea.Width * 2),
            Math.Max(1, screen.WorkingArea.Height * 2),
            SwpNoZOrder | SwpNoActivate));
        Assert.True(GetWindowRect(handle, out var movedAndResizedBounds));
        Assert.DoesNotContain(
            Forms.Screen.AllScreens,
            candidate => Intersects(movedAndResizedBounds, candidate.WorkingArea));
        var maximumBounds = StabilizeWindow(window);
        var finalScreen = Forms.Screen.FromHandle(handle);
        Assert.False(HaveSameBounds(movedAndResizedBounds, maximumBounds));
        AssertInsideWorkArea(
            maximumBounds,
            finalScreen.WorkingArea,
            StandardWindowWorkAreaMargin);
        dpi = System.Windows.Media.VisualTreeHelper.GetDpi(window);
        Assert.True(
            maximumBounds.Right - maximumBounds.Left
            <= Math.Ceiling(window.MaxWidth * dpi.DpiScaleX) + 2);
        Assert.True(
            maximumBounds.Bottom - maximumBounds.Top
            <= Math.Ceiling(window.MaxHeight * dpi.DpiScaleY) + 2);
    }

    private static void AssertInsideWorkArea(
        NativeRect bounds,
        System.Drawing.Rectangle workArea,
        int margin = WidgetWorkAreaMargin)
    {
        Assert.True(
            bounds.Left >= workArea.Left + margin,
            $"Left edge is outside the work area: {Format(bounds)} in {workArea}.");
        Assert.True(
            bounds.Top >= workArea.Top + margin,
            $"Top edge is outside the work area: {Format(bounds)} in {workArea}.");
        Assert.True(
            bounds.Right <= workArea.Right - margin,
            $"Right edge is outside the work area: {Format(bounds)} in {workArea}.");
        Assert.True(
            bounds.Bottom <= workArea.Bottom - margin,
            $"Bottom edge is outside the work area: {Format(bounds)} in {workArea}.");
    }

    private static void AssertMatches(
        NativeRect bounds,
        string monitorDeviceName,
        WidgetWindowPosition position)
    {
        Assert.Equal(bounds.Left, position.Left);
        Assert.Equal(bounds.Top, position.Top);
        Assert.Equal(monitorDeviceName, position.MonitorDeviceName, ignoreCase: true);
    }

    private static string Format(NativeRect bounds) =>
        $"({bounds.Left},{bounds.Top})-({bounds.Right},{bounds.Bottom})";

    private static NativeRect StabilizeWindow(FloatingWidgetWindow window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        Assert.NotEqual(IntPtr.Zero, handle);
        NativeRect? previous = null;
        for (var attempt = 0; attempt < 8; attempt++)
        {
            window.ShowClamped(activate: false);
            window.UpdateLayout();
            FlushDispatcher(window.Dispatcher);
            Assert.True(GetWindowRect(handle, out var current));
            if (previous is { } prior && HaveSameBounds(prior, current))
            {
                return current;
            }

            previous = current;
        }

        throw new InvalidOperationException(
            $"The native widget bounds did not stabilize; last bounds were {Format(previous!.Value)}.");
    }

    private static NativeRect StabilizeWindow(System.Windows.Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        Assert.NotEqual(IntPtr.Zero, handle);
        NativeRect? previous = null;
        for (var attempt = 0; attempt < 8; attempt++)
        {
            window.UpdateLayout();
            FlushDispatcher(window.Dispatcher);
            Assert.True(GetWindowRect(handle, out var current));
            if (previous is { } prior && HaveSameBounds(prior, current))
            {
                return current;
            }

            previous = current;
        }

        throw new InvalidOperationException(
            $"The native window bounds did not stabilize; last bounds were {Format(previous!.Value)}.");
    }

    private static bool HaveSameBounds(NativeRect left, NativeRect right) =>
        left.Left == right.Left
        && left.Top == right.Top
        && left.Right == right.Right
        && left.Bottom == right.Bottom;

    private static bool Intersects(
        NativeRect bounds,
        System.Drawing.Rectangle rectangle) =>
        bounds.Left < rectangle.Right
        && bounds.Right > rectangle.Left
        && bounds.Top < rectangle.Bottom
        && bounds.Bottom > rectangle.Top;

    private static void FlushDispatcher(Dispatcher dispatcher) =>
        dispatcher.Invoke(static () => { }, DispatcherPriority.ApplicationIdle);

    private static void RunOnStaThread(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        })
        {
            IsBackground = true,
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(30)), "The native WPF window test timed out.");

        if (failure is not null)
        {
            ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr window, out NativeRect rectangle);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(
        IntPtr window,
        uint message,
        IntPtr wordParameter,
        IntPtr longParameter);

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
