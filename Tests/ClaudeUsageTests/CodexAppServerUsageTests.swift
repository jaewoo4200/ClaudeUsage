import XCTest
@testable import ClaudeUsage

final class CodexAppServerUsageTests: XCTestCase {
    func testFindsNestedAndLegacyDesktopExecutables() {
        for directory in ["/Applications", "/Users/demo/Applications"] {
            for app in ["ChatGPT.app", "Codex.app"] {
                for relativePath in ["codex-cli/CodexCLI.app/Contents/MacOS/codex", "codex"] {
                    let expected = "\(directory)/\(app)/Contents/Resources/\(relativePath)"
                    XCTAssertEqual(resolveExecutable(available: [expected])?.path, expected)
                }
            }
        }
    }

    func testPrefersNestedBundleOverLegacyAndStandaloneExecutables() {
        let nested = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        let legacy = "/Applications/ChatGPT.app/Contents/Resources/codex"
        XCTAssertEqual(resolveExecutable(available: [nested, legacy, "/opt/homebrew/bin/codex"])?.path, nested)
        XCTAssertEqual(resolveExecutable(available: [legacy, "/opt/homebrew/bin/codex"])?.path, legacy)
    }

    func testFallsBackToExistingStandaloneInstallLocations() {
        for path in ["/Users/demo/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            XCTAssertEqual(resolveExecutable(available: [path])?.path, path)
        }
    }

    func testUnavailableWhenNoCandidateIsExecutable() {
        XCTAssertNil(resolveExecutable(available: []))
    }

    func testRediscoversExecutableAfterDesktopUpdate() {
        let oldPath = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let newPath = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        XCTAssertEqual(resolveExecutable(available: [oldPath])?.path, oldPath)
        XCTAssertEqual(resolveExecutable(available: [newPath])?.path, newPath)
    }

    func testResetCreditDetailsCanBeNullOrMissingWithoutLosingUsage() throws {
        for details in [",\"credits\":null", ""] {
            let json = Data("""
            {"rateLimits":{"limitId":"codex","planType":"pro",
              "primary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1800000000}},
             "rateLimitResetCredits":{"availableCount":2\(details)}}
            """.utf8)
            let usage = try CodexAppServerUsageService.decodeFixture(rateLimitsJSON: json, tokenUsageJSON: nil)
            XCTAssertEqual(usage.rateLimit?.primaryWindow?.usedPercent, 17)
            XCTAssertEqual(usage.counters.first?.kind, .weekly)
            XCTAssertEqual(usage.rateLimitResetCredits?.usableCount(), 2)
            XCTAssertNil(usage.rateLimitResetCredits?.earliestExpiry())
        }
    }

    func testLiveInstalledCodexUsageWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CLAUDEUSAGE_LIVE_CODEX_TEST"] == "1" else {
            throw XCTSkip("Opt in with TEST_RUNNER_CLAUDEUSAGE_LIVE_CODEX_TEST=1 for a signed-in local account.")
        }
        XCTAssertNotNil(CodexAppServerUsageService.executableURL())
        let usage = try await CodexAppServerUsageService.fetchUsage()
        XCTAssertFalse(usage.counters.isEmpty)
        for counter in usage.counters {
            XCTAssertTrue(counter.window.usedPercent.isFinite)
            XCTAssertGreaterThanOrEqual(counter.window.usedPercent, 0)
            XCTAssertNotNil(counter.window.resetDate())
        }
        print("[Codex live check] Received \(usage.counters.count) quota windows; token activity: \(usage.tokenActivity != nil)")
    }

    private func resolveExecutable(available: Set<String>) -> URL? {
        CodexAppServerUsageService.executableURL(
            homeDirectory: URL(fileURLWithPath: "/Users/demo"),
            isExecutableFile: { available.contains($0) }
        )
    }

    func testMapsDocumentedRateLimitsAndTokenBuckets() throws {
        let rateLimits = Data(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "limitName": null,
                "primary": {"usedPercent": 28, "windowDurationMins": 300, "resetsAt": 1783634265},
                "secondary": {"usedPercent": 32, "windowDurationMins": 10080, "resetsAt": 1783904355},
                "planType": "pro"
              },
              "rateLimitsByLimitId": {
                "codex": {
                  "limitId": "codex",
                  "limitName": null,
                  "primary": {"usedPercent": 28, "windowDurationMins": 300, "resetsAt": 1783634265},
                  "secondary": {"usedPercent": 32, "windowDurationMins": 10080, "resetsAt": 1783904355},
                  "planType": "pro"
                },
                "gpt_5_6_sol": {
                  "limitId": "gpt_5_6_sol",
                  "limitName": "GPT-5.6-Sol",
                  "primary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1783634265},
                  "secondary": {"usedPercent": 6, "windowDurationMins": 10080, "resetsAt": 1783904355},
                  "planType": "pro"
                }
              },
              "rateLimitResetCredits": {
                "availableCount": 1,
                "credits": [
                  {
                    "id": "credit-available",
                    "resetType": "codexRateLimits",
                    "status": "available",
                    "grantedAt": 1781742787,
                    "expiresAt": 1784334787,
                    "title": "Full reset (Weekly + 5 hr)",
                    "description": "One free reset"
                  },
                  {
                    "id": "credit-used",
                    "resetType": "codexRateLimits",
                    "status": "consumed",
                    "grantedAt": 1781742787,
                    "expiresAt": 1784334787,
                    "title": "Full reset (Weekly + 5 hr)",
                    "description": "Already used"
                  }
                ]
              }
            }
            """.utf8
        )
        let tokenUsage = Data(
            """
            {
              "summary": {
                "lifetimeTokens": 1000000,
                "peakDailyTokens": 250000,
                "longestRunningTurnSec": 120,
                "currentStreakDays": 5,
                "longestStreakDays": 9
              },
              "dailyUsageBuckets": [
                {"startDate": "2026-07-10", "tokens": 123456}
              ]
            }
            """.utf8
        )

        let usage = try CodexAppServerUsageService.decodeFixture(
            rateLimitsJSON: rateLimits,
            tokenUsageJSON: tokenUsage
        )

        XCTAssertEqual(usage.planDisplayName, "Pro")
        XCTAssertEqual(usage.rateLimit?.primaryWindow?.usedPercent, 28)
        XCTAssertEqual(usage.rateLimit?.secondaryWindow?.limitWindowSeconds, 604_800)
        XCTAssertEqual(usage.additionalRateLimits.first?.limitName, "GPT-5.6-Sol")
        XCTAssertEqual(usage.tokenActivity?.dailyBuckets.first?.tokens, 123_456)
        XCTAssertEqual(usage.tokenActivity?.summary?.longestRunningTurnSeconds, 120)
        let resetCredits = try XCTUnwrap(usage.rateLimitResetCredits)
        let beforeExpiry = Date(timeIntervalSince1970: 1_784_000_000)
        XCTAssertEqual(resetCredits.availableCount, 1)
        XCTAssertEqual(resetCredits.usableCount(at: beforeExpiry), 1)
        XCTAssertEqual(resetCredits.usableCredits(at: beforeExpiry).first?.id, "credit-available")
        XCTAssertEqual(
            resetCredits.earliestExpiry(at: beforeExpiry),
            Date(timeIntervalSince1970: 1_784_334_787)
        )
        XCTAssertEqual(resetCredits.usableCount(at: Date(timeIntervalSince1970: 1_785_000_000)), 0)
    }
}
