using System.Text.Json;
using ClaudeUsage.Core.Models;

namespace ClaudeUsage.Core.Parsing;

public static class ClaudeOrganizationParser
{
    public static ClaudeOrganization ParseFirst(string json)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(json);
        using var document = JsonDocument.Parse(json);
        return ParseFirst(document.RootElement);
    }

    public static ClaudeOrganization ParseFirst(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Array)
        {
            foreach (var element in root.EnumerateArray())
            {
                if (TryParse(element, out var organization))
                {
                    return organization;
                }
            }
        }
        else if (TryParse(root, out var organization))
        {
            return organization;
        }

        throw new JsonException("The Claude organization response does not contain a valid organization.");
    }

    private static bool TryParse(JsonElement element, out ClaudeOrganization organization)
    {
        organization = null!;
        if (element.ValueKind != JsonValueKind.Object
            || !TryReadString(element, "uuid", out var id)
            || string.IsNullOrWhiteSpace(id))
        {
            return false;
        }

        var capabilities = new List<string>();
        if (TryGetProperty(element, "capabilities", out var capabilitiesElement)
            && capabilitiesElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var capability in capabilitiesElement.EnumerateArray())
            {
                if (capability.ValueKind == JsonValueKind.String
                    && !string.IsNullOrWhiteSpace(capability.GetString()))
                {
                    capabilities.Add(capability.GetString()!);
                }
            }
        }

        TryReadString(element, "name", out var name);
        TryReadString(element, "rate_limit_tier", out var rateLimitTier);
        organization = new ClaudeOrganization(id, name, capabilities, rateLimitTier);
        return true;
    }

    private static bool TryReadString(JsonElement element, string name, out string? value)
    {
        if (TryGetProperty(element, name, out var property)
            && property.ValueKind == JsonValueKind.String)
        {
            value = property.GetString();
            return true;
        }

        value = null;
        return false;
    }

    private static bool TryGetProperty(JsonElement element, string name, out JsonElement value)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                {
                    value = property.Value;
                    return true;
                }
            }
        }

        value = default;
        return false;
    }
}
