namespace ClaudeUsage.Windows.Services;

public interface IClaudeCookieStore
{
    Task<string?> LoadAsync(CancellationToken cancellationToken = default);

    Task SaveAsync(string cookieHeader, CancellationToken cancellationToken = default);

    Task ClearAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Clears the stored session only when it still matches the session used by
    /// the caller. Implementations must make the comparison and deletion atomic
    /// with respect to <see cref="SaveAsync"/>.
    /// </summary>
    Task<bool> ClearIfMatchesAsync(
        string expectedCookieHeader,
        CancellationToken cancellationToken = default);
}
