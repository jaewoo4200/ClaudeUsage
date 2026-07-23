using System.Net;

namespace ClaudeUsage.Windows.Services;

public enum ClaudeUsageErrorKind
{
    NoCookie,
    AuthenticationExpired,
    Network,
    InvalidResponse,
}

public sealed class ClaudeUsageException : Exception
{
    public ClaudeUsageException(
        ClaudeUsageErrorKind kind,
        string message,
        Exception? innerException = null,
        HttpStatusCode? statusCode = null)
        : base(message, innerException)
    {
        Kind = kind;
        StatusCode = statusCode;
    }

    public ClaudeUsageErrorKind Kind { get; }

    public HttpStatusCode? StatusCode { get; }
}
