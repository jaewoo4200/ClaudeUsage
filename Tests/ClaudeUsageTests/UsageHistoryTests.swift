import XCTest
@testable import ClaudeUsage

final class UsageHistoryTests: XCTestCase {
    func testClaudeLocalTokensUseTodayAndDeduplicateMessages() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-local-token-fixture", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        let today = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        let yesterday = ISO8601DateFormatter().string(from: now.addingTimeInterval(-25 * 60 * 60))
        let current = """
        {"requestId":"request-1","timestamp":"\(today)","message":{"id":"message-1","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
        """
        let old = """
        {"requestId":"request-2","timestamp":"\(yesterday)","message":{"id":"message-2","usage":{"input_tokens":999}}}
        """
        let fixture = [current, current, old].joined(separator: "\n")
        try Data(fixture.utf8).write(to: root.appendingPathComponent("session.jsonl"))

        let fetched = await ClaudeLocalTokenUsageService.fetch(now: now, rootURL: root)
        let usage = try XCTUnwrap(fetched)
        XCTAssertEqual(usage.todayTokens, 100)
    }

    @MainActor
    func testTrendUsesRecentSegmentAndTokenDelta() {
        let url = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-history-test.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.record(snapshot(pressure: 20, tokens: 1_000), at: now.addingTimeInterval(-3_600), force: true)
        store.record(snapshot(pressure: 28, tokens: 3_500), at: now, force: true)

        let trend = store.trend(now: now)
        XCTAssertEqual(trend.deltaPercent, 8)
        XCTAssertEqual(trend.percentPerHour, 8)
        XCTAssertEqual(trend.recentTokenDelta, 2_500)
        XCTAssertEqual(trend.points, [20, 28])
    }

    @MainActor
    func testResetStartsANewTrendSegmentAndRefreshesPet() {
        let url = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-history-reset-test.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.record(snapshot(pressure: 92, tokens: 10_000), at: now.addingTimeInterval(-1_800), force: true)
        store.record(snapshot(pressure: 8, tokens: 11_000), at: now.addingTimeInterval(-900), force: true)
        store.record(snapshot(pressure: 10, tokens: 12_000), at: now, force: true)

        let trend = store.trend(now: now)
        XCTAssertTrue(trend.resetDetected)
        XCTAssertEqual(trend.deltaPercent, 2)
        XCTAssertEqual(PetMood.resolve(snapshot: snapshot(pressure: 10, tokens: 12_000), trend: trend), .refreshed)
    }

    func testPetMoodUsesPressureAndBurnRate() {
        XCTAssertEqual(PetMood.resolve(snapshot: snapshot(pressure: 25, tokens: nil), trend: .empty), .calm)
        XCTAssertEqual(PetMood.resolve(snapshot: snapshot(pressure: 62, tokens: nil), trend: .empty), .focused)
        XCTAssertEqual(PetMood.resolve(snapshot: snapshot(pressure: 80, tokens: nil), trend: .empty), .sleepy)
        XCTAssertEqual(PetMood.resolve(snapshot: snapshot(pressure: 94, tokens: nil), trend: .empty), .tired)

        let fastTrend = UsageTrend(
            points: [20, 50],
            deltaPercent: 30,
            percentPerHour: 48,
            recentTokenDelta: nil,
            resetDetected: false
        )
        XCTAssertEqual(PetMood.resolve(snapshot: snapshot(pressure: 35, tokens: nil), trend: fastTrend), .tired)
    }

    @MainActor
    func testRecordingUsesFiveMinuteCadenceButCapturesReset() {
        let url = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-history-cadence-test.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageHistoryStore(fileURL: url, minimumSampleInterval: 300)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.record(snapshot(pressure: 40, tokens: 1_000), at: now, force: true)
        store.record(snapshot(pressure: 48, tokens: 5_000), at: now.addingTimeInterval(60))
        XCTAssertEqual(store.samples.count, 1)

        store.record(snapshot(pressure: 15, tokens: 5_500), at: now.addingTimeInterval(120))
        XCTAssertEqual(store.samples.count, 2)
    }

    @MainActor
    func testRefreshedMoodExpiresThirtyMinutesAfterReset() {
        let url = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-history-old-reset-test.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.record(snapshot(pressure: 90, tokens: nil), at: now.addingTimeInterval(-2_400), force: true)
        store.record(snapshot(pressure: 10, tokens: nil), at: now.addingTimeInterval(-2_100), force: true)
        store.record(snapshot(pressure: 12, tokens: nil), at: now, force: true)

        XCTAssertFalse(store.trend(now: now).resetDetected)
    }

    private func snapshot(pressure: Double, tokens: Int64?) -> UsageHistorySnapshot {
        UsageHistorySnapshot(
            claudeFiveHour: pressure,
            claudeWeekly: nil,
            claudeModelMaximum: nil,
            openAIFiveHour: nil,
            openAIWeekly: nil,
            openAIModelMaximum: nil,
            claudeTodayTokens: tokens,
            openAITodayTokens: nil
        )
    }
}
