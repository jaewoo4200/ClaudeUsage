import XCTest
@testable import ClaudeUsage

final class ForkCompatibilityTests: XCTestCase {
    func testIndexedCodexLimitOverridesLegacySummaryWithoutDuplicateCounter() throws {
        let json = Data(#"{"rateLimits":{"limitId":"old","primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":24,"windowDurationMins":300}}}}"#.utf8)
        let usage = try CodexAppServerUsageService.decodeFixture(rateLimitsJSON: json, tokenUsageJSON: Data("broken optional JSON".utf8))
        XCTAssertEqual(usage.rateLimit?.primaryWindow?.usedPercent, 24)
        XCTAssertTrue(usage.additionalRateLimits.isEmpty)
        XCTAssertNil(usage.tokenActivity)
    }

    func testMissingCodexQuotaDoesNotLookLikeZeroUsage() {
        XCTAssertThrowsError(try CodexAppServerUsageService.decodeFixture(rateLimitsJSON: Data("{}".utf8), tokenUsageJSON: nil))
    }

    func testClaudeOrganizationUsesActiveMembershipThenChatCapability() throws {
        let data = Data(#"[{"uuid":"api-only","capabilities":["api"]},{"uuid":"personal","capabilities":["chat"]},{"uuid":"team","capabilities":["chat"]}]"#.utf8)
        XCTAssertEqual(try UsageService.selectOrganization(data: data, cookie: "lastActiveOrg=team; other=ignored").uuid, "team")
        XCTAssertEqual(try UsageService.selectOrganization(data: data, cookie: "lastActiveOrg=deleted").uuid, "personal")
        XCTAssertThrowsError(try UsageService.selectOrganization(data: Data("[]".utf8), cookie: ""))
    }

    func testStreamingTokenSnapshotsCountMaximumNotFirstOrSum() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsage-stream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
        var lines: [String] = []
        for (index, output) in [5, 20, 10, 20].enumerated() {
            let timestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(index) - 60))
            lines.append("""
            {"requestId":"r","timestamp":"\(timestamp)","message":{"id":"m","usage":{"input_tokens":10,"output_tokens":\(output),"cache_read_input_tokens":30}}}
            """)
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: root.appendingPathComponent("session.jsonl"))
        try Data(lines[1].utf8).write(to: root.appendingPathComponent("duplicate.jsonl"))
        let usage = await ClaudeLocalTokenUsageService.fetch(now: now, rootURL: root)
        XCTAssertEqual(usage?.todayTokens, 60)
        XCTAssertEqual(ClaudeLocalTokenUsageService.projectsURL(environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-profile"]).path, "/tmp/claude-profile/projects")
    }
}
