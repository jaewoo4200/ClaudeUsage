import XCTest
@testable import ClaudeUsage

final class UsageBreakdownTests: XCTestCase {
    static var fixture: Data {
        let reset = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(280_000))
        let sessionReset = ISO8601DateFormatter.shared.string(from: Date().addingTimeInterval(14_900))
        return Data("""
        {
          "five_hour": {"utilization": 5, "resets_at": "\(sessionReset)"},
          "seven_day": {"utilization": 35, "resets_at": "\(reset)"},
          "limits": [{"scope": {"model": {"display_name": "Fable"}}, "utilization": 26}],
          "seven_day_breakdown": {
            "as_of": "2026-09-17T05:22:10.010806+00:00",
            "window_started_at": "2026-09-13T22:59:59Z",
            "rows": [
              {"key": "claude_code", "display_name": "Claude Code", "percent": 90},
              {"key": "chat", "display_name": "Chats", "percent": 9},
              {"key": "cowork", "display_name": "Cowork", "percent": 1},
              {"key": "other", "display_name": "Other", "percent": 0}
            ]
          }
        }
        """.utf8)
    }

    func testBreakdownIsCompositionAndFableKeepsItsOwnQuota() throws {
        let usage = try UsageData.decode(from: Self.fixture)
        XCTAssertEqual(usage.sevenDay?.utilization, 35)
        XCTAssertEqual(usage.fiveHour?.utilization, 5)
        XCTAssertEqual(usage.sevenDayFable?.utilization, 26)
        XCTAssertEqual(usage.sevenDayFable?.resetsAt, usage.sevenDay?.resetsAt)
        let breakdown = try XCTUnwrap(usage.sevenDayBreakdown)
        XCTAssertEqual(breakdown.rows.map(\.percent), [90, 9, 1, 0])
        XCTAssertNotNil(breakdown.asOf)
        XCTAssertNotNil(breakdown.windowStartedAt)
        XCTAssertTrue(usage.additionalSevenDayWindows.isEmpty)
        let roundtrip = try UsageData.decode(from: JSONEncoder().encode(usage))
        XCTAssertEqual(roundtrip.sevenDayBreakdown, breakdown)
    }

    func testDynamicCountersRequireRealUtilizationButPreserveZero() throws {
        let usage = try UsageData.decode(from: Data("""
        {
          "seven_day_metadata": {"rows": []},
          "seven_day_empty": {},
          "seven_day_null": null,
          "seven_day_bad": {"utilization": "unknown"},
          "seven_day_negative": {"utilization": -1},
          "seven_day_new_model": {"utilization": 0},
          "seven_day_next_model": {"utilization": 12.5}
        }
        """.utf8))
        XCTAssertEqual(Set(usage.additionalSevenDayWindows.keys), ["seven_day_new_model", "seven_day_next_model"])
        XCTAssertEqual(usage.additionalSevenDayWindows["seven_day_new_model"]?.utilization, 0)
    }

    func testMalformedBreakdownDoesNotDiscardOtherUsage() throws {
        for breakdown in ["null", "{}", "[]", "{\"rows\":null}"] {
            let usage = try UsageData.decode(from: Data("""
            {"seven_day":{"utilization":35},"seven_day_breakdown":\(breakdown)}
            """.utf8))
            XCTAssertEqual(usage.sevenDay?.utilization, 35)
            XCTAssertNil(usage.sevenDayBreakdown)
            XCTAssertTrue(usage.additionalSevenDayWindows.isEmpty)
        }
    }

    func testInvalidRowsAreSkippedAndUnknownServicesRetained() throws {
        let usage = try UsageData.decode(from: Data("""
        {"seven_day_breakdown":{"rows":[
          {"key":"claude_code","percent":0},
          {"key":"claude_code","percent":20},
          {"key":"future_service","display_name":"New service","percent":42.5},
          {"key":"missing_percent"},
          {"key":"negative","percent":-3},
          {"key":"too_high","percent":101},
          {"key":"","percent":3},
          null, false, "invalid"
        ]}}
        """.utf8))
        XCTAssertEqual(usage.sevenDayBreakdown?.rows.map(\.key), ["claude_code", "future_service"])
        XCTAssertEqual(usage.sevenDayBreakdown?.rows.last?.displayName, "New service")
        XCTAssertEqual(usage.sevenDayBreakdown?.rows.last?.percent, 42.5)
    }

    func testModelNamedInsideBreakdownIsNotAUsageWindow() throws {
        let usage = try UsageData.decode(from: Data("""
        {"seven_day":{"utilization":35},"seven_day_breakdown":{"rows":[
          {"key":"fable","display_name":"Fable","percent":90}
        ]}}
        """.utf8))
        XCTAssertNil(usage.sevenDayFable)
        XCTAssertTrue(usage.additionalSevenDayWindows.isEmpty)
    }

    @MainActor
    func testCompositionDoesNotBecomeQuotaHistoryOrPetPressure() throws {
        let vm = UsageViewModel(autoStart: false)
        vm.state = .loaded(AccountSnapshot(
            organization: Organization(uuid: "fixture", name: nil, capabilities: [], rateLimitTier: nil),
            usage: try UsageData.decode(from: Self.fixture)
        ))
        XCTAssertEqual(vm.claudeDisplayMetrics.map(\.id), ["five_hour", "seven_day", "seven_day_fable"])
        XCTAssertEqual(vm.claudeWeeklyBreakdown?.rows.first?.percent, 90)
        let snapshot = vm.historySnapshot(includingSpark: false)
        XCTAssertEqual(snapshot.pressure, 35)
        XCTAssertFalse(snapshot.claudeModelCounters.contains { $0.id == "seven_day_breakdown" })

        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: historyURL) }
        try Data("""
        [{"timestamp":0,"claudeWeekly":35,"claudeModelMaximum":26,"claudeModelCounters":[
          {"id":"seven_day_breakdown","label":"Breakdown","utilization":0},
          {"id":"seven_day_fable","label":"Claude Fable","utilization":26}
        ]}]
        """.utf8).write(to: historyURL)
        let history = UsageHistoryStore(fileURL: historyURL)
        XCTAssertEqual(history.samples.first?.claudeModelCounters?.map(\.id), ["seven_day_fable"])
        XCTAssertEqual(history.samples.first?.snapshot.pressure, 35)
    }
}
