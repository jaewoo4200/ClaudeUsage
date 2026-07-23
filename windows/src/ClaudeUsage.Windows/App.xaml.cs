using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Interop;
using ClaudeUsage.Core.History;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using ClaudeUsage.Windows.ViewModels;
using ClaudeUsage.Windows.Views;
using WpfMessageBox = System.Windows.MessageBox;

namespace ClaudeUsage.Windows;

public partial class App : System.Windows.Application
{
    private SingleInstanceCoordinator? _singleInstance;
    private int _pendingInstanceActivation;
    private bool _isExiting;
    private bool _shutdownRequested;
    private bool _openingClaudeLogin;
    private bool _isRevertingStartupSetting;
    private bool _visualTestMode;
    private bool _widgetVisualTestMode;
    private bool _runtimeSmokeMode;
    private string? _runtimeSmokeResultPath;
    private WidgetActivationPolicy _pendingWidgetActivationPolicy =
        WidgetActivationPolicy.PreserveForeground;

    internal static WidgetActivationPolicy DefaultWidgetToggleActivationPolicy =>
        WidgetActivationPolicy.PreserveForeground;
    private AppSettings? _settings;
    private HttpClient? _httpClient;
    private IClaudeCookieStore? _cookieStore;
    private UsageCoordinator? _coordinator;
    private UsageHistoryService? _historyService;
    private UsageViewModel? _usageViewModel;
    private CompanionViewModel? _companionViewModel;
    private WidgetViewModel? _widgetViewModel;
    private TrayIconService? _trayIcon;
    private FlyoutWindow? _flyout;
    private SettingsWindow? _settingsWindow;
    private UsageHistoryDashboardWindow? _historyWindow;
    private ClaudeLoginWindow? _claudeLoginWindow;
    private FloatingWidgetWindow? _combinedWidget;
    private FloatingWidgetWindow? _claudeWidget;
    private FloatingWidgetWindow? _codexWidget;
    private string? _visualTestHistoryPath;
    private Task _staleLoginProfileCleanupTask = Task.CompletedTask;
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly StartupRegistrationService _startupRegistration = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var flyoutScreenshotMode = e.Args.Contains(
            "--screenshot",
            StringComparer.OrdinalIgnoreCase);
        var settingsScreenshotMode = e.Args.Contains(
            "--screenshot-settings",
            StringComparer.OrdinalIgnoreCase);
        var historyScreenshotMode = e.Args.Contains(
            "--screenshot-history",
            StringComparer.OrdinalIgnoreCase);
        var screenshotMode = flyoutScreenshotMode
                             || settingsScreenshotMode
                             || historyScreenshotMode;
        _widgetVisualTestMode = e.Args.Contains(
            "--screenshot-widget",
            StringComparer.OrdinalIgnoreCase);
        _runtimeSmokeMode = e.Args.Contains(
            "--runtime-smoke",
            StringComparer.OrdinalIgnoreCase);
        _runtimeSmokeResultPath = ReadArgumentValue(e.Args, "runtime-smoke-result");
        _visualTestMode = screenshotMode || _widgetVisualTestMode || _runtimeSmokeMode;

        _settings = SettingsStore.Load();

        if (!_visualTestMode)
        {
            try
            {
                _startupRegistration.SynchronizePackagedBeforeInstanceHandoff(
                    _settings.StartWithWindows);
            }
            catch (Exception exception) when (
                exception is IOException
                    or UnauthorizedAccessException
                    or SecurityException
                    or InvalidOperationException)
            {
                // A packaged secondary cannot safely show registration errors.
                // Transactional ordering leaves the portable Run registration in
                // place, and a primary process retries through normal startup sync.
            }

            var instanceStart = SingleInstanceCoordinator.Start(
                OnPrimaryInstanceActivationRequested);
            if (!instanceStart.IsPrimary)
            {
                if (!instanceStart.ActivationForwarded)
                {
                    WpfMessageBox.Show(
                        "ClaudeUsage is already running, but its window could not be activated. Please try again.",
                        "ClaudeUsage",
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning);
                }

                Shutdown();
                return;
            }

            _singleInstance = instanceStart.Coordinator;
            _staleLoginProfileCleanupTask = CleanupStaleLoginProfilesAtStartupAsync();
        }

        if (_visualTestMode)
        {
            ApplyVisualTestOptions(e.Args);
        }
        Controls.CompanionControl.ForceMotionForDiagnostics = _widgetVisualTestMode
            && e.Args.Contains("--force-motion", StringComparer.OrdinalIgnoreCase);
        ThemeResourceManager.Initialize(_settings);

