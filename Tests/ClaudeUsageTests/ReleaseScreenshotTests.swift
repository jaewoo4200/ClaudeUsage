import AppKit
import SwiftUI
import XCTest
@testable import ClaudeUsage

final class ReleaseScreenshotTests: XCTestCase {
    @MainActor
    func testRenderPublicReleaseScreenshotsWithDemoData() throws {
        let output = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-release-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let vm = UsageViewModel(autoStart: false)
        let theme = ThemeStore()
        let language = LanguageStore.shared
        let settings = AppSettings()
        let history = UsageHistoryStore(fileURL: output.appendingPathComponent("unused-history.json"))
        let original = (theme.current, language.current, settings.widgetLayoutMode,
                        settings.usagePetEnabled, settings.usageHistoryEnabled,
                        settings.mimoAnimationMode, settings.companionKind)
        defer {
            theme.current = original.0
            language.current = original.1
            settings.widgetLayoutMode = original.2
            settings.usagePetEnabled = original.3
            settings.usageHistoryEnabled = original.4
            settings.mimoAnimationMode = original.5
            settings.companionKind = original.6
        }
        settings.usagePetEnabled = true
        settings.usageHistoryEnabled = true
        settings.mimoAnimationMode = .still
        settings.companionKind = .mimo
        let now = Date()
        let breakdown = try JSONDecoder().decode(UsageBreakdown.self, from: Data("""
        {"as_of":"\(ISO8601DateFormatter().string(from: now))","rows":[
          {"key":"claude_code","display_name":"Claude Code","percent":72},
          {"key":"chat","display_name":"Chats","percent":20},
          {"key":"cowork","display_name":"Cowork","percent":6},
          {"key":"other","display_name":"Other","percent":2}
        ]}
        """.utf8))
        vm.state = .loaded(AccountSnapshot(
            organization: .init(uuid: "demo", name: "Demo", capabilities: ["claude_max"], rateLimitTier: "max_20x"),
            usage: .init(
                fiveHour: .init(utilization: 38, resetsAt: now.addingTimeInterval(9_000)),
                sevenDay: .init(utilization: 18, resetsAt: now.addingTimeInterval(300_000)),
                sevenDayFable: .init(utilization: 24, resetsAt: now.addingTimeInterval(300_000)),
                sevenDayBreakdown: breakdown
            )
        ))
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        vm.openAIState = .loaded(OpenAIUsageData(
            planType: "pro", rateLimit: .init(
                primaryWindow: .init(usedPercent: 42, resetAt: nil, resetAfterSeconds: 5_400, limitWindowSeconds: 18_000),
                secondaryWindow: .init(usedPercent: 28, resetAt: nil, resetAfterSeconds: 400_000, limitWindowSeconds: 604_800)
            ), codeReviewRateLimit: nil, additionalRateLimits: [],
            tokenActivity: .init(summary: nil, dailyBuckets: [
                .init(startDate: dateFormatter.string(from: yesterday), tokens: 1_250_000)
            ])
        ))
        vm.claudeLocalTokenUsage = .init(todayTokens: 0, updatedAt: now)

        for kind in ThemeKind.allCases {
            theme.current = kind
            for lang in AppLanguage.allCases {
                language.current = lang
                for layout in [WidgetLayoutMode.horizontal, .paged, .stacked] {
                    settings.widgetLayoutMode = layout
                    try render(WidgetView().environmentObject(vm).environmentObject(theme)
                        .environmentObject(language).environmentObject(settings).environmentObject(history),
                        name: "widget-\(layout.rawValue)-\(kind.rawValue)-\(lang.rawValue)", output: output)
                }
                try render(MenuBarContentView().environmentObject(vm).environmentObject(AppDelegate())
                    .environmentObject(theme).environmentObject(language).environmentObject(settings)
                    .environmentObject(history), name: "dropdown-\(kind.rawValue)-\(lang.rawValue)", output: output)
                try render(TodayTokensView().environmentObject(vm).environmentObject(theme)
                    .environmentObject(language).environmentObject(settings),
                    name: "tokens-\(kind.rawValue)-\(lang.rawValue)", output: output)
                try render(UsageBreakdownView(breakdown: breakdown, compact: false)
                    .environmentObject(theme).environmentObject(language).padding(20).frame(width: 340)
                    .background(theme.current.tokens.bg),
                    name: "breakdown-\(kind.rawValue)-\(lang.rawValue)", output: output)
            }
        }
    }

    @MainActor
    private func render<V: View>(_ root: V, name: String, output: URL) throws {
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 200)
        XCTAssertLessThan(host.fittingSize.height, 900)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000)
        try png.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
    }
}
