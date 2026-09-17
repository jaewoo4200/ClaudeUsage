using System.Text.Json;
using ClaudeUsage.Core.Models;
using ClaudeUsage.Core.Parsing;

namespace ClaudeUsage.Core.Tests;

public sealed class ClaudeOrganizationParserTests
{
    [Fact]
    public void ParseFirst_SelectsFirstOrganizationAndMapsPlan()
    {
        var organization = ClaudeOrganizationParser.ParseFirst(
            ReadFixture("claude-organizations.json"));

        Assert.Equal("redacted-org-001", organization.Id);
        Assert.Equal("Redacted Team", organization.Name);
        Assert.Equal(ClaudePlan.Max20X, organization.Plan);
        Assert.Equal("Max 20x", organization.PlanDisplayName);
    }

    [Fact]
    public void ParseFirst_AcceptsSingleOrganizationAndCapabilityFallback()
    {
        var organization = ClaudeOrganizationParser.ParseFirst(
            """
            {
              "uuid": "redacted-single",
              "capabilities": ["claude_pro", 42, null]
            }
            """);

        Assert.Equal(ClaudePlan.Pro, organization.Plan);
        Assert.Equal(["claude_pro"], organization.Capabilities);
    }

    [Fact]
    public void ParseFirst_SkipsMalformedArrayEntriesWithoutUsingTheirIdentifiers()
    {
        var organization = ClaudeOrganizationParser.ParseFirst(
            """
            [
              null,
              {"uuid": ""},
              {"uuid": "redacted-valid", "capabilities": ["chat"]}
            ]
            """);

        Assert.Equal("redacted-valid", organization.Id);
        Assert.Equal(ClaudePlan.Free, organization.Plan);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("[]")]
    [InlineData("[{\"uuid\":null}]")]
    public void ParseFirst_RejectsMissingOrganizationIdentity(string json)
    {
        Assert.Throws<JsonException>(() => ClaudeOrganizationParser.ParseFirst(json));
    }

    private static string ReadFixture(string fileName) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", fileName));
}