        var httpHandler = new HttpClientHandler
        {
            AllowAutoRedirect = false,
            UseCookies = false,
            AutomaticDecompression = DecompressionMethods.All,
        };
        _httpClient = new HttpClient(httpHandler, disposeHandler: true)
        {
            Timeout = TimeSpan.FromSeconds(25),
        };
        _cookieStore = _visualTestMode
            ? new DpapiClaudeCookieStore(Path.Combine(
                Path.GetTempPath(),
                "ClaudeUsage",
                $"visual-test-session-{Environment.ProcessId}-{Guid.NewGuid():N}.dat"))
            : new DpapiClaudeCookieStore();

        var locator = new CodexExecutableLocator(_settings);
        var codexClient = new CodexAppServerClient();
        var claudeService = new ClaudeUsageService(_httpClient, _cookieStore);
        if (_visualTestMode)
        {
            _visualTestHistoryPath = Path.Combine(
                Path.GetTempPath(),
                "ClaudeUsage",
                $"visual-test-history-{Environment.ProcessId}-{Guid.NewGuid():N}.json");
            _historyService = new UsageHistoryService(new UsageHistoryStore(_visualTestHistoryPath));
            _settings.UsageHistoryEnabled = true;
        }
        else
        {
            _historyService = new UsageHistoryService();
        }
        _usageViewModel = new UsageViewModel(_settings);
        _companionViewModel = new CompanionViewModel(
            _settings.SelectedCompanion,
            _settings.CompanionSensitivity,
            _settings.CompanionAnimationMode,
            _settings.ReducedMotion,
            _settings.Language);
        _widgetViewModel = new WidgetViewModel(
            _usageViewModel,
            _settings,
            _companionViewModel);
        _coordinator = new UsageCoordinator(
            locator,
            codexClient,
            claudeService,
            _historyService,
            _usageViewModel,
            _companionViewModel,
            _settings,
            externalRefreshEnabled: !_visualTestMode);
        if (_visualTestMode)
        {
            ApplyVisualTestSamples();
        }

        _flyout = new FlyoutWindow(
            _usageViewModel,
            _widgetViewModel,
            _coordinator,
            _settings);
        _flyout.PersistSettingsChanges = !_visualTestMode;
        if (screenshotMode || _runtimeSmokeMode)
        {
            // Keep normal tray behavior unchanged while making automated visual
            // verification discoverable as a regular top-level window.
            _flyout.ShowInTaskbar = true;
            _flyout.ForceKeepOpenForDiagnostics = true;
        }

        _flyout.ClaudeLoginRequested += OnClaudeLoginRequested;
        _flyout.ClaudeLogoutRequested += OnFlyoutClaudeLogoutRequested;
        _flyout.OpenCodexUsageRequested += (_, _) => OpenCodexUsagePage();
        _flyout.SettingsRequested += OnSettingsRequested;
        _flyout.UsageHistoryRequested += OnUsageHistoryRequested;
        _flyout.ToggleWidgetRequested += OnToggleWidgetRequested;
        _flyout.QuitRequested += (_, _) => ExitApplication();
        ActivatePendingPrimaryInstanceRequest();

        if (!_visualTestMode)
        {
            _trayIcon = new TrayIconService(
                _usageViewModel,
                _flyout,
                _coordinator,
                _settings,
                ToggleWidgetFromTray,
                ToggleStartWithWindowsFromTray,
                OpenSettings,
                OpenClaudeLogin,
                ExitApplication);
        }

        _settings.PropertyChanged += OnSettingsPropertyChanged;
        EnsureWidgetWindows();
        if (_widgetVisualTestMode)
        {
            // Visual verification needs the normally tool-window-only widget to
            // be discoverable without changing the user's persisted visibility.
            ShowVisualTestWidgets();
        }
        else if (settingsScreenshotMode)
        {
            OpenSettings();
        }
        else if (historyScreenshotMode)
        {
            OpenUsageHistory();
        }
        else if (_runtimeSmokeMode)
        {
            ShowVisualTestWidgets(activate: false);
            OpenSettings();
            OpenUsageHistory();
        }
        else if (!_visualTestMode)
        {
            SynchronizeStartupRegistration(showError: false);
            ApplyWidgetVisibility(WidgetActivationPolicy.PreserveForeground);
        }

        // Start the local one-second countdown in every mode. Visual diagnostics
        // construct the coordinator with external refresh disabled, so this
        // advances Flyout/Widget text without network or persistence activity.
        _coordinator.Start();
        if (_visualTestMode)
        {
            _ = MonitorVisualCountdownAsync();
        }

        if (_runtimeSmokeMode)
        {
            _ = RunRuntimeSmokeAsync();
        }

