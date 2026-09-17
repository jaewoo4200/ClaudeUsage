import XCTest
import SwiftUI
@testable import ClaudeUsage

final class TodayTokenTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-17T05:00:00Z")!

    func testCombinedTotalRequiresBothProvidersAndPreservesRealZero() {
        XCTAssertEqual(summary(.available(0), .available(0)).total, 0)
        XCTAssertEqual(summary(.available(12_400), .available(2_875_919)).total, 2_888_319)
        XCTAssertNil(summary(.available(0), .pending).total)
        XCTAssertNil(summary(.disabled, .available(0)).total)
        XCTAssertNil(summary(.pending, .unavailable).reportedTotal)
        XCTAssertEqual(summary(.available(123), .pending).reportedTotal, 123)
    }

    @MainActor
    func testMissingDataIsNotLabeledAsZero() {
        let language = LanguageStore.shared
        let previous = language.current
        defer { language.current = previous }
        language.current = .ko
        XCTAssertEqual(summary(.available(0), .pending).displayTotal, "집계 대기")
        XCTAssertEqual(summary(.available(0), .available(0)).displayTotal, "0")
        XCTAssertEqual(summary(.disabled, .available(2_875_919)).displayTotal, "일부 2.9M")
        XCTAssertEqual(summary(.disabled, .unavailable).displayTotal, "조회 불가")
    }

    func testServerBucketsUseRequestedCalendarDayWithoutFallingBackToYesterday() {
        var korea = Calendar(identifier: .gregorian)
        korea.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var utc = korea
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let shortlyAfterMidnight = ISO8601DateFormatter().date(from: "2026-09-16T15:05:00Z")!
        let activity = OpenAITokenActivity(summary: nil, dailyBuckets: [
            .init(startDate: "2026-09-16", tokens: 21_205_852),
            .init(startDate: "2026-09-17", tokens: 0)
        ])
        XCTAssertEqual(activity.tokens(on: shortlyAfterMidnight, calendar: korea), 0)
        XCTAssertEqual(activity.tokens(on: shortlyAfterMidnight, calendar: utc), 21_205_852)
        let delayed = OpenAITokenActivity(summary: nil, dailyBuckets: [activity.dailyBuckets[0]])
        XCTAssertNil(delayed.tokens(on: shortlyAfterMidnight, calendar: korea))
        XCTAssertEqual(delayed.latestBucket(before: shortlyAfterMidnight, calendar: korea)?.tokens, 21_205_852)
    }

    func testLatestReportRejectsInvalidAndFutureBuckets() {
        let activity = OpenAITokenActivity(summary: nil, dailyBuckets: [
            .init(startDate: "2026-09-16", tokens: 123),
            .init(startDate: "2026-09-15", tokens: 456),
            .init(startDate: "2026-09-17", tokens: -1),
            .init(startDate: "2026-09-18", tokens: 999),
            .init(startDate: "2026-02-30", tokens: 999)
        ])
        XCTAssertNil(activity.tokens(on: now))
        XCTAssertEqual(activity.latestBucket(before: now)?.startDate, "2026-09-16")
    }

    func testNullOrMissingDailyBucketsRemainUnknown() throws {
        for json in ["{}", "{\"dailyUsageBuckets\":null}"] {
            let data = try CodexAppServerUsageService.decodeFixture(
                rateLimitsJSON: Data("{\"rateLimits\":null}".utf8),
                tokenUsageJSON: Data(json.utf8)
            )
            XCTAssertNotNil(data.tokenActivity)
            XCTAssertTrue(try XCTUnwrap(data.tokenActivity).dailyBuckets.isEmpty)
            XCTAssertNil(data.tokenActivity?.tokens(on: now))
        }
        let activity = try JSONDecoder().decode(OpenAITokenActivity.self, from: Data("{\"dailyBuckets\":null}".utf8))
        XCTAssertNil(activity.tokens(on: now))
    }

    func testClaudeCacheExpiresAtLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let before = ISO8601DateFormatter().date(from: "2026-09-16T14:59:00Z")!
        let after = before.addingTimeInterval(120)
        let cache = ClaudeLocalTokenUsage(todayTokens: 1_234, updatedAt: before)
        XCTAssertEqual(cache.tokens(on: before, calendar: calendar), 1_234)
        XCTAssertNil(cache.tokens(on: after, calendar: calendar))
    }

    @MainActor
    func testViewModelKeepsDelayedServerDataSeparateFromToday() {
        let vm = UsageViewModel(autoStart: false)
        vm.claudeLocalTokenUsage = .init(todayTokens: 0, updatedAt: now)
        vm.openAIState = .loaded(usage(buckets: [.init(startDate: "2026-09-16", tokens: 21_205_852)]))
        let value = vm.todayTokenSummary(localCollectionEnabled: true, now: now)
        XCTAssertEqual(value.claude, .available(0))
        XCTAssertEqual(value.codex, .pending)
        XCTAssertNil(value.total)
        XCTAssertEqual(value.latestCodexBucket?.tokens, 21_205_852)
        XCTAssertNil(vm.historySnapshot(includingSpark: false, now: now).todayTokens)
    }

    @MainActor
    func testViewModelExcludesDisabledOrPreviousDayLocalValues() {
        let vm = UsageViewModel(autoStart: false)
        vm.claudeLocalTokenUsage = .init(todayTokens: 1_234, updatedAt: now.addingTimeInterval(-86_400))
        XCTAssertEqual(vm.todayTokenSummary(localCollectionEnabled: true, now: now).claude, .pending)
        XCTAssertNil(vm.historySnapshot(includingSpark: false, now: now).claudeTodayTokens)
        vm.claudeLocalTokenUsage = .init(todayTokens: 1_234, updatedAt: now)
        XCTAssertEqual(vm.todayTokenSummary(localCollectionEnabled: false, now: now).claude, .disabled)
        vm.openAIState = .unavailable
        XCTAssertEqual(vm.todayTokenSummary(localCollectionEnabled: true, now: now).codex, .unavailable)
    }

    @MainActor
    func testTrendDoesNotCountNewlyArrivedDailyTotalsAsRecentUsage() {
        XCTAssertNil(trend([(0, nil), (0, 2_875_919)]).recentTokenDelta)
        XCTAssertNil(trend([(0, 2_875_919), (0, nil)]).recentTokenDelta)
        XCTAssertNil(trend([(0, 100), (0, nil), (0, 200)]).recentTokenDelta)
        XCTAssertNil(trend([(100, 100), (50, 200)]).recentTokenDelta)
    }

    @MainActor
    func testTrendUsesOnlyConsistentlyAvailableProviders() {
        XCTAssertEqual(trend([(100, 200), (150, 300)]).recentTokenDelta, 150)
        XCTAssertEqual(trend([(100, nil), (150, nil)]).recentTokenDelta, 50)
        XCTAssertNil(trend([(nil, nil), (nil, nil)]).recentTokenDelta)
    }

    @MainActor
    func testTrendDoesNotBridgeMidnight() {
        let midnight = Calendar.current.startOfDay(for: now)
        XCTAssertNil(trend([(0, 0), (100, 100)], endingAt: midnight.addingTimeInterval(30)).recentTokenDelta)
    }

    @MainActor
    func testTokenDetailsRenderPendingAndMillionCountsInBothLanguagesAndThemes() throws {
        let vm = UsageViewModel(autoStart: false)
        let settings = AppSettings()
        let theme = ThemeStore()
        let language = LanguageStore.shared
        let previous = (settings.usageHistoryEnabled, theme.current, language.current)
        defer {
            settings.usageHistoryEnabled = previous.0
            theme.current = previous.1
            language.current = previous.2
        }
        settings.usageHistoryEnabled = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        vm.claudeLocalTokenUsage = .init(todayTokens: 0, updatedAt: Date())
        vm.openAIState = .loaded(usage(buckets: [.init(startDate: formatter.string(from: yesterday), tokens: 21_205_852)]))
        for kind in ThemeKind.allCases {
            theme.current = kind
            for lang in AppLanguage.allCases {
                language.current = lang
                let root = TodayTokensView().environmentObject(vm).environmentObject(settings)
                    .environmentObject(theme).environmentObject(language)
                let host = NSHostingView(rootView: root)
                host.appearance = NSAppearance(named: .aqua)
                host.layoutSubtreeIfNeeded()
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 310, accuracy: 1)
                XCTAssertGreaterThan(host.fittingSize.height, 150)
                XCTAssertLessThan(host.fittingSize.height, 360)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 1_000)
                try png.write(to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-tokens-\(kind.rawValue)-\(lang.rawValue).png"))
            }
        }
    }

    private func summary(_ claude: TodayTokenState, _ codex: TodayTokenState) -> TodayTokenSummary {
        TodayTokenSummary(claude: claude, codex: codex, latestCodexBucket: nil)
    }

    private func usage(buckets: [OpenAITokenDailyBucket]) -> OpenAIUsageData {
        OpenAIUsageData(planType: "pro", rateLimit: nil, codeReviewRateLimit: nil, additionalRateLimits: [],
                        tokenActivity: .init(summary: nil, dailyBuckets: buckets))
    }

    @MainActor
    private func trend(_ values: [(Int64?, Int64?)], endingAt date: Date? = nil) -> UsageTrend {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        let end = date ?? now
        for (index, value) in values.enumerated() {
            let snapshot = UsageHistorySnapshot(
                claudeFiveHour: 20, claudeWeekly: nil, claudeModelMaximum: nil,
                openAIFiveHour: 30, openAIWeekly: nil, openAIModelMaximum: nil,
                claudeTodayTokens: value.0, openAITodayTokens: value.1
            )
            store.record(snapshot, at: end.addingTimeInterval(Double(index - values.count + 1) * 300), force: true)
        }
        return store.trend(now: end)
    }
}
