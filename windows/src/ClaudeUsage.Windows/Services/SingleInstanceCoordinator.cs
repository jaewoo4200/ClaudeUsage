using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;

namespace ClaudeUsage.Windows.Services;

internal readonly record struct SingleInstanceNames(string MutexName, string PipeName)
{
    public static SingleInstanceNames ForCurrentUser()
    {
        string identity;
        try
        {
            using var currentIdentity = WindowsIdentity.GetCurrent();
            identity = currentIdentity.User?.Value
                       ?? Environment.UserName;
        }
        catch (Exception exception) when (
            exception is SecurityException
                or UnauthorizedAccessException
                or PlatformNotSupportedException)
        {
            identity = Environment.UserName;
        }

        using var process = Process.GetCurrentProcess();
        return ForIdentity(identity, process.SessionId);
    }

    internal static SingleInstanceNames ForIdentity(string identity, int sessionId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(identity);
        var identityBytes = Encoding.UTF8.GetBytes($"{identity}|{sessionId}");
        var suffix = Convert.ToHexString(SHA256.HashData(identityBytes).AsSpan(0, 16));
        return new SingleInstanceNames(
            $@"Local\ClaudeUsage.Windows.{suffix}",
            $"ClaudeUsage.Windows.{suffix}");
    }
}

internal readonly record struct SingleInstanceStartResult(
    SingleInstanceCoordinator? Coordinator,
    bool ActivationForwarded)
{
    public bool IsPrimary => Coordinator is not null;
}

/// <summary>
/// Owns the per-session application mutex and a same-user-only activation pipe.
/// The fixed-size pipe protocol deliberately exposes no general command surface.
/// </summary>
internal sealed class SingleInstanceCoordinator : IDisposable
{
    private static readonly byte[] ActivationCommand = [0x43, 0x55, 0x01];
    private static readonly byte[] ActivationAcknowledgement = [0x4F, 0x4B, 0x01];
    private static readonly TimeSpan ClientAttemptTimeout = TimeSpan.FromMilliseconds(180);
    private static readonly TimeSpan RetryDelay = TimeSpan.FromMilliseconds(40);

    private readonly Mutex _mutex;
    private readonly string _pipeName;
    private readonly Func<bool> _activationRequested;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly object _serverGate = new();
    private readonly Task _listenTask;
    private NamedPipeServerStream? _activeServer;
    private bool _disposed;

    private SingleInstanceCoordinator(
        Mutex mutex,
        string pipeName,
        Func<bool> activationRequested)
    {
        _mutex = mutex;
        _pipeName = pipeName;
        _activationRequested = activationRequested;
        _listenTask = Task.Run(ListenAsync);
    }

    public static SingleInstanceStartResult Start(
        Func<bool> activationRequested,
        TimeSpan? handoffTimeout = null) =>
        Start(
            SingleInstanceNames.ForCurrentUser(),
            activationRequested,
            handoffTimeout ?? TimeSpan.FromSeconds(2.5));

    internal static SingleInstanceStartResult Start(
        SingleInstanceNames names,
        Func<bool> activationRequested,
        TimeSpan handoffTimeout)
    {
        ArgumentNullException.ThrowIfNull(activationRequested);
        if (handoffTimeout < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(handoffTimeout));
        }

        Mutex mutex;
        try
        {
            mutex = new Mutex(initiallyOwned: false, names.MutexName);
        }
        catch (Exception exception) when (
            exception is UnauthorizedAccessException or SecurityException)
        {
            return new SingleInstanceStartResult(
                Coordinator: null,
                ActivationForwarded: false);
        }

        var stopwatch = Stopwatch.StartNew();
        do
        {
            if (TryAcquire(mutex))
            {
                return new SingleInstanceStartResult(
                    new SingleInstanceCoordinator(mutex, names.PipeName, activationRequested),
                    ActivationForwarded: false);
            }

            var remaining = handoffTimeout - stopwatch.Elapsed;
            if (remaining <= TimeSpan.Zero)
            {
                break;
            }

            var attemptTimeout = remaining < ClientAttemptTimeout
                ? remaining
                : ClientAttemptTimeout;
            if (TryForwardActivation(names.PipeName, attemptTimeout, remaining))
            {
                mutex.Dispose();
                return new SingleInstanceStartResult(
                    Coordinator: null,
                    ActivationForwarded: true);
            }

            remaining = handoffTimeout - stopwatch.Elapsed;
            if (remaining > TimeSpan.Zero)
            {
                Thread.Sleep(remaining < RetryDelay ? remaining : RetryDelay);
            }
        }
        while (stopwatch.Elapsed < handoffTimeout);

