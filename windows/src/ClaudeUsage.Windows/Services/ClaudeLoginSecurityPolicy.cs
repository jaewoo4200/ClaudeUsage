namespace ClaudeUsage.Windows.Services;

internal readonly record struct ClaudeLoginCookieCandidate(
    string Name,
    string Value,
    string? Domain,
    string? Path);

internal static class ClaudeLoginSecurityPolicy
{
    private static readonly string[] SessionCookieNames =
    [
        "sessionKey",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
    ];

    // These are top-level authentication pages, not subresource hosts. Claude's
    // own origin remains available for email sign-in and the OAuth/SAML return.
    private static readonly HashSet<string> ExactAuthenticationHosts = new(
        StringComparer.OrdinalIgnoreCase)
    {
        "accounts.google.com",
        "api.workos.com",
        "appleid.apple.com",
        "login.microsoftonline.com",
        "sso.jumpcloud.com",
    };

    // Claude supports organization-managed SSO. Limit those navigations to
    // well-known hosted IdP zones while still allowing each customer's tenant.
    private static readonly string[] AuthenticationHostZones =
    [
        "authkit.app",
        "duosecurity.com",
        "okta.com",
        "okta-emea.com",
        "oktapreview.com",
        "onelogin.com",
        "pingone.com",
        "pingone.eu",
        "pingone.asia",
        "pingone.ca",
    ];

    public static bool IsAllowedNavigation(string? rawUri)
    {
        if (string.Equals(rawUri, "about:blank", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out var uri)
            || !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
            || !uri.IsDefaultPort
            || !string.IsNullOrEmpty(uri.UserInfo))
        {
            return false;
        }

        var host = uri.IdnHost;
        return IsHostOrSubdomain(host, "claude.ai")
            || ExactAuthenticationHosts.Contains(host)
            || AuthenticationHostZones.Any(zone => IsHostOrSubdomain(host, zone));
    }

    public static string? BuildSessionCookieHeader(
        IEnumerable<ClaudeLoginCookieCandidate> cookies)
    {
        ArgumentNullException.ThrowIfNull(cookies);

        var eligibleCookies = cookies
            .Where(IsEligibleSessionCookie)
            .ToArray();
        var headerParts = new List<string>(SessionCookieNames.Length);

        // Keep at most one value for each recognized session mechanism. Claude
        // has changed the cookie name over time, so retaining the known aliases
        // preserves existing sessions without persisting analytics or UI state.
        foreach (var cookieName in SessionCookieNames)
        {
            var cookie = eligibleCookies.FirstOrDefault(candidate =>
                string.Equals(candidate.Name, cookieName, StringComparison.Ordinal));
            if (!string.IsNullOrEmpty(cookie.Name))
            {
                headerParts.Add($"{cookie.Name}={cookie.Value}");
            }
        }

        return headerParts.Count == 0
            ? null
            : string.Join("; ", headerParts);
    }

    private static bool IsEligibleSessionCookie(ClaudeLoginCookieCandidate cookie) =>
        SessionCookieNames.Contains(cookie.Name, StringComparer.Ordinal)
        && IsClaudeSessionDomain(cookie.Domain)
        && string.Equals(cookie.Path, "/", StringComparison.Ordinal)
        && IsSafeCookieValue(cookie.Value);

    private static bool IsClaudeSessionDomain(string? domain) =>
        string.Equals(domain, "claude.ai", StringComparison.OrdinalIgnoreCase)
        || string.Equals(domain, ".claude.ai", StringComparison.OrdinalIgnoreCase);

    private static bool IsSafeCookieValue(string value) =>
        !string.IsNullOrEmpty(value)
        && !value.Contains('\r')
        && !value.Contains('\n')
        && !value.Contains(';');

    private static bool IsHostOrSubdomain(string host, string zone) =>
        host.Equals(zone, StringComparison.OrdinalIgnoreCase)
        || host.EndsWith($".{zone}", StringComparison.OrdinalIgnoreCase);
}