        if (!_widgetVisualTestMode
            && !settingsScreenshotMode
            && !historyScreenshotMode
            && !e.Args.Contains("--background", StringComparer.OrdinalIgnoreCase))
        {
            _flyout.ShowNearNotificationArea();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _isExiting = true;
        _lifetimeCancellation.Cancel();
        _singleInstance?.Dispose();
        _singleInstance = null;
        if (_settings is not null)
        {
            _settings.PropertyChanged -= OnSettingsPropertyChanged;
        }

        _coordinator?.Dispose();
        _trayIcon?.Dispose();
        _claudeLoginWindow?.CancelLoginAndClose();
        _settingsWindow?.Close();
        _historyWindow?.Close();
        _combinedWidget?.CloseForExit();
        _claudeWidget?.CloseForExit();
        _codexWidget?.CloseForExit();
        _flyout?.CloseForExit();
        _widgetViewModel?.Dispose();
        _httpClient?.Dispose();
        ThemeResourceManager.Shutdown();
        DeleteVisualTestHistory();

        base.OnExit(e);
    }

    private void EnsureWidgetWindows()
    {
        if (_widgetViewModel is null || _settings is null)
        {
            return;
        }

        _combinedWidget ??= CreateWidget(WidgetPanelKind.Combined);
        _claudeWidget ??= CreateWidget(WidgetPanelKind.Claude);
        _codexWidget ??= CreateWidget(WidgetPanelKind.Codex);
    }

    private FloatingWidgetWindow CreateWidget(WidgetPanelKind panelKind)
    {
        var window = new FloatingWidgetWindow(_widgetViewModel!, _settings!, panelKind);
        if (_visualTestMode)
        {
            window.PersistPositionChanges = false;
        }

        if (_widgetVisualTestMode)
        {
            window.ShowInTaskbar = true;
            window.ExitApplicationOnHideForDiagnostics = true;
            window.Title = panelKind switch
            {
                WidgetPanelKind.Claude => "ClaudeUsage — Claude Widget",
                WidgetPanelKind.Codex => "ClaudeUsage — Codex Widget",
                _ => "ClaudeUsage Widget",
            };
        }

        window.SettingsRequested += (_, _) => OpenSettings();
        window.HideRequested += (_, _) => HideAllWidgets();
        return window;
    }

    private void ShowVisualTestWidgets(bool activate = true)
    {
        if (_settings?.WidgetLayout == WidgetLayoutMode.Separate)
        {
            HideWidgetWindow(_combinedWidget);
            SetWidgetVisible(_claudeWidget, _settings.SeparateClaudeWidgetEnabled, activate: false);
            SetWidgetVisible(_codexWidget, _settings.SeparateCodexWidgetEnabled, activate: false);
            var activationWindow = _settings.SeparateClaudeWidgetEnabled
                ? _claudeWidget
                : _codexWidget;
            activationWindow?.ShowClamped(activate);
            return;
        }

        HideWidgetWindow(_claudeWidget);
        HideWidgetWindow(_codexWidget);
        _combinedWidget?.ShowClamped(activate);
    }

    private void ApplyWidgetVisibility(WidgetActivationPolicy activationPolicy)
    {
        if (_settings is null)
        {
            return;
        }

        EnsureWidgetWindows();
        if (!_settings.FloatingWidgetVisible)
        {
            HideWidgetWindow(_combinedWidget);
            HideWidgetWindow(_claudeWidget);
            HideWidgetWindow(_codexWidget);
            return;
        }

        if (_settings.WidgetLayout == WidgetLayoutMode.Separate)
        {
            HideWidgetWindow(_combinedWidget);
            SetWidgetVisible(
                _claudeWidget,
                _settings.SeparateClaudeWidgetEnabled,
                activate: false);
            SetWidgetVisible(
                _codexWidget,
                _settings.SeparateCodexWidgetEnabled,
                activate: false);

            var activationTarget = WidgetActivationPlanner.ResolveActivationTarget(
                activationPolicy,
                _settings.WidgetLayout,
                _settings.SeparateClaudeWidgetEnabled,
                _settings.SeparateCodexWidgetEnabled);
            if (activationTarget == WidgetPanelKind.Claude)
            {
                _claudeWidget?.ShowClamped(activate: true);
            }
            else if (activationTarget == WidgetPanelKind.Codex)
            {
                _codexWidget?.ShowClamped(activate: true);
            }

            return;
        }

        HideWidgetWindow(_claudeWidget);
        HideWidgetWindow(_codexWidget);
        _combinedWidget?.ShowClamped(
            activate: WidgetActivationPlanner.ResolveActivationTarget(
                activationPolicy,
                _settings.WidgetLayout,
                _settings.SeparateClaudeWidgetEnabled,
                _settings.SeparateCodexWidgetEnabled) == WidgetPanelKind.Combined);
    }

