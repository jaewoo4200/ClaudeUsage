using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Core.Parsing;

namespace ClaudeUsage.Windows.Services;

public sealed class ClaudeUsageService
{
    public const string DefaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0";

    private const int MaximumResponseCharacters = 2 * 1024 * 1024;
    private static readonly Uri BaseUri = new("https://claude.ai/");

    private readonly HttpClient _httpClient;
    private readonly IClaudeCookieStore _cookieStore;
    private readonly string _userAgent;

    public ClaudeUsageService(
        HttpClient httpClient,
        IClaudeCookieStore cookieStore,
        string? userAgent = null)
    {
        _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
        _cookieStore = cookieStore ?? throw new ArgumentNullException(nameof(cookieStore));
        _userAgent = string.IsNullOrWhiteSpace(userAgent) ? DefaultUserAgent : userAgent.Trim();
        if (_userAgent.Contains('\r') || _userAgent.Contains('\n'))
        {
            throw new ArgumentException("The user agent contains an invalid line break.", nameof(userAgent));
        }
    }

    public async Task<ClaudeAccountSnapshot> FetchSnapshotAsync(
        CancellationToken cancellationToken = default)
    {
        string? cookieHeader;
        try
        {
            cookieHeader = await _cookieStore.LoadAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is CryptographicException or IOException)
        {
            throw new ClaudeUsageException(
                ClaudeUsageErrorKind.NoCookie,
                "The saved Claude session could not be read. Please log in again.",
                exception);
        }

        if (string.IsNullOrWhiteSpace(cookieHeader))
        {
            throw new ClaudeUsageException(
                ClaudeUsageErrorKind.NoCookie,
                "Claude login is required.");
        }

        ValidateCookieHeader(cookieHeader);

        var organizationsJson = await SendAsync(
            new Uri(BaseUri, "api/organizations"),
            cookieHeader,
            cancellationToken);

        ClaudeOrganization organization;
        try
        {
            organization = ClaudeOrganizationParser.ParseFirst(organizationsJson);
        }
        catch (Exception exception) when (exception is JsonException or ArgumentException)
        {
            throw new ClaudeUsageException(
                ClaudeUsageErrorKind.InvalidResponse,
                "Claude returned an unsupported organization response.",
                exception);
        }

        var escapedOrganizationId = Uri.EscapeDataString(organization.Id);
        var usageJson = await SendAsync(
            new Uri(BaseUri, $"api/organizations/{escapedOrganizationId}/usage"),
            cookieHeader,
            cancellationToken);

        try
        {
            return new ClaudeAccountSnapshot(
                organization,
                ClaudeUsageParser.Parse(usageJson));
        }
        catch (Exception exception) when (exception is JsonException or ArgumentException)
        {
            throw new ClaudeUsageException(
                ClaudeUsageErrorKind.InvalidResponse,
                "Claude returned an unsupported usage response.",
                exception);
        }
    }

    public Task LogoutAsync(CancellationToken cancellationToken = default) =>
        _cookieStore.ClearAsync(cancellationToken);

    private async Task<string> SendAsync(
        Uri uri,
        string cookieHeader,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/plain"));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("*/*"));
        request.Headers.Referrer = BaseUri;
        request.Headers.TryAddWithoutValidation("User-Agent", _userAgent);
        request.Headers.TryAddWithoutValidation("Cookie", cookieHeader);

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new ClaudeUsageException(
                ClaudeUsageErrorKind.Network,
                "The Claude request timed out.");
        }
        catch (HttpRequestException exception)
        {
            throw new ClaudeUsageException(
                ClaudeUsageErrorKind.Network,
                "Claude could not be reached.",
                exception,
                exception.StatusCode);
        }

        using (response)
        {
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                await ClearExpiredSessionIfUnchangedBestEffortAsync(cookieHeader);
                throw new ClaudeUsageException(
                    ClaudeUsageErrorKind.AuthenticationExpired,
                    "The Claude session has expired.",
                    statusCode: response.StatusCode);
            }

            if (!response.IsSuccessStatusCode)
            {
                throw new ClaudeUsageException(
                    ClaudeUsageErrorKind.Network,
                    $"Claude returned HTTP {(int)response.StatusCode}.",
                    statusCode: response.StatusCode);
            }

            if (response.Content.Headers.ContentLength is > MaximumResponseCharacters)
            {
                throw new ClaudeUsageException(
                    ClaudeUsageErrorKind.InvalidResponse,
                    "The Claude response was unexpectedly large.");
            }

            string content;
            try
            {
                content = await response.Content.ReadAsStringAsync(cancellationToken);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new ClaudeUsageException(
                    ClaudeUsageErrorKind.Network,
                    "The Claude response timed out.");
            }
            catch (HttpRequestException exception)
            {
                throw new ClaudeUsageException(
                    ClaudeUsageErrorKind.Network,
                    "The Claude response could not be read.",
                    exception,
                    exception.StatusCode);
            }
            if (content.Length > MaximumResponseCharacters)
            {
                throw new ClaudeUsageException(
                    ClaudeUsageErrorKind.InvalidResponse,
                    "The Claude response was unexpectedly large.");
            }

            return content;
        }
    }

    private async Task ClearExpiredSessionIfUnchangedBestEffortAsync(string cookieHeader)
    {
        try
        {
            _ = await _cookieStore.ClearIfMatchesAsync(cookieHeader, CancellationToken.None);
        }
        catch (Exception exception) when (
            exception is CryptographicException or IOException or UnauthorizedAccessException)
        {
            // Preserve the authentication-expired signal. A corrupt or replaced
            // session is handled by the next explicit login/logout action.
        }
    }

    private static void ValidateCookieHeader(string cookieHeader)
    {
        if (cookieHeader.Contains('\r') || cookieHeader.Contains('\n'))
        {
            throw new ClaudeUsageException(
                ClaudeUsageErrorKind.NoCookie,
                "The saved Claude session is invalid.");
        }
    }
}
