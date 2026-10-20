import XCTest
import SwiftUI
@testable import ClaudeUsage

final class NotificationAndUpdateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBrowserLoginAcceptsOnlyClaudeSessionValue() {
        let value = "sk-ant-sid01-" + String(repeating: "example0_", count: 8)
        XCTAssertEqual(BrowserSession.cookie(from: value), "sessionKey=" + value)
        XCTAssertEqual(BrowserSession.cookie(from: "  sessionKey=" + value + "\n"), "sessionKey=" + value)
        for input in ["", "sk-ant-api03-secret", "eyJhbGci", "sessionKey=", value + "; other=secret",
                      value + "\r\nX-Header: injected", "curl https://claude.ai", "google-token"] {
            XCTAssertNil(BrowserSession.cookie(from: input))
        }
        XCTAssertNil(BrowserSession.cookie(from: value + String(repeating: "x", count: 4096)))
    }

    func testGoogleNavigationRequiresBrowserWithoutMatchingLookalikeHosts() {
        XCTAssertTrue(BrowserSession.needsExternalBrowser(URL(string: "https://accounts.google.com/o/oauth2/auth")!))
        XCTAssertFalse(BrowserSession.needsExternalBrowser(URL(string: "https://accounts.google.com.example.org/auth")!))
        XCTAssertFalse(BrowserSession.needsExternalBrowser(URL(string: "https://claude.ai/login")!))
    }

    func testSessionRequestsCannotRedirectToAnotherOrigin() {
        XCTAssertTrue(ClaudeUsageRedirectPolicy.permits(URL(string: "https://claude.ai/api/organizations")))
        for value in ["http://claude.ai/api", "https://claude.ai.evil.example/api", "https://example.org/api",
                      "https://claude.ai:9443/api", "https://user:password@claude.ai/api"] {
            XCTAssertFalse(ClaudeUsageRedirectPolicy.permits(URL(string: value)))
        }
        XCTAssertFalse(ClaudeUsageRedirectPolicy.permits(nil))
    }

    @MainActor
    func testLoginAndNotificationSettingsRenderInBothLanguages() throws {
        let language = LanguageStore.shared
        let originalLanguage = language.current
        defer { language.current = originalLanguage }
        let notifications = UsageNotifications(client: FakeNotificationClient(),
                                               defaults: UserDefaults(suiteName: "notification-render-tests")!)
        for lang in AppLanguage.allCases {
            language.current = lang
            let root = HStack(alignment: .top, spacing: 16) {
                BrowserSessionLoginView(onCookies: { _ in }, onCancel: {})
                NotificationSettingsRow(notifications: notifications)
                    .environmentObject(AppSettings())
                    .environmentObject(ThemeStore())
                    .frame(width: 380)
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: root)
            host.appearance = NSAppearance(named: .aqua)
            let size = host.fittingSize
            XCTAssertLessThanOrEqual(size.width, 930)
            XCTAssertLessThanOrEqual(size.height, 550)
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-login-notifications-\(lang.rawValue).png"))
        }
    }

    private func metric(_ usage: Double, reset: Date? = nil) -> UsageDisplayMetric {
        UsageDisplayMetric(id: "five_hour", title: "5-hour", utilization: usage,
                           resetsAt: reset, isWeekly: false)
    }

    func testThresholdsAreIndependentAndPersistAcrossRestarts() throws {
        var policy = UsageAlertPolicy()
        func observe(_ percent: Double, provider: AlertProvider = .claude) -> [UsageAlert] {
            policy.success(provider: provider, metrics: [metric(percent, reset: now.addingTimeInterval(1800))],
                           now: now, usageEnabled: true, resetEnabled: true)
        }
        XCTAssertTrue(observe(69).isEmpty)
        XCTAssertEqual(observe(70).map(\.kind), [.warning])
        XCTAssertTrue(observe(80).isEmpty)
        policy = try JSONDecoder().decode(UsageAlertPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertTrue(observe(80).isEmpty)
        XCTAssertEqual(observe(92).map(\.kind), [.critical])
        XCTAssertTrue(observe(100).isEmpty)
        XCTAssertEqual(observe(95, provider: .codex).map(\.kind), [.critical])
    }

    func testConfirmedResetRearmsWarningsAndNeverSchedulesFromCountdownAlone() {
        var policy = UsageAlertPolicy()
        let expired = now.addingTimeInterval(-5)
        _ = policy.success(provider: .claude, metrics: [metric(95, reset: expired)],
                           now: now.addingTimeInterval(-60), usageEnabled: true, resetEnabled: true)
        XCTAssertTrue(policy.success(provider: .claude, metrics: [metric(95, reset: expired)],
                                     now: now, usageEnabled: true, resetEnabled: true).isEmpty)
        let reset = now.addingTimeInterval(18_000)
        let alerts = policy.success(provider: .claude, metrics: [metric(1, reset: reset)],
                                    now: now, usageEnabled: true, resetEnabled: true)
        XCTAssertEqual(alerts.map(\.kind), [.reset])
        XCTAssertEqual(policy.success(provider: .claude, metrics: [metric(71, reset: reset)],
                                      now: now, usageEnabled: true, resetEnabled: true).map(\.kind), [.warning])
    }

    func testResetAfterLongOfflineGapIsNotAnnouncedAsRecent() {
        var policy = UsageAlertPolicy()
        _ = policy.success(provider: .codex, metrics: [metric(90, reset: now.addingTimeInterval(-100))],
                           now: now.addingTimeInterval(-86_400), usageEnabled: true, resetEnabled: true)
        XCTAssertTrue(policy.success(provider: .codex, metrics: [metric(1, reset: now.addingTimeInterval(18_000))],
                                     now: now, usageEnabled: true, resetEnabled: true).isEmpty)
    }

    func testDisabledWarningDoesNotConsumeThresholdAndForgetRemovesProvider() {
        var policy = UsageAlertPolicy()
        XCTAssertTrue(policy.success(provider: .claude, metrics: [metric(90)], now: now,
                                     usageEnabled: false, resetEnabled: false).isEmpty)
        XCTAssertEqual(policy.success(provider: .claude, metrics: [metric(90)], now: now,
                                      usageEnabled: true, resetEnabled: false).map(\.kind), [.critical])
        policy.forget(.claude)
        XCTAssertTrue(policy.counters.isEmpty)
        XCTAssertTrue(policy.failures.isEmpty)
    }

    func testTransientFailureRequiresThreeAttemptsAndRecoveryRearms() {
        var policy = UsageAlertPolicy()
        XCTAssertTrue(policy.failure(provider: .codex, loginRequired: false).isEmpty)
        XCTAssertTrue(policy.failure(provider: .codex, loginRequired: false).isEmpty)
        XCTAssertEqual(policy.failure(provider: .codex, loginRequired: false).map(\.kind), [.connection])
        XCTAssertTrue(policy.failure(provider: .codex, loginRequired: false).isEmpty)
        XCTAssertEqual(policy.failure(provider: .codex, loginRequired: true).map(\.kind), [.login])
        XCTAssertTrue(policy.failure(provider: .codex, loginRequired: true).isEmpty)
        _ = policy.success(provider: .codex, metrics: [], now: now, usageEnabled: false, resetEnabled: false)
        XCTAssertEqual(policy.failure(provider: .codex, loginRequired: true).map(\.kind), [.login])
    }

    func testStableSemanticVersionsUseNumericOrdering() throws {
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("v1.9.0")), try XCTUnwrap(ReleaseVersion("1.10.0")))
        XCTAssertEqual(ReleaseVersion("v1.7.0"), ReleaseVersion("1.7.0"))
        for invalid in ["1.7", "1.7.0-beta", "windows-1.7.0", "1.7.-1", "x1.7.0", "1.7.999999999999999999999"] {
            XCTAssertNil(ReleaseVersion(invalid))
        }
    }

    func testUpdateRequiresNewStableReleaseWithMacInstallerAndTrustedURL() throws {
        func release(tag: String = "v1.7.0", prerelease: Bool = false, draft: Bool = false,
                     url: String = "https://github.com/jaewoo4200/ClaudeUsage/releases/tag/v1.7.0",
                     name: String = "ClaudeUsage-1.7.0.dmg", size: Int = 4000) throws -> PublishedRelease {
            let json: [String: Any] = ["tag_name": tag, "html_url": url, "draft": draft, "prerelease": prerelease,
                                       "assets": [["name": name, "size": size]]]
            return try JSONDecoder().decode(PublishedRelease.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertTrue(try release().isAvailable(after: "1.6.3"))
        XCTAssertFalse(try release().isAvailable(after: "1.7.0"))
        XCTAssertFalse(try release().isAvailable(after: "1.8.0"))
        XCTAssertFalse(try release(prerelease: true).isAvailable(after: "1.6.3"))
        XCTAssertFalse(try release(draft: true).isAvailable(after: "1.6.3"))
        XCTAssertFalse(try release(name: "ClaudeUsage-win-x64.zip").isAvailable(after: "1.6.3"))
        XCTAssertFalse(try release(size: 0).isAvailable(after: "1.6.3"))
        XCTAssertFalse(try release(url: "https://example.com/installer").isAvailable(after: "1.6.3"))
        XCTAssertFalse(try release(url: "https://github.com/another/repo/releases/tag/v1.7.0").isAvailable(after: "1.6.3"))
    }

    @MainActor
    func testHiddenProviderCannotAffectPetHistoricalTrend() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageHistoryStore(fileURL: url, minimumSampleInterval: 0)
        for (offset, claude, codex) in [(-3600.0, 10.0, 20.0), (0.0, 12.0, 80.0)] {
            store.record(UsageHistorySnapshot(
                claudeFiveHour: claude, claudeWeekly: nil, claudeModelMaximum: nil,
                openAIFiveHour: codex, openAIWeekly: nil, openAIModelMaximum: nil,
                claudeTodayTokens: 100, openAITodayTokens: offset < 0 ? 100 : 900_000
            ), at: now.addingTimeInterval(offset), force: true)
        }
        let trend = store.trend(now: now, showClaude: true, showCodex: false)
        XCTAssertEqual(trend.points, [10, 12])
        XCTAssertEqual(trend.percentPerHour, 2)
        XCTAssertEqual(trend.recentTokenDelta, 0)
        XCTAssertFalse(trend.resetDetected)
    }
}
