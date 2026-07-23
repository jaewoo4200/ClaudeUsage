using ClaudeUsage.Windows.Services;

if (args.Length > 1)
{
    Console.Error.WriteLine("Usage: ClaudeUsage.Probe [codex.exe]");
    return 2;
}

try
{
    var executable = args.Length == 1
        ? args[0]
        : new CodexExecutableLocator(new AppSettings()).Resolve();
    if (string.IsNullOrWhiteSpace(executable))
    {
        Console.WriteLine("kind=Unavailable; requestFailed=true");
        return 1;
    }

    var payload = await new CodexAppServerClient(message => Console.WriteLine($"diagnostic={message}"))
        .FetchAsync(executable, CancellationToken.None);
    Console.WriteLine($"rateLimits={payload.RateLimits.ValueKind}; tokenUsage={payload.TokenUsage?.ValueKind.ToString() ?? "unavailable"}");
    return 0;
}
catch (CodexRpcException exception)
{
    // The app-server error body can contain provider diagnostics. Keep probe
    // output safe for CI logs by reporting only our normalized error kind.
    Console.WriteLine($"kind={exception.Kind}; requestFailed=true");
    return 1;
}