    private static void SetWidgetVisible(
        FloatingWidgetWindow? window,
        bool visible,
        bool activate)
    {
        if (visible)
        {
            window?.ShowClamped(activate);
        }
        else
        {
            HideWidgetWindow(window);
        }
    }

    private static void HideWidgetWindow(FloatingWidgetWindow? window)
    {
        if (window?.IsVisible == true)
        {
            window.SavePositionAndHide();
        }
    }

    private void ToggleWidgetFromTray() =>
        ToggleWidget(DefaultWidgetToggleActivationPolicy);

    private void ToggleWidget(WidgetActivationPolicy activationPolicy)
    {
        if (_settings is null)
        {
            return;
        }

        var previousPolicy = _pendingWidgetActivationPolicy;
        _pendingWidgetActivationPolicy = !_settings.FloatingWidgetVisible
            ? activationPolicy
            : WidgetActivationPolicy.PreserveForeground;
        try
        {
            _settings.FloatingWidgetVisible = !_settings.FloatingWidgetVisible;
            PersistSettings();
        }
        finally
        {
            _pendingWidgetActivationPolicy = previousPolicy;
        }
    }

    private void HideAllWidgets()
    {
        if (_settings is null)
        {
            return;
        }

        _settings.FloatingWidgetVisible = false;
        PersistSettings();
    }

    private void OpenSettings()
    {
        if (_settings is null)
        {
            return;
        }

        if (_settingsWindow is { IsVisible: true })
        {
            WindowActivationPolicy.RestoreAndActivate(_settingsWindow);
            return;
        }

        var viewModel = new SettingsViewModel(
            _settings,
            _usageViewModel!,
            _historyService!,
            _companionViewModel!,
            persistChanges: !_visualTestMode);
        viewModel.SettingsChanged += OnPersistedSettingChanged;
        var window = new SettingsWindow(viewModel);
        window.ClaudeLoginRequested += (_, _) => OpenClaudeLogin();
        window.ClaudeLogoutRequested += (_, _) => _ = PerformClaudeLogoutAsync();
        window.ClearHistoryRequested += (_, _) => _ = ClearHistoryAsync(window);
        window.OpenHistoryRequested += (_, _) => OpenUsageHistory();
        window.OpenCodexUsageRequested += (_, _) => OpenCodexUsagePage();
        window.Closed += (_, _) =>
        {
            viewModel.SettingsChanged -= OnPersistedSettingChanged;
            viewModel.Dispose();
            if (ReferenceEquals(_settingsWindow, window))
            {
                _settingsWindow = null;
            }
        };
        _settingsWindow = window;
        window.Show();
        window.Activate();
    }

    private void ToggleStartWithWindowsFromTray()
    {
        if (_settings is null)
        {
            return;
        }

        var previousValue = _settings.StartWithWindows;
        _settings.StartWithWindows = !previousValue;
        if (!SettingsStore.Save(_settings))
        {
            _settings.StartWithWindows = previousValue;
            ShowMessage(
                S("Settings.PersistenceErrorTitle", "Couldn't save settings."),
                S(
                    "Settings.PersistenceError",
                    "The startup setting was not changed because the settings file could not be saved."),
                MessageBoxImage.Warning);
            return;
        }

        SynchronizeStartupRegistration(showError: true);
    }

    private void OpenUsageHistory()
    {
        if (_historyService is null || _settings is null)
        {
            return;
        }

        if (_historyWindow is { IsVisible: true })
        {
            _historyWindow.ViewModel.Refresh();
            WindowActivationPolicy.RestoreAndActivate(_historyWindow);
            return;
        }

        var viewModel = new UsageHistoryDashboardViewModel(_historyService, _settings);
        var window = new UsageHistoryDashboardWindow(viewModel);
        window.ClearHistoryRequested += (_, _) => _ = ClearHistoryAsync(window);
        window.Closed += (_, _) =>
        {
            viewModel.Dispose();
            if (ReferenceEquals(_historyWindow, window))
            {
                _historyWindow = null;
            }
        };
        _historyWindow = window;
        window.Show();
        window.Activate();
    }

    private void OpenCodexUsagePage()
    {
        if (_visualTestMode)
        {
            return;
        }

        try
        {
            _ = Process.Start(new ProcessStartInfo(
                "https://chatgpt.com/codex/cloud/settings/analytics#usage")
            {
                UseShellExecute = true,
            });
        }
        catch (Exception exception) when (
            exception is InvalidOperationException
                or System.ComponentModel.Win32Exception)
        {
            ShowMessage(
                S("App.OpenUsageFailedTitle", "Couldn't open the Codex usage page."),
                S("App.OpenUsageFailedDetail", "Check that Windows has a default web browser."),
                MessageBoxImage.Warning);
        }
    }

