using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Threading;
using ClaudeUsage.Windows.Resources.Themes;
using ClaudeUsage.Windows.Services;
using Microsoft.Web.WebView2.Core;

namespace ClaudeUsage.Windows.Views;

public sealed class ClaudeLoginCompletedEventArgs(DateTimeOffset completedAt) : EventArgs
{
    public DateTimeOffset CompletedAt { get; } = completedAt;
}

public partial class ClaudeLoginWindow : Window
{
    private static readonly Uri LoginUri = new("https://claude.ai/login");

    private readonly IClaudeCookieStore _cookieStore;
    private readonly DispatcherTimer _pollTimer;
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly SemaphoreSlim _captureGate = new(1, 1);
    private readonly string _profilePath;
    private FileStream? _profileLease;

    private bool _initialized;
    private bool _captureInProgress;
    private bool _completed;
    private bool _allowClose;
    private bool _captureDisabled;
    private Task? _initializationTask;
    private Task? _cleanupTask;
    private string _statusResourceKey = "ClaudeLogin.Status.Preparing";
    private string _statusFallback = "Preparing a secure sign-in window…";
    private object[] _statusArguments = [];

    public ClaudeLoginWindow()
        : this(new DpapiClaudeCookieStore())
    {
    }

    public ClaudeLoginWindow(IClaudeCookieStore cookieStore)
    {
        _cookieStore = cookieStore ?? throw new ArgumentNullException(nameof(cookieStore));
        _profilePath = Path.Combine(
            ClaudeLoginProfileCleanup.ProfileRoot,
            $"login-{Guid.NewGuid():N}");

        InitializeComponent();

        _pollTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(1_500),
        };
        _pollTimer.Tick += PollTimer_Tick;
        Loaded += ClaudeLoginWindow_Loaded;
        ThemeResourceManager.ResourcesChanged += OnResourcesChanged;
    }

    public event EventHandler<ClaudeLoginCompletedEventArgs>? LoginCompleted;

    public bool LoginSucceeded => _completed;

    internal static ProcessStartInfo CreateExternalBrowserStartInfo() => new()
    {
        FileName = LoginUri.AbsoluteUri,
        UseShellExecute = true,
    };

    public async Task ClearLoginDataAsync(CancellationToken cancellationToken = default)
    {
        await _cookieStore.ClearAsync(cancellationToken);
        if (LoginWebView.CoreWebView2 is { } core)
        {
            core.CookieManager.DeleteAllCookies();
            await core.Profile.ClearBrowsingDataAsync();
        }
    }

    public async Task DisconnectAndCloseAsync()
    {
        _captureDisabled = true;
        _pollTimer.Stop();
        await DrainCaptureAsync();
        try
        {
            await ClearLoginDataAsync(CancellationToken.None);
        }
        finally
        {
            _allowClose = true;
            Close();
        }
    }

    public void CancelLoginAndClose()
    {
        _captureDisabled = true;
        _pollTimer.Stop();
        _allowClose = true;
        Close();
    }

    public async Task CancelLoginAndCloseAsync()
    {
        _captureDisabled = true;
        _pollTimer.Stop();
        await DrainCaptureAsync();
        _lifetimeCancellation.Cancel();
        if (_initializationTask is not null)
        {
            await _initializationTask;
        }

        await CleanupBrowserAsync();
        _allowClose = true;
        if (IsVisible)
        {
            Close();
        }
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        _captureDisabled = true;
        _pollTimer.Stop();
        if (!_allowClose && _initialized)
        {
            e.Cancel = true;
            if (_cleanupTask is null)
            {
                _ = CloseAfterCleanupAsync();
            }
        }

        base.OnClosing(e);
    }

    protected override async void OnClosed(EventArgs e)
    {
        base.OnClosed(e);
        ThemeResourceManager.ResourcesChanged -= OnResourcesChanged;
        _lifetimeCancellation.Cancel();
        _pollTimer.Stop();
        if (_initializationTask is not null)
        {
            await _initializationTask;
        }
        await CleanupBrowserAsync();
        _captureGate.Dispose();
        _lifetimeCancellation.Dispose();
    }

    private async void ClaudeLoginWindow_Loaded(object sender, RoutedEventArgs e)
    {
        Loaded -= ClaudeLoginWindow_Loaded;
        _initializationTask = InitializeBrowserAsync();
        await _initializationTask;
    }

    private async Task InitializeBrowserAsync()
    {
        try
        {
            await ClaudeLoginProfileCleanup.CleanupStaleProfilesAsync(
                _lifetimeCancellation.Token);
            _profileLease = ClaudeLoginProfileCleanup.AcquireProfileLease(_profilePath);

            var environment = await CoreWebView2Environment.CreateAsync(
                browserExecutableFolder: null,
                userDataFolder: _profilePath);
            _lifetimeCancellation.Token.ThrowIfCancellationRequested();
            await LoginWebView.EnsureCoreWebView2Async(environment);
            _lifetimeCancellation.Token.ThrowIfCancellationRequested();

            var core = LoginWebView.CoreWebView2;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.DownloadStarting += Core_DownloadStarting;
            core.LaunchingExternalUriScheme += Core_LaunchingExternalUriScheme;
            core.NewWindowRequested += Core_NewWindowRequested;
            core.NavigationStarting += Core_NavigationStarting;
            core.PermissionRequested += Core_PermissionRequested;
            LoginWebView.NavigationCompleted += LoginWebView_NavigationCompleted;

            _initialized = true;
            _pollTimer.Start();
            SetStatus(
                "ClaudeLogin.Status.LoadingLogin",
                "Loading the Claude sign-in page…");
            core.Navigate(LoginUri.AbsoluteUri);
        }
        catch (OperationCanceledException)
        {
            // The window was closed while WebView2 was starting.
        }
        catch (WebView2RuntimeNotFoundException)
        {
            SetStatus(
                "ClaudeLogin.Status.RuntimeMissing",
                "Install Microsoft Edge WebView2 Runtime, then try again.");
        }
        catch (Exception exception) when (
            exception is InvalidOperationException
                or IOException
                or UnauthorizedAccessException
                or COMException)
        {
            SetStatus(
                "ClaudeLogin.Status.StartFailed",
                "Couldn't start the secure sign-in window. Close it and try again.");
        }
    }

    private async void PollTimer_Tick(object? sender, EventArgs e)
    {
        await TryCaptureCookiesAsync();
    }

    private async void LoginWebView_NavigationCompleted(
        object? sender,
        CoreWebView2NavigationCompletedEventArgs e)
    {
        if (!e.IsSuccess)
        {
            SetStatus(
                "ClaudeLogin.Status.PageFailed",
                "Couldn't load the page. Select Reload to try again.");
            return;
        }

        var host = LoginWebView.Source?.Host;
        if (string.IsNullOrEmpty(host))
        {
            SetStatus(
                "ClaudeLogin.Status.Waiting",
                "Waiting for sign-in to finish…");
        }
        else
        {
            SetStatus(
                "ClaudeLogin.Status.WaitingAt",
                "Waiting for sign-in to finish at {0}…",
                host);
        }
        await TryCaptureCookiesAsync();
    }

    private void Core_NavigationStarting(
        object? sender,
        CoreWebView2NavigationStartingEventArgs e)
    {
        if (!ClaudeLoginSecurityPolicy.IsAllowedNavigation(e.Uri))
        {
            e.Cancel = true;
            SetStatus(
                "ClaudeLogin.Status.ExternalBlocked",
                "Blocked navigation to an unsafe external page.");
        }
    }

    private void Core_NewWindowRequested(
        object? sender,
        CoreWebView2NewWindowRequestedEventArgs e)
    {
        e.Handled = true;
        if (ClaudeLoginSecurityPolicy.IsAllowedNavigation(e.Uri))
        {
            try
            {
                LoginWebView.CoreWebView2.Navigate(e.Uri);
            }
            catch (Exception exception) when (exception is InvalidOperationException or COMException)
            {
                SetStatus(
                    "ClaudeLogin.Status.PopupFailed",
                    "Couldn't open the pop-up page. Try again.");
            }
        }
        else
        {
            SetStatus(
                "ClaudeLogin.Status.PopupBlocked",
                "Blocked an unsafe pop-up navigation.");
        }
    }

    private void Core_DownloadStarting(
        object? sender,
        CoreWebView2DownloadStartingEventArgs e)
    {
        e.Cancel = true;
        e.Handled = true;
        SetStatus(
            "ClaudeLogin.Status.DownloadBlocked",
            "Downloads are disabled in the secure sign-in window.");
    }

    private void Core_LaunchingExternalUriScheme(
        object? sender,
        CoreWebView2LaunchingExternalUriSchemeEventArgs e)
    {
        e.Cancel = true;
        SetStatus(
            "ClaudeLogin.Status.ExternalBlocked",
            "Blocked navigation to an unsafe external page.");
    }

    private static void Core_PermissionRequested(
        object? sender,
        CoreWebView2PermissionRequestedEventArgs e)
    {
        e.State = CoreWebView2PermissionState.Deny;
        e.SavesInProfile = false;
        e.Handled = true;
    }

    private async Task TryCaptureCookiesAsync()
    {
        if (_captureDisabled
            || !_initialized
            || _captureInProgress
            || _completed
            || LoginWebView.CoreWebView2 is null)
        {
            return;
        }

        try
        {
            await _captureGate.WaitAsync(_lifetimeCancellation.Token);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        var shouldCloseAfterCapture = false;
        try
        {
            if (_captureDisabled
                || !_initialized
                || _captureInProgress
                || _completed
                || LoginWebView.CoreWebView2 is null)
            {
                return;
            }

            _captureInProgress = true;
            var cookies = await LoginWebView.CoreWebView2.CookieManager
                .GetCookiesAsync("https://claude.ai");
            var cookieHeader = ClaudeLoginSecurityPolicy.BuildSessionCookieHeader(
                cookies.Select(cookie => new ClaudeLoginCookieCandidate(
                    cookie.Name,
                    cookie.Value,
                    cookie.Domain,
                    cookie.Path)));
            if (cookieHeader is null)
            {
                return;
            }

            if (_captureDisabled)
            {
                return;
            }

            await _cookieStore.SaveAsync(cookieHeader, _lifetimeCancellation.Token);

            _completed = true;
            _pollTimer.Stop();
            SetStatus(
                "ClaudeLogin.Status.Completed",
                "Claude sign-in is complete.");
            LoginCompleted?.Invoke(
                this,
                new ClaudeLoginCompletedEventArgs(DateTimeOffset.Now));
            shouldCloseAfterCapture = true;
        }
        catch (OperationCanceledException)
        {
            // The window is closing.
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or CryptographicException
                or InvalidOperationException
                or COMException
                or ArgumentException)
        {
            SetStatus(
                "ClaudeLogin.Status.SaveFailed",
                "Couldn't save the sign-in data. Try again.");
        }
        finally
        {
            _captureInProgress = false;
            _captureGate.Release();
        }

        if (shouldCloseAfterCapture)
        {
            await CloseAfterCleanupAsync();
        }
    }

    private async void ReloadButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (LoginWebView.CoreWebView2 is null)
            {
                return;
            }

            SetStatus(
                "ClaudeLogin.Status.Reloading",
                "Reloading the page…");
            LoginWebView.Reload();
            await TryCaptureCookiesAsync();
        }
        catch (Exception exception) when (exception is InvalidOperationException or COMException)
        {
            SetStatus(
                "ClaudeLogin.Status.ReloadFailed",
                "Couldn't reload the page. Close the window and try again.");
        }
    }

    private void OpenInDefaultBrowserButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (Process.Start(CreateExternalBrowserStartInfo()) is null)
            {
                throw new InvalidOperationException("The default browser process was not created.");
            }

            SetStatus(
                "ClaudeLogin.Status.OpenedInBrowser",
                "Opened Claude in your default browser. Complete the connection in this window.");
        }
        catch (Exception exception) when (
            exception is Win32Exception or InvalidOperationException or NotSupportedException)
        {
            SetStatus(
                "ClaudeLogin.Status.BrowserOpenFailed",
                "Couldn't open Claude in your default browser.");
        }
    }

    private async void ClearLoginDataButton_Click(object sender, RoutedEventArgs e)
    {
        var clearSucceeded = false;
        _captureDisabled = true;
        _pollTimer.Stop();
        try
        {
            await DrainCaptureAsync();
            await ClearLoginDataAsync(_lifetimeCancellation.Token);
            clearSucceeded = true;
            SetStatus(
                "ClaudeLogin.Status.DataCleared",
                "Sign-in data cleared. Sign in again.");
            try
            {
                LoginWebView.CoreWebView2?.Navigate(LoginUri.AbsoluteUri);
            }
            catch (Exception exception) when (exception is InvalidOperationException or COMException)
            {
                // The credentials are already cleared. Polling can safely resume
                // even if the current browser instance could not navigate.
            }
        }
        catch (OperationCanceledException)
        {
            // The window is closing.
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or CryptographicException
                or InvalidOperationException
                or COMException)
        {
            SetStatus(
                "ClaudeLogin.Status.ClearFailed",
                "Couldn't completely clear sign-in data. Try again.");
        }
        finally
        {
            if (clearSucceeded
                && !_completed
                && IsVisible
                && !_lifetimeCancellation.IsCancellationRequested)
            {
                _captureDisabled = false;
                _pollTimer.Start();
            }
        }
    }

    private void SetStatus(string resourceKey, string fallback, params object[] arguments)
    {
        _statusResourceKey = resourceKey;
        _statusFallback = fallback;
        _statusArguments = arguments;
        ApplyStatusText();
    }

    private void OnResourcesChanged(object? sender, EventArgs e)
    {
        if (!Dispatcher.CheckAccess())
        {
            _ = Dispatcher.BeginInvoke(ApplyStatusText);
            return;
        }

        ApplyStatusText();
    }

    private void ApplyStatusText()
    {
        var format = ThemeResourceManager.GetString(_statusResourceKey, _statusFallback);
        StatusText.Text = _statusArguments.Length == 0
            ? format
            : string.Format(CultureInfo.CurrentCulture, format, _statusArguments);
    }

    private async Task CloseAfterCleanupAsync()
    {
        _captureDisabled = true;
        _pollTimer.Stop();
        await DrainCaptureAsync();
        await CleanupBrowserAsync();
        if (!IsVisible)
        {
            return;
        }

        _allowClose = true;
        Close();
    }

    private async Task DrainCaptureAsync()
    {
        await _captureGate.WaitAsync(CancellationToken.None);
        _captureGate.Release();
    }

    private Task CleanupBrowserAsync() => _cleanupTask ??= CleanupBrowserCoreAsync();

    private async Task CleanupBrowserCoreAsync()
    {
        _pollTimer.Stop();

        if (LoginWebView.CoreWebView2 is { } core)
        {
            core.DownloadStarting -= Core_DownloadStarting;
            core.LaunchingExternalUriScheme -= Core_LaunchingExternalUriScheme;
            core.NewWindowRequested -= Core_NewWindowRequested;
            core.NavigationStarting -= Core_NavigationStarting;
            core.PermissionRequested -= Core_PermissionRequested;
            LoginWebView.NavigationCompleted -= LoginWebView_NavigationCompleted;

            try
            {
                core.CookieManager.DeleteAllCookies();
                await core.Profile.ClearBrowsingDataAsync();
            }
            catch (Exception exception) when (exception is InvalidOperationException or IOException or COMException)
            {
                // The temporary profile is also removed below.
            }

            try
            {
                core.Stop();
            }
            catch (InvalidOperationException)
            {
                // WebView2 may already be shutting down.
            }
        }

        try
        {
            LoginWebView.Dispose();
        }
        catch (Exception exception) when (exception is InvalidOperationException or COMException)
        {
            // Releasing the profile lease still lets startup cleanup retry.
        }
        finally
        {
            _profileLease?.Dispose();
            _profileLease = null;
        }

        await ClaudeLoginProfileCleanup.DeleteProfileWithRetryAsync(_profilePath);
    }
}
