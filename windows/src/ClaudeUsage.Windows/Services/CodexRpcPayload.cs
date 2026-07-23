using System.Text.Json;

namespace ClaudeUsage.Windows.Services;

public sealed record CodexRpcPayload(JsonElement RateLimits, JsonElement? TokenUsage);