    private async void OpenClaudeLogin()
    {
        if (_visualTestMode || _isExiting)
        {
            return;
        }

        if (_cookieStore is null || _settings is null)
        {
            return;
        }

        if (_claudeLoginWindow is { IsVisible: true })
        {
            WindowActivationPolicy.RestoreAndActivate(_claudeLoginWindow);
            return;
        }

        if (_openingClaudeLogin)
        {
            return;
        }

        _openingClaudeLogin = true;
        try
        {
            await _staleLoginProfileCleanupTask;
            if (_isExiting)
            {
                return;
            }

            if (_claudeLoginWindow is { IsVisible: true } existingWindow)
            {
                WindowActivationPolicy.RestoreAndActivate(existingWindow);
                return;
            }

            if (!_settings.ClaudeCloudEnabled)
            {
                _settings.ClaudeCloudEnabled = true;
                PersistSettings();
            }

            var window = new ClaudeLoginWindow(_cookieStore);
            window.LoginCompleted += (_, _) =>
            {
                if (_coordinator is not null)
                {
                    _ = _coordinator.RefreshAsync();
                }
            };
            window.Closed += (_, _) =>
            {
                if (ReferenceEquals(_claudeLoginWindow, window))
                {
                    _claudeLoginWindow = null;
                }
            };
            _claudeLoginWindow = window;
            window.Show();
            window.Activate();
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested)
        {
            // Normal application shutdown while startup cleanup was pending.
        }
        finally
        {
            _openingClaudeLogin = false;
        }
    }

    private async Task PerformClaudeLogoutAsync()
    {
        if (_coordinator is null)
        {
            return;
        }

        Exception? browserCleanupError = null;
        if (_claudeLoginWindow is { } loginWindow)
        {
            try
            {
                await loginWindow.DisconnectAndCloseAsync();
            }
            catch (Exception exception) when (
                exception is IOException
                    or UnauthorizedAccessException
                    or CryptographicException
                    or InvalidOperationException
                    or COMException)
            {
                browserCleanupError = exception;
            }
        }

        try
        {
            // Always clear the authoritative DPAPI store, even if temporary
            // WebView2 profile cleanup failed above.
            await _coordinator.LogoutClaudeAsync();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            ShowMessage(
                S("App.ClaudeSessionDeleteTitle", "Couldn't delete the Claude session file."),
                S("App.ClaudeSessionDeleteDetail", "Check file permissions for the current Windows account."),
                MessageBoxImage.Error);
            return;
        }

        if (browserCleanupError is not null)
        {
            ShowMessage(
                S("App.ClaudeDisconnectedTitle", "Claude has been disconnected."),
                S(
                    "App.ClaudeBrowserCleanupDetail",
                    "Temporary sign-in browser data couldn't be completely removed. Restarting the app will retry cleanup of the remaining temporary profile."),
                MessageBoxImage.Warning);
        }
    }

