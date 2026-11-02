import XCTest
@testable import ClaudeUsage

final class ClaudeUltraTests: XCTestCase {
    func testUltraRecognizesNewAndLegacyPlanIdentifiers() throws {
        for tier in ["ultra", "default_claude_ultra", "ULTRA", "max_20x", "default_claude_max_20x"] {
            let organization = Organization(uuid: "fixture", name: nil,
                                            capabilities: ["claude_max"], rateLimitTier: tier)
            XCTAssertEqual(organization.plan.displayName, "Ultra", tier)
            XCTAssertEqual(organization.plan.compactName, "ULTRA", tier)
        }
        XCTAssertEqual(Plan.parse(capabilities: ["chat", "CLAUDE_ULTRA"], rateLimitTier: nil).displayName, "Ultra")
        XCTAssertEqual(try JSONDecoder().decode(Plan.self, from: Data("\"max20x\"".utf8)).displayName, "Ultra")
    }

    func testOtherPlansAndTierPrecedenceArePreserved() {
        for (tier, plan) in [("max_5x", Plan.max5x), ("pro", .pro), ("team", .team), ("enterprise", .enterprise)] {
            XCTAssertEqual(Plan.parse(capabilities: ["claude_ultra"], rateLimitTier: tier), plan)
        }
        XCTAssertEqual(Plan.parse(capabilities: ["chat"], rateLimitTier: nil), .free)
        XCTAssertEqual(Plan.parse(capabilities: [], rateLimitTier: nil), .unknown)
    }

    @MainActor
    func testAbsentSessionWindowUsesWeeklyQuotaWithoutPlaceholder() throws {
        for session in ["", "\"five_hour\":null,", "\"five_hour\":{},", "\"five_hour\":{\"utilization\":\"unknown\"},"] {
            let vm = try model(session: session)
            XCTAssertEqual(vm.plan.displayName, "Ultra")
            XCTAssertNil(vm.snapshot?.usage.fiveHour)
            XCTAssertEqual(vm.claudeDisplayMetrics.map(\.id), ["seven_day", "seven_day_fable"])
            XCTAssertEqual(vm.claudeDisplayMetrics.map(\.utilization), [88, 64])
            XCTAssertTrue(vm.claudeDisplayMetrics.allSatisfy(\.isWeekly))
            XCTAssertEqual(vm.claudeDisplayMetrics[1].resetsAt, vm.sevenDayResetsAt)
            XCTAssertEqual(vm.claudePrimaryUtilization, 88)
            XCTAssertEqual(vm.claudeMenuBarValue, "88%")
        }
    }

    @MainActor
    func testTemporarySessionLimitIsKeptEvenAtZeroWithoutReset() throws {
        for tier in ["ultra", "max_20x", "pro", "max_5x"] {
            let vm = try model(session: "\"five_hour\":{\"utilization\":0,\"resets_at\":null},", tier: tier)
            XCTAssertEqual(vm.claudeDisplayMetrics.map(\.id), ["five_hour", "seven_day", "seven_day_fable"])
            XCTAssertEqual(vm.claudePrimaryUtilization, 0)
            XCTAssertEqual(vm.claudeMenuBarValue, "0%")
            XCTAssertFalse(vm.claudeDisplayMetrics[0].isWeekly)
        }
    }

    @MainActor
    func testSessionLimitCanDisappearAndReturnOnRefresh() throws {
        let vm = try model(session: "\"five_hour\":{\"utilization\":37},")
        XCTAssertEqual(vm.claudeMenuBarValue, "37%")
        vm.state = try model(session: "").state
        XCTAssertEqual(vm.claudeMenuBarValue, "88%")
        XCTAssertEqual(vm.claudeDisplayMetrics.count, 2)
        vm.state = try model(session: "\"five_hour\":{\"utilization\":12},").state
        XCTAssertEqual(vm.claudeMenuBarValue, "12%")
        XCTAssertEqual(vm.claudeDisplayMetrics.count, 3)
    }

    @MainActor
    func testMissingQuotasDoNotBecomeZeroUsage() throws {
        let vm = try model(session: "")
        vm.state = .loaded(AccountSnapshot(organization: try XCTUnwrap(vm.snapshot?.organization),
                                          usage: try UsageData.decode(from: Data("{}".utf8))))
        XCTAssertTrue(vm.claudeDisplayMetrics.isEmpty)
        XCTAssertNil(vm.claudePrimaryUtilization)
        XCTAssertEqual(vm.claudeMenuBarValue, "—")
        vm.state = .loading
        XCTAssertEqual(vm.claudeMenuBarValue, "…")
        vm.state = .error("fixture")
        XCTAssertEqual(vm.claudeMenuBarValue, "!")
        vm.state = .needsLogin
        XCTAssertEqual(vm.claudeMenuBarValue, "—")
    }

    @MainActor
    func testNoWeeklyQuotaIsInventedForSessionOnlyResponse() throws {
        let vm = try model(session: "")
        vm.state = .loaded(AccountSnapshot(organization: try XCTUnwrap(vm.snapshot?.organization),
                                          usage: UsageData(fiveHour: .init(utilization: 25, resetsAt: nil))))
        XCTAssertEqual(vm.claudeDisplayMetrics.map(\.id), ["five_hour"])
        XCTAssertEqual(vm.claudeMenuBarValue, "25%")
    }

    @MainActor
    func testHistoryAndMenuPressureUseActualWeeklyWindow() throws {
        let settings = AppSettings.shared
        let original = (settings.showClaude, settings.showCodex)
        defer {
            settings.showClaude = true
            settings.showCodex = original.1
            settings.showClaude = original.0
        }
        settings.showClaude = true
        settings.showCodex = false
        let vm = try model(session: "")
        XCTAssertEqual(vm.highestPrimaryUtilization, 88)
        let snapshot = vm.historySnapshot(includingSpark: false)
        XCTAssertNil(snapshot.claudeFiveHour)
        XCTAssertEqual(snapshot.claudeWeekly, 88)
        XCTAssertEqual(snapshot.claudeModelMaximum, 64)
        XCTAssertEqual(snapshot.pressure, 88)
    }

    @MainActor
    func testRemovingSessionLimitDoesNotNotifyAReset() throws {
        let vm = try model(session: "\"five_hour\":{\"utilization\":75,\"resets_at\":\"2026-11-03T01:00:00.000Z\"},")
        var policy = UsageAlertPolicy()
        let now = Date()
        _ = policy.success(provider: .claude, metrics: vm.claudeDisplayMetrics, now: now,
                           usageEnabled: true, resetEnabled: true)
        vm.state = try model(session: "").state
        let alerts = policy.success(provider: .claude, metrics: vm.claudeDisplayMetrics,
                                    now: now.addingTimeInterval(60), usageEnabled: true, resetEnabled: true)
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertNil(policy.counters["claude/five_hour"])
        XCTAssertEqual(policy.counters["claude/seven_day"]?.utilization, 88)
    }

    @MainActor
    private func model(session: String, tier: String = "max_20x") throws -> UsageViewModel {
        let vm = UsageViewModel(autoStart: false)
        vm.state = .loaded(AccountSnapshot(
            organization: .init(uuid: "fixture", name: nil, capabilities: ["claude_max"], rateLimitTier: tier),
            usage: try UsageData.decode(from: Data("""
            {\(session)
              "seven_day":{"utilization":88,"resets_at":"2026-11-04T00:00:00.000Z"},
              "seven_day_fable":{"utilization":64}
            }
            """.utf8))
        ))
        return vm
    }
}
