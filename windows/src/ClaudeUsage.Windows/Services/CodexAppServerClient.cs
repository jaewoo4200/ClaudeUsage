using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace ClaudeUsage.Windows.Services;

public sealed class CodexAppServerClient
{
    private static readonly TimeSpan DefaultTotalTimeout = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan DefaultOptionalTokenGrace = TimeSpan.FromSeconds(2);
    private static readonly Encoding Utf8WithoutByteOrderMark = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

    private readonly Action<string>? _diagnosticObserver;
    private readonly Func<string, ProcessStartInfo> _startInfoFactory;
    private readonly TimeSpan _totalTimeout;
    private readonly TimeSpan _optionalTokenGrace;

    public CodexAppServerClient(Action<string>? diagnosticObserver = null)
        : this(
            diagnosticObserver,
            CreateStartInfo,
            DefaultTotalTimeout,
            DefaultOptionalTokenGrace)
    {
    }

    internal CodexAppServerClient(
        Action<string>? diagnosticObserver,
        Func<string, ProcessStartInfo> startInfoFactory,
        TimeSpan totalTimeout,
        TimeSpan optionalTokenGrace)
    {
        ArgumentNullException.ThrowIfNull(startInfoFactory);
        if (totalTimeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(totalTimeout));
        }
        if (optionalTokenGrace < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(optionalTokenGrace));
        }

        _diagnosticObserver = diagnosticObserver;
        _startInfoFactory = startInfoFactory;
        _totalTimeout = totalTimeout;
        _optionalTokenGrace = optionalTokenGrace;
    }

    public async Task<CodexRpcPayload> FetchAsync(string executablePath, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(_totalTimeout);

        var startInfo = _startInfoFactory(executablePath);

        using var process = new Process { StartInfo = startInfo };
        try
        {
            if (!process.Start())
            {
                throw new CodexRpcException(CodexRpcErrorKind.Unavailable, "Codex app-server를 시작하지 못했습니다.");
            }
            _diagnosticObserver?.Invoke("process-started");
        }
        catch (Exception exception) when (exception is Win32Exception or InvalidOperationException)
        {
            throw new CodexRpcException(
                CodexRpcErrorKind.Unavailable,
                "Codex 실행 파일을 시작할 수 없습니다.",
                exception);
        }

        using var readerCancellation = CancellationTokenSource.CreateLinkedTokenSource(timeout.Token);
        var initialize = NewCompletionSource<JsonElement>();
        var rateLimits = NewCompletionSource<JsonElement>();
        var tokenUsage = NewCompletionSource<JsonElement?>();
        var outputTask = ReadOutputAsync(
            process.StandardOutput,
            initialize,
            rateLimits,
            tokenUsage,
            _diagnosticObserver,
            readerCancellation.Token);
        var errorTask = DrainErrorAsync(process.StandardError, readerCancellation.Token);

        try
        {
            await SendAsync(
                process.StandardInput,
                """{"method":"initialize","id":0,"params":{"clientInfo":{"name":"claude_usage","title":"ClaudeUsage","version":"1.0"},"capabilities":{}}}""",
                timeout.Token);
            _diagnosticObserver?.Invoke("initialize-sent");

            _ = await initialize.Task.WaitAsync(timeout.Token);
            _diagnosticObserver?.Invoke("initialize-completed");

            await SendAsync(process.StandardInput, """{"method":"initialized","params":{}}""", timeout.Token);
            await SendAsync(process.StandardInput, """{"method":"account/rateLimits/read","id":7}""", timeout.Token);
            await SendAsync(process.StandardInput, """{"method":"account/usage/read","id":8}""", timeout.Token);

            var rateLimitResult = await rateLimits.Task.WaitAsync(timeout.Token);
            JsonElement? tokenResult = null;
            var completed = await Task.WhenAny(
                tokenUsage.Task,
                Task.Delay(_optionalTokenGrace, timeout.Token));
            if (completed == tokenUsage.Task)
            {
                try
                {
                    tokenResult = await tokenUsage.Task;
                }
                catch (Exception exception) when (exception is CodexRpcException or JsonException)
                {
                    // Token activity is supplementary. Keep a valid rate-limit snapshot.
                    tokenResult = null;
                }
            }

            return new CodexRpcPayload(rateLimitResult, tokenResult);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new CodexRpcException(CodexRpcErrorKind.Timeout, "Codex 사용량 조회 시간이 초과되었습니다.");
        }
        catch (IOException exception)
        {
            throw new CodexRpcException(
                CodexRpcErrorKind.ProcessExited,
                "Codex app-server 연결이 종료되었습니다.",
                exception);
        }
        finally
        {
            readerCancellation.Cancel();
            try
            {
                process.StandardInput.Close();
            }
            catch (IOException)
            {
                // The process may have already closed its input pipe.
            }

            if (!process.HasExited)
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch (Exception exception) when (exception is InvalidOperationException or Win32Exception)
                {
                    Debug.WriteLine($"Codex process cleanup failed: {exception.GetType().Name}");
                }
            }

            await ObserveAsync(outputTask);
            await ObserveAsync(errorTask);
        }
    }

    internal static string ResolveWritableWorkingDirectory()
    {
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return !string.IsNullOrWhiteSpace(userProfile) && Directory.Exists(userProfile)
            ? userProfile
            : Path.GetTempPath();
    }

    internal static ProcessStartInfo CreateStartInfo(string executablePath)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = executablePath,
            // Start-menu and StartupTask launches can inherit WindowsApps as
            // their current directory. Codex must receive a writable, stable CWD.
            WorkingDirectory = ResolveWritableWorkingDirectory(),
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardInputEncoding = Utf8WithoutByteOrderMark,
            StandardOutputEncoding = Utf8WithoutByteOrderMark,
            StandardErrorEncoding = Utf8WithoutByteOrderMark
        };
        startInfo.ArgumentList.Add("app-server");
        return startInfo;
    }

    private static TaskCompletionSource<T> NewCompletionSource<T>() =>
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    private static async Task SendAsync(
        StreamWriter writer,
        string message,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await writer.WriteLineAsync(message.AsMemory(), cancellationToken);
        await writer.FlushAsync(cancellationToken);
    }

    private static async Task ReadOutputAsync(
        StreamReader reader,
        TaskCompletionSource<JsonElement> initialize,
        TaskCompletionSource<JsonElement> rateLimits,
        TaskCompletionSource<JsonElement?> tokenUsage,
        Action<string>? diagnosticObserver,
        CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync(cancellationToken);
                if (line is null)
                {
                    break;
                }

                diagnosticObserver?.Invoke("stdout-line");
                HandleLine(line, initialize, rateLimits, tokenUsage, diagnosticObserver);
            }
        }
        catch (OperationCanceledException)
        {
            // Normal during cancellation and process cleanup.
        }
        catch (IOException exception)
        {
            SetPendingException(initialize, rateLimits, tokenUsage, new CodexRpcException(
                CodexRpcErrorKind.ProcessExited,
                "Codex app-server 출력을 읽지 못했습니다.",
                exception));
        }

        if (!cancellationToken.IsCancellationRequested)
        {
            SetPendingException(initialize, rateLimits, tokenUsage, new CodexRpcException(
                CodexRpcErrorKind.ProcessExited,
                "Codex app-server가 응답을 마치기 전에 종료되었습니다."));
        }
    }

    private static async Task DrainErrorAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        try
        {
            while (await reader.ReadLineAsync(cancellationToken) is not null)
            {
                // Intentionally discard stderr. It may contain account or environment details.
            }
        }
        catch (OperationCanceledException)
        {
            // Normal during cleanup.
        }
        catch (IOException)
        {
            // A closed stderr pipe is expected when the short-lived process is terminated.
        }
    }

    private static void HandleLine(
        string line,
        TaskCompletionSource<JsonElement> initialize,
        TaskCompletionSource<JsonElement> rateLimits,
        TaskCompletionSource<JsonElement?> tokenUsage,
        Action<string>? diagnosticObserver)
    {
        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (!root.TryGetProperty("id", out var idElement) || !idElement.TryGetInt32(out var id))
            {
                return;
            }
            diagnosticObserver?.Invoke($"response:{id}");

            if (root.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.Object)
            {
                var message = error.TryGetProperty("message", out var messageElement)
                    ? messageElement.GetString() ?? "Codex RPC 오류"
                    : "Codex RPC 오류";
                var kind = message.Contains("authentication required", StringComparison.OrdinalIgnoreCase)
                    ? CodexRpcErrorKind.AuthenticationRequired
                    : CodexRpcErrorKind.Protocol;
                var exception = new CodexRpcException(kind, message);

                if (id == 0)
                {
                    initialize.TrySetException(exception);
                }
                else if (id == 7)
                {
                    rateLimits.TrySetException(exception);
                }
                else if (id == 8)
                {
                    tokenUsage.TrySetResult(null);
                }
                return;
            }

            if (!root.TryGetProperty("result", out var result))
            {
                return;
            }

            if (id == 0)
            {
                initialize.TrySetResult(result.Clone());
            }
            else if (id == 7 && result.ValueKind == JsonValueKind.Object)
            {
                rateLimits.TrySetResult(result.Clone());
            }
            else if (id == 8)
            {
                tokenUsage.TrySetResult(result.ValueKind == JsonValueKind.Object ? result.Clone() : null);
            }
        }
        catch (JsonException)
        {
            // Ignore unrelated or malformed protocol lines; the total timeout still applies.
        }
    }

    private static void SetPendingException(
        TaskCompletionSource<JsonElement> initialize,
        TaskCompletionSource<JsonElement> rateLimits,
        TaskCompletionSource<JsonElement?> tokenUsage,
        Exception exception)
    {
        initialize.TrySetException(exception);
        rateLimits.TrySetException(exception);
        tokenUsage.TrySetException(exception);
    }

    private static async Task ObserveAsync(Task task)
    {
        try
        {
            await task;
        }
        catch (OperationCanceledException)
        {
            // Normal during cleanup.
        }
    }
}