    private async Task ClearHistoryAsync(Window owner)
    {
        if (_coordinator is null)
        {
            return;
        }

        var lifetimeToken = _lifetimeCancellation.Token;
        try
        {
            await _coordinator.ClearHistoryAsync(lifetimeToken);
            if (!CanShowOwnedMessage(owner))
            {
                return;
            }

            _historyWindow?.ViewModel.Refresh();
            WpfMessageBox.Show(
                owner,
                S("App.HistoryClearedDetail", "Cleared the local usage history created by ClaudeUsage."),
                S("App.HistoryClearedTitle", "History cleared"),
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            if (!CanShowOwnedMessage(owner))
            {
                return;
            }

            WpfMessageBox.Show(
                owner,
                S("App.HistoryClearFailedDetail", "Couldn't clear local usage history. Check file permissions."),
                S("App.HistoryClearFailedTitle", "Couldn't clear history"),
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        catch (OperationCanceledException) when (lifetimeToken.IsCancellationRequested)
        {
            // Normal application shutdown; never show an orphaned owner dialog.
        }
    }

    private bool CanShowOwnedMessage(Window owner) =>
        !_isExiting
        && owner.IsLoaded
        && owner.IsVisible
        && !owner.Dispatcher.HasShutdownStarted
        && !owner.Dispatcher.HasShutdownFinished;

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_isExiting)
        {
            return;
        }

        if (e.PropertyName == nameof(AppSettings.Language) && _settings is not null)
        {
            if (_companionViewModel is not null)
            {
                _companionViewModel.Language = _settings.Language;
            }
        }

        if (e.PropertyName is nameof(AppSettings.FloatingWidgetVisible)
            or nameof(AppSettings.WidgetLayout)
            or nameof(AppSettings.SeparateClaudeWidgetEnabled)
            or nameof(AppSettings.SeparateCodexWidgetEnabled))
        {
            if (_widgetVisualTestMode
                && e.PropertyName is (nameof(AppSettings.WidgetLayout)
                    or nameof(AppSettings.SeparateClaudeWidgetEnabled)
                    or nameof(AppSettings.SeparateCodexWidgetEnabled)))
            {
                ShowVisualTestWidgets(activate: false);
            }
            else if (!_visualTestMode)
            {
                ApplyWidgetVisibility(_pendingWidgetActivationPolicy);
            }
        }
    }

    private void OnPersistedSettingChanged(object? sender, SettingChangedEventArgs e)
    {
        if (!_visualTestMode
            && e.PropertyName == nameof(AppSettings.StartWithWindows)
            && !_isRevertingStartupSetting)
        {
            SynchronizeStartupRegistration(showError: true);
        }
    }

    private void SynchronizeStartupRegistration(bool showError)
    {
        if (_settings is null)
        {
            return;
        }

        bool? previouslyEnabled = null;
        try
        {
            previouslyEnabled = _startupRegistration.IsEnabled();
            _startupRegistration.SetEnabled(_settings.StartWithWindows);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or SecurityException or InvalidOperationException)
        {
            if (previouslyEnabled is { } rollbackValue)
            {
                _isRevertingStartupSetting = true;
                try
                {
                    _settings.StartWithWindows = rollbackValue;
                    SettingsStore.Save(_settings);
                }
                finally
                {
                    _isRevertingStartupSetting = false;
                }
            }

            if (showError)
            {
                ShowMessage(
                    S("App.StartupRegistrationFailedTitle", "Couldn't change Windows startup registration."),
                    S("App.StartupRegistrationFailedDetail", "Check registry permissions for the current user."),
                    MessageBoxImage.Warning);
            }
        }
    }

    private void ApplyVisualTestSamples()
    {
        if (_usageViewModel is null || _companionViewModel is null)
        {
            return;
        }

        var now = DateTimeOffset.Now;
        var claudeSnapshot = new ClaudeAccountSnapshot(
            new ClaudeOrganization(
                "visual-test",
                "Visual QA",
                ["claude_max"],
                "max_20x"),
            new ClaudeUsageData(
                fiveHour: new ClaudeUsageWindow(37, now.AddHours(1)),
                sevenDay: new ClaudeUsageWindow(18, now.AddDays(3).AddHours(11).AddMinutes(19)),
                sevenDayFable: new ClaudeUsageWindow(24, now.AddDays(3).AddHours(11).AddMinutes(19))));
        _usageViewModel.ApplyClaudeSnapshot(claudeSnapshot, now);

        var today = DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var codexUsage = new OpenAIUsageData(
            planType: "pro",
            rateLimit: new OpenAIRateLimit(
                new OpenAIUsageWindow(0, now.AddHours(5), null, 5 * 60 * 60),
                new OpenAIUsageWindow(3, now.AddDays(6).AddHours(22).AddMinutes(39), null, 7 * 24 * 60 * 60)),
            codeReviewRateLimit: null,
            additionalRateLimits: [],
            tokenActivity: new OpenAITokenActivity(
                new OpenAITokenUsageSummary(248_000, 42_000, 7_200, 4, 12),
                [new OpenAITokenDailyBucket(today, 12_400)]),
            rateLimitResetCredits: new OpenAIRateLimitResetCredits(3, []));
        _usageViewModel.ApplySnapshot(codexUsage, now);

        for (var index = 0; index < 8; index++)
        {
            var sample = new UsageHistorySnapshot(
                claudeFiveHour: 20 + index * 4,
                claudeWeekly: 12 + index,
                openAIFiveHour: 10 + index * 3,
                openAIWeekly: 7 + index,
                claudeModelCounters:
                [
                    new UsageHistoryCounter(
                        "seven_day_fable",
                        "Claude Fable",
                        24 + index * 3),
                ]);
            _historyService?.Store.Record(
                sample,
                now.AddMinutes(-56 + index * 8),
                force: true);
        }

        _companionViewModel.ApplyUsage(
            _usageViewModel.CreateHistorySnapshot(),
            new UsageTrend([24, 28, 32, 36, 40, 44, 48], 24, null, null, false),
            historyEnabled: true,
            now);
    }

    private void ApplyVisualTestOptions(IReadOnlyList<string> arguments)
    {
        if (_settings is null)
        {
            return;
        }

        _settings.Theme = ReadVisualEnum(arguments, "theme", _settings.Theme);
        _settings.Appearance = ReadVisualEnum(arguments, "appearance", _settings.Appearance);
        _settings.Language = ReadVisualEnum(arguments, "language", _settings.Language);
        _settings.WidgetLayout = ReadVisualEnum(arguments, "layout", _settings.WidgetLayout);
        _settings.SelectedCompanion = ReadVisualEnum(
            arguments,
            "companion",
            _settings.SelectedCompanion);
    }

    private async Task MonitorVisualCountdownAsync()
    {
        var counter = _usageViewModel?.ClaudeCounters
            .FirstOrDefault(item => !item.IsWeekly)
            ?? _usageViewModel?.Counters.FirstOrDefault(item => !item.IsWeekly);
        var before = counter?.ResetText;
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(2.2), _lifetimeCancellation.Token);
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested)
        {
            return;
        }

