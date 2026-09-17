using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Core.Parsing;
using ClaudeUsage.Windows.ViewModels;

namespace ClaudeUsage.Windows.Services;

public sealed class UsageCoordinator : IDisposable
{
    private readonly CodexExecutableLocator _locator;
    private readonly CodexAppServerClient _codexClient;
    private readonly ClaudeUsageService _claudeService;
    private readonly UsageHistoryService _historyService;
    private readonly UsageViewModel _viewModel;
    private readonly CompanionViewModel _companionViewModel;
    private readonly AppSettings _settings;
    private readonly bool _externalRefreshEnabled;
    private readonly TimeSpan _countdownInterval;
    private readonly Func<DateTimeOffset> _nowProvider;
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly object _refreshLock = new();
    private CancellationTokenSource? _activeRefresh;
    private long _refreshGeneration;
    private int _claudeLogoutInProgress;
    private int _started;
    private int _disposed;
    private Task? _countdownTimerTask;

    public UsageCoordinator(
        CodexExecutableLocator locator,
        CodexAppServerClient codexClient,
        ClaudeUsageService claudeService,
        UsageHistoryService historyService,
        UsageViewModel viewModel,
        CompanionViewModel companionViewModel,
        AppSettings settings,
        bool externalRefreshEnabled = true)
        : this(
            locator,
            codexClient,
            claudeService,
            historyService,
            viewModel,
            companionViewModel,
            settings,
            externalRefreshEnabled,
            TimeSpan.FromSeconds(1),
            static () => DateTimeOffset.Now)
    {
    }

