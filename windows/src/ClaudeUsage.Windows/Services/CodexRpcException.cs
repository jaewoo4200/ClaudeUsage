namespace ClaudeUsage.Windows.Services;

public enum CodexRpcErrorKind
{
    Unavailable,
    AuthenticationRequired,
    Timeout,
    Protocol,
    ProcessExited
}

public sealed class CodexRpcException(CodexRpcErrorKind kind, string message, Exception? innerException = null)
    : Exception(message, innerException)
{
    public CodexRpcErrorKind Kind { get; } = kind;
}