        if (_coordinator is null || counter is null)
        {
            return;
        }

        var failure = _coordinator.CountdownCompletion.Exception?.GetBaseException();
        var diagnostic = failure is not null
            ? $"countdown fault: {failure.GetType().Name}: {failure.Message}"
            : string.Equals(before, counter.ResetText, StringComparison.Ordinal)
                ? "countdown stalled"
                : null;
        if (diagnostic is not null && _combinedWidget is { IsVisible: true })
        {
            _combinedWidget.Title = $"ClaudeUsage Widget [{diagnostic}]";
        }
    }

    private async Task RunRuntimeSmokeAsync()
    {
        var counter = _usageViewModel?.ClaudeCounters
            .FirstOrDefault(item => !item.IsWeekly)
            ?? _usageViewModel?.Counters.FirstOrDefault(item => !item.IsWeekly);
        var initialResetText = counter?.ResetText;
        try
        {
            await Dispatcher.InvokeAsync(
                static () => { },
                System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            await Task.Delay(TimeSpan.FromSeconds(2.4), _lifetimeCancellation.Token);
            await Dispatcher.InvokeAsync(
                static () => { },
                System.Windows.Threading.DispatcherPriority.ApplicationIdle);

            var windows = new (string Name, Window? Window)[]
            {
                ("flyout", _flyout),
                ("settings", _settingsWindow),
                ("history", _historyWindow),
                ("widget", ResolveVisibleSmokeWidget()),
            };
            var invalidWindows = windows
                .Where(item => item.Window is null
                               || !item.Window.IsLoaded
                               || !item.Window.IsVisible
                               || item.Window.ActualWidth <= 0
                               || item.Window.ActualHeight <= 0
                               || new WindowInteropHelper(item.Window).Handle == IntPtr.Zero)
                .Select(item => item.Name)
                .ToArray();
            if (invalidWindows.Length > 0)
            {
                throw new InvalidOperationException(
                    $"Top-level WPF windows did not initialize: {string.Join(", ", invalidWindows)}.");
            }

            var countdownFailure = _coordinator?.CountdownCompletion.Exception?.GetBaseException();
            if (countdownFailure is not null)
            {
                throw new InvalidOperationException("The local countdown faulted.", countdownFailure);
            }

            if (counter is null
                || string.Equals(initialResetText, counter.ResetText, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("The local one-second countdown did not advance.");
            }

            WriteRuntimeSmokeResult("PASS: flyout, settings, history, widget, and countdown initialized.");
            Shutdown(0);
        }
        catch (Exception exception)
        {
            WriteRuntimeSmokeResult(
                $"FAIL: {exception.GetType().Name}: {exception.GetBaseException().Message}");
            Shutdown(1);
        }
    }

    private FloatingWidgetWindow? ResolveVisibleSmokeWidget() =>
        _combinedWidget is { IsVisible: true }
            ? _combinedWidget
            : _claudeWidget is { IsVisible: true }
                ? _claudeWidget
                : _codexWidget is { IsVisible: true }
                    ? _codexWidget
                    : null;

    private void WriteRuntimeSmokeResult(string result)
    {
        if (string.IsNullOrWhiteSpace(_runtimeSmokeResultPath))
        {
            return;
        }

        try
        {
            var fullPath = Path.GetFullPath(_runtimeSmokeResultPath);
            var directory = Path.GetDirectoryName(fullPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(fullPath, result);
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or NotSupportedException
                or SecurityException)
        {
            // Exit status remains authoritative when a diagnostic path is unwritable.
        }
    }

    private static string? ReadArgumentValue(
        IEnumerable<string> arguments,
        string optionName)
    {
        var prefix = $"--{optionName}=";
        return arguments
            .FirstOrDefault(argument => argument.StartsWith(
                prefix,
                StringComparison.OrdinalIgnoreCase))?[prefix.Length..];
    }

    private static TEnum ReadVisualEnum<TEnum>(
        IEnumerable<string> arguments,
        string optionName,
        TEnum fallback)
        where TEnum : struct, Enum
    {
        var prefix = $"--{optionName}=";
        var value = arguments
            .FirstOrDefault(argument => argument.StartsWith(
                prefix,
                StringComparison.OrdinalIgnoreCase))?[prefix.Length..];
        return Enum.TryParse<TEnum>(value, ignoreCase: true, out var parsed)
            ? parsed
            : fallback;
    }

    private void PersistSettings()
    {
        if (!_visualTestMode && _settings is not null)
        {
            SettingsStore.Save(_settings);
        }
    }

    private void DeleteVisualTestHistory()
    {
        if (_visualTestHistoryPath is null)
        {
            return;
        }

        try
        {
            File.Delete(_visualTestHistoryPath);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or SecurityException)
        {
            // Diagnostics must never turn cleanup trouble into a shutdown failure.
        }
    }

    private void OnClaudeLoginRequested(object? sender, EventArgs e) => OpenClaudeLogin();

    private void OnFlyoutClaudeLogoutRequested(object? sender, EventArgs e)
    {
        var result = WpfMessageBox.Show(
            _flyout,
            S(
                "Settings.ClaudeLogoutConfirmMessage",
                "Only the Claude session protected for this Windows account is deleted."),
            S("Settings.ClaudeLogoutConfirmTitle", "Disconnect Claude?"),
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (result == MessageBoxResult.Yes)
        {
            _ = PerformClaudeLogoutAsync();
        }
    }

    private void OnSettingsRequested(object? sender, EventArgs e) => OpenSettings();

    private void OnUsageHistoryRequested(object? sender, EventArgs e) => OpenUsageHistory();

    private void OnToggleWidgetRequested(object? sender, EventArgs e) =>
        ToggleWidget(DefaultWidgetToggleActivationPolicy);

    private bool OnPrimaryInstanceActivationRequested()
    {
        if (_isExiting)
        {
            return false;
        }

        if (Dispatcher.HasShutdownStarted || Dispatcher.HasShutdownFinished)
        {
            return false;
        }

        if (Dispatcher.CheckAccess())
        {
            return TryActivatePrimaryInstanceRequest();
        }

        try
        {
            // The pipe ACK is sent only after the UI thread accepts the request.
            // This prevents a second process from exiting successfully while the
            // primary process is already inside its shutdown path.
            return Dispatcher.Invoke(TryActivatePrimaryInstanceRequest);
        }
        catch (Exception exception) when (
            exception is InvalidOperationException or OperationCanceledException)
        {
            return false;
        }
    }

    private bool TryActivatePrimaryInstanceRequest()
    {
        if (_isExiting || Dispatcher.HasShutdownStarted || Dispatcher.HasShutdownFinished)
        {
            return false;
        }

        if (_flyout is null)
        {
            Interlocked.Exchange(ref _pendingInstanceActivation, 1);
            return true;
        }

        Interlocked.Exchange(ref _pendingInstanceActivation, 0);
        _flyout.ShowNearNotificationArea();
        return true;
    }

    private void ActivatePendingPrimaryInstanceRequest()
    {
        if (_isExiting || _flyout is null)
        {
            return;
        }

        if (Interlocked.Exchange(ref _pendingInstanceActivation, 0) != 0)
        {
            _flyout.ShowNearNotificationArea();
        }
    }

    private static void ShowMessage(string title, string detail, MessageBoxImage image) =>
        WpfMessageBox.Show(detail, title, MessageBoxButton.OK, image);

    private static string S(string key, string fallback) =>
        ThemeResourceManager.GetString(key, fallback);

    private async void ExitApplication()
    {
        if (_shutdownRequested)
        {
            return;
        }

        _shutdownRequested = true;
        _isExiting = true;
        try
        {
            await _staleLoginProfileCleanupTask;
            if (_claudeLoginWindow is { } loginWindow)
            {
                await loginWindow.CancelLoginAndCloseAsync();
            }
        }
        catch (Exception)
        {
            // Shutdown must continue. Any temporary profile left behind is
            // retried by the next normal application startup.
        }
        finally
        {
            Shutdown();
        }
    }

    private async Task CleanupStaleLoginProfilesAtStartupAsync()
    {
        try
        {
            await ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(
                _lifetimeCancellation.Token);
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested)
        {
            // Normal application shutdown.
        }
    }
}
