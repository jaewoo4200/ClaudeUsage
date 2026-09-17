using ClaudeUsage.Windows.Services;

namespace ClaudeUsage.Windows.Tests;

public sealed class ClaudeLoginSecurityPolicyTests
{
    [Theory]
    [InlineData("about:blank")]
    [InlineData("https://claude.ai/login")]
    [InlineData("https://auth.claude.ai/oauth/callback")]
    [InlineData("https://accounts.google.com/o/oauth2/v2/auth")]
    [InlineData("https://api.workos.com/sso/authorize/example")]
    [InlineData("https://tenant.authkit.app/login")]
    [InlineData("https://example.okta.com/app/claude/sso/saml")]
    [InlineData("https://login.microsoftonline.com/example/saml2")]
    public void NavigationAllowlist_AcceptsOnlyKnownAuthenticationOrigins(string uri)
    {
        Assert.True(ClaudeLoginSecurityPolicy.IsAllowedNavigation(uri));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("not a URI")]
    [InlineData("http://claude.ai/login")]
    [InlineData("https://claude.ai:8443/login")]
    [InlineData("https://claude.ai.evil.example/login")]
    [InlineData("https://accounts.google.com.evil.example/oauth")]
    [InlineData("https://example.com/login")]
    [InlineData("file:///C:/Windows/System32/calc.exe")]
    [InlineData("javascript:alert(document.domain)")]
    [InlineData("data:text/html,unsafe")]
    [InlineData("mailto:user@example.com")]
    [InlineData("about:config")]
    public void NavigationAllowlist_BlocksExternalAndUnsafeUris(string? uri)
    {
        Assert.False(ClaudeLoginSecurityPolicy.IsAllowedNavigation(uri));
    }

    [Fact]
    public void CookieHeader_PersistsOnlyRootScopedRecognizedSessionCookies()
    {
        var cookies = new[]
        {
            Cookie("analytics", "tracking-value"),
            Cookie("sessionKey", "primary-session"),
            Cookie("sessionKey", "duplicate-is-ignored"),
            Cookie("__Secure-next-auth.session-token", "secure-alias", ".claude.ai"),
            Cookie("next-auth.session-token", "legacy-alias", "CLAUDE.AI"),
            Cookie("sessionKey", "subdomain-cookie", "preview.claude.ai"),
            Cookie("sessionKey", "wrong-path", path: "/api/auth"),
            Cookie("sessionKey", "malformed-domain", "..claude.ai"),
            Cookie("sessionkey", "wrong-case"),
            Cookie("sessionKey", "unsafe;value"),
        };

        var header = ClaudeLoginSecurityPolicy.BuildSessionCookieHeader(cookies);

        Assert.Equal(
            "sessionKey=primary-session; "
                + "__Secure-next-auth.session-token=secure-alias; "
                + "next-auth.session-token=legacy-alias",
            header);
        Assert.DoesNotContain("analytics", header, StringComparison.Ordinal);
        Assert.DoesNotContain("subdomain-cookie", header, StringComparison.Ordinal);
        Assert.DoesNotContain("duplicate-is-ignored", header, StringComparison.Ordinal);
    }

    [Fact]
    public void CookieHeader_ReturnsNullWhenNoValidSessionCookieExists()
    {
        var cookies = new[]
        {
            Cookie("csrf-token", "csrf"),
            Cookie("sessionKey", "wrong-domain", "attacker.example"),
            Cookie("sessionKey", "line\nbreak"),
        };

        Assert.Null(ClaudeLoginSecurityPolicy.BuildSessionCookieHeader(cookies));
    }

    private static ClaudeLoginCookieCandidate Cookie(
        string name,
        string value,
        string domain = "claude.ai",
        string path = "/") => new(name, value, domain, path);
}