    internal UsageCoordinator(
        CodexExecutableLocator locator,
        CodexAppServerClient codexClient,
        ClaudeUsageService claudeService,
        UsageHistoryService historyService,
        UsageViewModel viewModel,
        CompanionViewModel companionViewModel,
        AppSettings settings,
        bool externalRefreshEnabled,
        TimeSpan countdownInterval,
        Func<DateTimeOffset> nowProvider)
    {
        _locator = locator ?? throw new ArgumentNullException(nameof(locator));
        _codexClient = codexClient ?? throw new ArgumentNullException(nameof(codexClient));
        _claudeService = claudeService ?? throw new ArgumentNullException(nameof(claudeService));
        _historyService = historyService ?? throw new ArgumentNullException(nameof(historyService));
        _viewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _companionViewModel = companionViewModel ?? throw new ArgumentNullException(nameof(companionViewModel));
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));
        _externalRefreshEnabled = externalRefreshEnabled;
        if (countdownInterval <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(countdownInterval));
        }

        _countdownInterval = countdownInterval;
        _nowProvider = nowProvider ?? throw new ArgumentNullException(nameof(nowProvider));

        _historyService.SetEnabled(_settings.UsageHistoryEnabled);
        _companionViewModel.SelectedCompanion = _settings.SelectedCompanion;
        _companionViewModel.Sensitivity = _settings.CompanionSensitivity;
        _companionViewModel.AnimationMode = _settings.CompanionAnimationMode;
        _companionViewModel.ReducedMotion = _settings.ReducedMotion;
        _settings.PropertyChanged += OnSettingsPropertyChanged;
    }

    public void Start()
    {
        ThrowIfDisposed();
        if (Interlocked.Exchange(ref _started, 1) != 0)
        {
            return;
        }

        _viewModel.UpdateCountdowns(_nowProvider());
        _countdownTimerTask = RunCountdownTimerAsync(_lifetimeCancellation.Token);
        if (!_externalRefreshEnabled)
        {
            return;
        }

        _ = RefreshAsync();
        _ = RunTimerAsync(_lifetimeCancellation.Token);
    }

    internal Task CountdownCompletion => _countdownTimerTask ?? Task.CompletedTask;

    public async Task RefreshAsync()
    {
        ThrowIfDisposed();
        if (!_externalRefreshEnabled)
        {
            return;
        }

        CancellationTokenSource refreshCancellation;
        CancellationTokenSource? previousRefresh;
        long generation;
        lock (_refreshLock)
        {
            previousRefresh = _activeRefresh;
            _activeRefresh = CancellationTokenSource.CreateLinkedTokenSource(_lifetimeCancellation.Token);
            refreshCancellation = _activeRefresh;
            generation = ++_refreshGeneration;
        }
        TryCancel(previousRefresh);

        var cancellationToken = refreshCancellation.Token;
        await OnUiAsync(() =>
        {
            if (!IsCurrent(generation))
            {
                return;
            }

            _viewModel.SetRefreshing();
            _viewModel.SetClaudeRefreshing();
        });

        try
        {
            var codexTask = RefreshCodexAsync(generation, cancellationToken);
            var claudeTask = RefreshClaudeAsync(generation, cancellationToken);
            await Task.WhenAll(codexTask, claudeTask);

            if (IsCurrent(generation))
            {
                await UpdateHistoryAndCompanionAsync(generation, cancellationToken);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // A newer manual/timer refresh superseded this one, or the app is exiting.
        }
        catch (Exception exception)
        {
            // Provider failures are translated inside their independent refresh
            // paths. Keep an unexpected history/UI failure from faulting a
            // fire-and-forget refresh or permanently stopping the timer.
            Debug.WriteLine($"Usage refresh failed: {exception.GetType().Name}");
        }
        finally
        {
            lock (_refreshLock)
            {
                if (ReferenceEquals(_activeRefresh, refreshCancellation))
                {
                    _activeRefresh = null;
                }
            }
            refreshCancellation.Dispose();
        }
    }

    public async Task LogoutClaudeAsync(CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        Interlocked.Exchange(ref _claudeLogoutInProgress, 1);
        CancellationTokenSource? refreshToCancel;
        lock (_refreshLock)
        {
            refreshToCancel = _activeRefresh;
            _activeRefresh = null;
            _refreshGeneration++;
        }
        TryCancel(refreshToCancel);

        try
        {
            await _claudeService.LogoutAsync(cancellationToken);
            await OnUiAsync(() =>
            {
                _viewModel.ClearClaudeForLogout();
                ApplyCompanionState(
                    _viewModel.CreateHistorySnapshot(),
                    UsageTrend.Empty,
                    historyEnabled: false,
                    DateTimeOffset.Now);
            });
        }
        finally
        {
            Volatile.Write(ref _claudeLogoutInProgress, 0);
            if (Volatile.Read(ref _disposed) == 0)
            {
                _ = RefreshAsync();
            }
        }
    }

    public async Task ClearHistoryAsync(CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        await _historyService.ClearAsync(cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        await OnUiAsync(() =>
        {
            _viewModel.ApplyClaudeLocalTokens(null);
            ApplyCompanionState(
                _viewModel.CreateHistorySnapshot(),
                UsageTrend.Empty,
                _settings.UsageHistoryEnabled,
                DateTimeOffset.Now);
        });
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        _settings.PropertyChanged -= OnSettingsPropertyChanged;
        _lifetimeCancellation.Cancel();
        lock (_refreshLock)
        {
            _activeRefresh?.Cancel();
            _activeRefresh = null;
        }
        _lifetimeCancellation.Dispose();
        GC.SuppressFinalize(this);
    }

    private async Task RefreshCodexAsync(long generation, CancellationToken cancellationToken)
    {
        try
        {
            var executable = _locator.Resolve();
            if (executable is null)
            {
                await SetCodexErrorIfCurrentAsync(
                    generation,
                    T("Codex를 찾을 수 없습니다", "Codex was not found"),
                    T(
                        "공식 Codex 앱 또는 CLI를 설치한 뒤 실행 파일 경로를 선택해 주세요.",
                        "Install the official Codex app or CLI, then select its executable path."),
                    needsSetup: true);
                return;
            }

            var payload = await _codexClient.FetchAsync(executable, cancellationToken);
            var usage = CodexUsageMapper.Parse(payload.RateLimits, payload.TokenUsage);
            await OnUiAsync(() =>
            {
                if (IsCurrent(generation))
                {
                    _viewModel.ApplySnapshot(usage, DateTimeOffset.Now);
                }
            });
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal cancellation when another refresh wins.
        }
        catch (CodexRpcException exception)
        {
            var (title, detail, needsSetup) = exception.Kind switch
            {
                CodexRpcErrorKind.AuthenticationRequired => (
                    T("Codex 로그인이 필요합니다", "Codex sign-in required"),
                    T(
                        "터미널에서 codex login을 완료한 뒤 다시 새로 고쳐 주세요.",
                        "Run codex login in a terminal, then refresh again."),
                    true),
                CodexRpcErrorKind.Timeout => (
                    T("Codex 응답이 늦어지고 있습니다", "Codex is taking too long to respond"),
                    T(
                        "네트워크와 Codex 로그인 상태를 확인한 뒤 다시 시도해 주세요.",
                        "Check your network and Codex sign-in status, then try again."),
                    false),
                CodexRpcErrorKind.Unavailable => (
                    T("Codex를 실행할 수 없습니다", "Codex could not be started"),
                    T(
                        "선택한 실행 파일이 현재 계정에서 실행 가능한지 확인해 주세요.",
                        "Make sure the selected executable can run under the current account."),
                    true),
                _ => (
                    T("Codex 사용량을 불러오지 못했습니다", "Could not load Codex usage"),
                    T(
                        "이전 값은 유지됩니다. 잠시 후 자동으로 다시 시도합니다.",
                        "Previous values are preserved. The app will retry automatically shortly."),
                    false),
            };
            await SetCodexErrorIfCurrentAsync(generation, title, detail, needsSetup);
        }
        catch (JsonException)
        {
            await SetCodexErrorIfCurrentAsync(
                generation,
                T("Codex 응답 형식이 변경되었습니다", "The Codex response format has changed"),
                T(
                    "이전 값은 유지됩니다. 앱 업데이트가 필요할 수 있습니다.",
                    "Previous values are preserved. An app update may be required."),
                needsSetup: false);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            await SetCodexErrorIfCurrentAsync(
                generation,
                T("Codex 사용량을 불러오지 못했습니다", "Could not load Codex usage"),
                T(
                    "파일 또는 프로세스 접근 권한을 확인해 주세요.",
                    "Check file and process access permissions."),
                needsSetup: false);
        }
        catch (Exception)
        {
            await SetCodexErrorIfCurrentAsync(
                generation,
                T("Codex 사용량을 불러오지 못했습니다", "Could not load Codex usage"),
                T(
                    "예상하지 못한 오류가 발생했습니다. 이전 값은 유지됩니다.",
                    "An unexpected error occurred. Previous values are preserved."),
                needsSetup: false);
        }
    }

    private async Task RefreshClaudeAsync(long generation, CancellationToken cancellationToken)
    {
        if (Volatile.Read(ref _claudeLogoutInProgress) != 0)
        {
            return;
        }

        if (!_settings.ClaudeCloudEnabled)
        {
            await OnUiAsync(() =>
            {
                if (IsCurrent(generation))
                {
                    _viewModel.SetClaudeUnavailable(
                        T("Claude 클라우드 연동이 꺼져 있습니다", "Claude cloud integration is off"),
                        T(
                            "설정에서 실험적 Claude 연동을 켜면 다시 조회합니다.",
                            "Enable the experimental Claude integration in Settings to fetch usage."));
                }
            });
            return;
        }

        try
        {
            var snapshot = await _claudeService.FetchSnapshotAsync(cancellationToken);
            await OnUiAsync(() =>
            {
                if (IsCurrent(generation))
                {
                    _viewModel.ApplyClaudeSnapshot(snapshot, DateTimeOffset.Now);
                }
            });
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal cancellation when another refresh wins.
        }
        catch (ClaudeUsageException exception)
        {
            var (title, detail, needsLogin) = exception.Kind switch
            {
                ClaudeUsageErrorKind.NoCookie => (
                    T("Claude 로그인이 필요합니다", "Claude sign-in required"),
                    T(
                        "Claude 계정을 연결하면 사용량이 여기에 표시됩니다.",
                        "Connect your Claude account to show usage here."),
                    true),
                ClaudeUsageErrorKind.AuthenticationExpired => (
                    T("Claude 세션이 만료되었습니다", "Your Claude session has expired"),
                    T(
                        "다시 로그인해 주세요. Codex 연결은 그대로 유지됩니다.",
                        "Sign in again. Your Codex connection will remain active."),
                    true),
                ClaudeUsageErrorKind.InvalidResponse => (
                    T("Claude 응답 형식이 변경되었습니다", "The Claude response format has changed"),
                    T(
                        "이전 값은 유지됩니다. 앱 업데이트가 필요할 수 있습니다.",
                        "Previous values are preserved. An app update may be required."),
                    false),
                _ => (
                    T("Claude 사용량을 불러오지 못했습니다", "Could not load Claude usage"),
                    T(
                        "이전 값은 유지됩니다. 네트워크를 확인한 뒤 다시 시도합니다.",
                        "Previous values are preserved. Check your network and try again."),
                    false),
            };
            await SetClaudeErrorIfCurrentAsync(generation, title, detail, needsLogin);
        }
        catch (Exception exception) when (
            exception is CryptographicException or IOException or UnauthorizedAccessException)
        {
            await SetClaudeErrorIfCurrentAsync(
                generation,
                T("Claude 로그인 정보를 열 수 없습니다", "Could not open Claude sign-in data"),
                T(
                    "현재 Windows 계정에서 다시 로그인해 주세요.",
                    "Sign in again from the current Windows account."),
                needsLogin: true);
        }
        catch (Exception)
        {
            await SetClaudeErrorIfCurrentAsync(
                generation,
                T("Claude 사용량을 불러오지 못했습니다", "Could not load Claude usage"),
                T(
                    "예상하지 못한 오류가 발생했습니다. Codex 연결은 그대로 유지됩니다.",
                    "An unexpected error occurred. Your Codex connection will remain active."),
                needsLogin: false);
        }
    }

    private async Task UpdateHistoryAndCompanionAsync(
        long generation,
        CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.Now;
        var snapshot = await OnUiAsync(_viewModel.CreateHistorySnapshot);
        if (!IsCurrent(generation))
        {
            return;
        }

        if (!_settings.UsageHistoryEnabled)
        {
            _historyService.SetEnabled(false);
            await OnUiAsync(() =>
            {
                if (!IsCurrent(generation))
                {
                    return;
                }

                _viewModel.SetClaudeHistoryDisabled();
                ApplyCompanionState(snapshot, UsageTrend.Empty, historyEnabled: false, now);
            });
            return;
        }

        _historyService.SetEnabled(true);
        try
        {
            var result = await _historyService.SampleAsync(
                snapshot,
                now,
                cancellationToken: cancellationToken);
            await OnUiAsync(() =>
            {
                if (!IsCurrent(generation))
                {
                    return;
                }

                _viewModel.ApplyClaudeLocalTokens(result.ClaudeLocalTokens?.TodayTokens);
                ApplyCompanionState(result.Snapshot, result.Trend, historyEnabled: true, now);
            });
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or JsonException)
        {
            await OnUiAsync(() =>
            {
                if (IsCurrent(generation))
                {
                    ApplyCompanionState(snapshot, UsageTrend.Empty, historyEnabled: false, now);
                }
            });
        }
    }

    private void ApplyCompanionState(
        UsageHistorySnapshot snapshot,
        UsageTrend trend,
        bool historyEnabled,
        DateTimeOffset now)
    {
        _companionViewModel.ApplyUsage(snapshot, trend, historyEnabled, now);

        var resetCredits = _viewModel.LastCodexSnapshot?.RateLimitResetCredits;
        if (resetCredits is null)
        {
            _companionViewModel.ClearResetCreditStatus();
            return;
        }

        _companionViewModel.ApplyResetCreditStatus(
            resetCredits.UsableCount(now),
            resetCredits.EarliestExpiry(now),
            now: now);
    }

    private async Task RunTimerAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(60));
        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken))
            {
                try
                {
                    await RefreshAsync();
                }
                catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested)
                {
                    break;
                }
                catch (Exception exception) when (!cancellationToken.IsCancellationRequested)
                {
                    Debug.WriteLine($"Periodic refresh failed: {exception.GetType().Name}");
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal on application exit.
        }
    }

    private async Task RunCountdownTimerAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(_countdownInterval);
        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken))
            {
                await OnUiAsync(() => _viewModel.UpdateCountdowns(_nowProvider()));
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal on application exit.
        }
    }

    private bool IsCurrent(long generation)
    {
        lock (_refreshLock)
        {
            return generation == _refreshGeneration && !_lifetimeCancellation.IsCancellationRequested;
        }
    }

    private Task SetCodexErrorIfCurrentAsync(
        long generation,
        string title,
        string detail,
        bool needsSetup) => OnUiAsync(() =>
    {
        if (IsCurrent(generation))
        {
            _viewModel.SetError(title, detail, needsSetup);
        }
    });

    private Task SetClaudeErrorIfCurrentAsync(
        long generation,
        string title,
        string detail,
        bool needsLogin) => OnUiAsync(() =>
    {
        if (IsCurrent(generation))
        {
            _viewModel.SetClaudeError(title, detail, needsLogin);
        }
    });

    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppSettings.SelectedCompanion))
        {
            _companionViewModel.SelectedCompanion = _settings.SelectedCompanion;
        }
        else if (e.PropertyName == nameof(AppSettings.CompanionSensitivity))
        {
            _companionViewModel.Sensitivity = _settings.CompanionSensitivity;
        }
        else if (e.PropertyName == nameof(AppSettings.CompanionAnimationMode))
        {
            _companionViewModel.AnimationMode = _settings.CompanionAnimationMode;
        }
        else if (e.PropertyName == nameof(AppSettings.ReducedMotion))
        {
            _companionViewModel.ReducedMotion = _settings.ReducedMotion;
        }
        else if (e.PropertyName == nameof(AppSettings.UsageHistoryEnabled))
        {
            _historyService.SetEnabled(_settings.UsageHistoryEnabled);
            if (!_settings.UsageHistoryEnabled)
            {
                _viewModel.SetClaudeHistoryDisabled();
                ApplyCompanionState(
                    _viewModel.CreateHistorySnapshot(),
                    UsageTrend.Empty,
                    historyEnabled: false,
                    DateTimeOffset.Now);
            }
            else
            {
                _ = RefreshAsync();
            }
        }
        else if (e.PropertyName == nameof(AppSettings.ShowCodexSpark))
        {
            _ = RefreshAsync();
        }
        else if (e.PropertyName == nameof(AppSettings.ClaudeCloudEnabled))
        {
            _ = RefreshAsync();
        }
        else if (e.PropertyName == nameof(AppSettings.Language))
        {
            _companionViewModel.Language = _settings.Language;
            _viewModel.Relocalize();
            _ = RefreshAsync();
        }
    }

    private string T(string korean, string english) =>
        _settings.Language == AppLanguage.Korean ? korean : english;

    private static void TryCancel(CancellationTokenSource? cancellation)
    {
        if (cancellation is null)
        {
            return;
        }

        try
        {
            cancellation.Cancel();
        }
        catch (ObjectDisposedException)
        {
            // The superseded refresh completed between lock release and cancel.
        }
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed != 0, this);

    private static Task OnUiAsync(Action action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            action();
            return Task.CompletedTask;
        }

        return dispatcher.InvokeAsync(action).Task;
    }

    private static async Task<T> OnUiAsync<T>(Func<T> action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            return action();
        }

        return await dispatcher.InvokeAsync(action).Task;
    }
}