        // The previous process can stop its pipe just before releasing the mutex.
        // A final ownership attempt lets this process become primary in that race.
        if (TryAcquire(mutex))
        {
            return new SingleInstanceStartResult(
                new SingleInstanceCoordinator(mutex, names.PipeName, activationRequested),
                ActivationForwarded: false);
        }

        mutex.Dispose();
        return new SingleInstanceStartResult(Coordinator: null, ActivationForwarded: false);
    }

    public void Dispose()
    {
        lock (_serverGate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _shutdown.Cancel();
            _activeServer?.Dispose();
        }

        var listenerStopped = false;
        try
        {
            listenerStopped = _listenTask.Wait(TimeSpan.FromSeconds(1));
        }
        catch (AggregateException exception) when (
            exception.InnerExceptions.All(inner =>
                inner is OperationCanceledException or ObjectDisposedException))
        {
            // Cancellation/disposal is the expected listener shutdown path.
            listenerStopped = true;
        }

        if (listenerStopped)
        {
            _shutdown.Dispose();
        }
        else
        {
            _ = _listenTask.ContinueWith(
                static (_, state) => ((CancellationTokenSource)state!).Dispose(),
                _shutdown,
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }

        try
        {
            _mutex.ReleaseMutex();
        }
        catch (ApplicationException)
        {
            // Process teardown can race an already-abandoned ownership handle.
        }

        _mutex.Dispose();
        GC.SuppressFinalize(this);
    }

    private async Task ListenAsync()
    {
        while (!_shutdown.IsCancellationRequested)
        {
            NamedPipeServerStream? server = null;
            try
            {
                server = new NamedPipeServerStream(
                    _pipeName,
                    PipeDirection.InOut,
                    maxNumberOfServerInstances: 1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

                lock (_serverGate)
                {
                    if (_disposed)
                    {
                        server.Dispose();
                        return;
                    }

                    _activeServer = server;
                }

                await server.WaitForConnectionAsync(_shutdown.Token).ConfigureAwait(false);
                using var readTimeout = CancellationTokenSource.CreateLinkedTokenSource(
                    _shutdown.Token);
                readTimeout.CancelAfter(TimeSpan.FromSeconds(1));
                var command = new byte[ActivationCommand.Length];
                await server.ReadExactlyAsync(command, readTimeout.Token).ConfigureAwait(false);
                if (command.AsSpan().SequenceEqual(ActivationCommand))
                {
                    var accepted = false;
                    try
                    {
                        accepted = _activationRequested();
                    }
                    catch (Exception)
                    {
                        // A UI teardown race must not terminate the listener loop.
                    }

                    if (accepted)
                    {
                        await server.WriteAsync(
                                ActivationAcknowledgement,
                                _shutdown.Token)
                            .ConfigureAwait(false);
                        await server.FlushAsync(_shutdown.Token).ConfigureAwait(false);
                    }
                }
            }
            catch (Exception exception) when (
                exception is OperationCanceledException
                    or IOException
                    or ObjectDisposedException
                    or SecurityException
                    or UnauthorizedAccessException)
            {
                if (!_shutdown.IsCancellationRequested
                    && exception is IOException or SecurityException or UnauthorizedAccessException)
                {
                    try
                    {
                        await Task.Delay(RetryDelay, _shutdown.Token).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException)
                    {
                        return;
                    }
                }
            }
            finally
            {
                lock (_serverGate)
                {
                    if (ReferenceEquals(_activeServer, server))
                    {
                        _activeServer = null;
                    }
                }

                server?.Dispose();
            }
        }
    }

    private static bool TryAcquire(Mutex mutex)
    {
        try
        {
            return mutex.WaitOne(0);
        }
        catch (AbandonedMutexException)
        {
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static bool TryForwardActivation(
        string pipeName,
        TimeSpan connectTimeout,
        TimeSpan acknowledgementTimeout)
    {
        try
        {
            using var client = new NamedPipeClientStream(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            client.Connect(Math.Max(1, (int)Math.Ceiling(connectTimeout.TotalMilliseconds)));
            client.Write(ActivationCommand, 0, ActivationCommand.Length);
            client.Flush();
            using var acknowledgementCancellation =
                new CancellationTokenSource(acknowledgementTimeout);
            var acknowledgement = new byte[ActivationAcknowledgement.Length];
            client.ReadExactlyAsync(acknowledgement, acknowledgementCancellation.Token)
                .AsTask()
                .GetAwaiter()
                .GetResult();
            return acknowledgement.AsSpan().SequenceEqual(ActivationAcknowledgement);
        }
        catch (Exception exception) when (
            exception is TimeoutException
                or OperationCanceledException
                or IOException
                or SecurityException
                or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
