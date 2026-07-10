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

    func testMimoSensitivityChangesFocusedThreshold() {
        let current = snapshot(pressure: 42, tokens: nil)

        XCTAssertEqual(
            PetMood.resolve(snapshot: current, trend: .empty, sensitivity: .responsive),
            .focused
        )
        XCTAssertEqual(
            PetMood.resolve(snapshot: current, trend: .empty, sensitivity: .balanced),
            .calm
        )
        XCTAssertEqual(
            PetMood.resolve(snapshot: current, trend: .empty, sensitivity: .relaxed),
            .calm
        )
    }

    func testPressureUsesHighestIndividualModelCounter() {
        let snapshot = UsageHistorySnapshot(
            claudeFiveHour: 41,
            claudeWeekly: 23,
            claudeModelMaximum: 43,
            openAIFiveHour: 32,
            openAIWeekly: 8,
            openAIModelMaximum: nil,
            claudeTodayTokens: nil,
            openAITodayTokens: nil,
            claudeModelCounters: [
                UsageHistoryCounter(id: "seven_day_fable", label: "Claude Fable", utilization: 43)
            ]
        )

        XCTAssertEqual(snapshot.pressure, 43)
        XCTAssertEqual(snapshot.pressureSource?.id, "seven_day_fable")
        XCTAssertEqual(snapshot.pressureSource?.provider, .claude)
    }

    func testMimoAnimationModesUseAdaptiveCadence() {
        XCTAssertEqual(MimoAnimationMode.automatic.updateInterval(for: .calm), 1.4)
        XCTAssertEqual(MimoAnimationMode.automatic.updateInterval(for: .focused), 0.45)
        XCTAssertEqual(MimoAnimationMode.lively.updateInterval(for: .calm), 0.25)
        XCTAssertNil(MimoAnimationMode.still.updateInterval(for: .focused))
        XCTAssertEqual(MimoAnimationMode.automatic.transitionDuration(for: .calm), 0.22)
        XCTAssertEqual(MimoAnimationMode.lively.transitionDuration(for: .calm), 0.16)
    }

    func testHistoryDashboardSummaryRespectsProviderScope() {
        let first = UsageHistorySample(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            snapshot: UsageHistorySnapshot(
                claudeFiveHour: 80,
                claudeWeekly: 20,
                claudeModelMaximum: nil,
                openAIFiveHour: 35,
                openAIWeekly: 10,
                openAIModelMaximum: nil,
                claudeTodayTokens: nil,
                openAITodayTokens: nil
            )
        )
        let second = UsageHistorySample(
            timestamp: Date(timeIntervalSince1970: 1_800_000_300),
            snapshot: UsageHistorySnapshot(
                claudeFiveHour: 50,
                claudeWeekly: 20,
                claudeModelMaximum: nil,
                openAIFiveHour: 40,
                openAIWeekly: 10,
                openAIModelMaximum: nil,
                claudeTodayTokens: nil,
                openAITodayTokens: nil
            )
        )

        XCTAssertEqual(UsageHistoryDashboardView.pressure(in: second, scope: .claude), 50)
        XCTAssertEqual(UsageHistoryDashboardView.pressure(in: second, scope: .codex), 40)
        XCTAssertEqual(UsageHistoryDashboardView.detectedResetCount([first, second], scope: .claude), 1)
        XCTAssertEqual(UsageHistoryDashboardView.detectedResetCount([first, second], scope: .codex), 0)
    }

    @MainActor
    func testHistoryPersistsModelCountersAndLoadsLegacySamples() throws {
        let url = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-history-schema-test.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = UsageHistoryCounter(
            id: "seven_day_fable",
            label: "Claude Fable",
            utilization: 47
        )

        store.record(
            UsageHistorySnapshot(
                claudeFiveHour: 30,
                claudeWeekly: 20,
                claudeModelMaximum: 47,
                openAIFiveHour: nil,
                openAIWeekly: nil,
                openAIModelMaximum: nil,
                claudeTodayTokens: nil,
                openAITodayTokens: nil,
                claudeModelCounters: [model]
            ),
            at: now,
            force: true
        )

        let reloaded = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        XCTAssertEqual(reloaded.samples.first?.claudeModelCounters, [model])

        let legacyJSON = """
        [{"timestamp":0,"claudeFiveHour":12,"claudeWeekly":8}]
        """
        try Data(legacyJSON.utf8).write(to: url, options: .atomic)
        let legacy = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        XCTAssertEqual(legacy.samples.first?.snapshot.pressure, 12)
        XCTAssertEqual(legacy.samples.first?.snapshot.claudeModelCounters, [])
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
