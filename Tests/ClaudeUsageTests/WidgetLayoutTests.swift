import AppKit
import SwiftUI
import XCTest
@testable import ClaudeUsage

final class WidgetLayoutTests: XCTestCase {
    @MainActor
    func testAllThemesFitStressCaseAndRenderNonblank() throws {
        let viewModel = UsageViewModel(autoStart: false)
        viewModel.state = .loaded(
            AccountSnapshot(
                organization: Organization(
                    uuid: "test",
                    name: "Test Account",
                    capabilities: ["claude_max"],
                    rateLimitTier: "max_20x"
                ),
                usage: UsageData(
                    fiveHour: UsageWindow(utilization: 68, resetsAt: Date().addingTimeInterval(4_000)),
                    sevenDay: UsageWindow(utilization: 14, resetsAt: Date().addingTimeInterval(300_000)),
                    sevenDayFable: UsageWindow(utilization: 24, resetsAt: Date().addingTimeInterval(300_000))
                )
            )
        )
        viewModel.openAIState = .loaded(try stressOpenAIUsage())

        let themeStore = ThemeStore()
        let languageStore = LanguageStore()
        let originalTheme = themeStore.current
        let originalLanguage = languageStore.current
        defer {
            themeStore.current = originalTheme
            languageStore.current = originalLanguage
        }
        languageStore.current = .en

        for theme in ThemeKind.allCases {
            themeStore.current = theme
            let root = WidgetView()
                .environmentObject(viewModel)
                .environmentObject(themeStore)
                .environmentObject(languageStore)
            let host = NSHostingView(rootView: root)
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize

            XCTAssertGreaterThan(size.width, 0, "\(theme.rawValue) width")
            XCTAssertGreaterThan(size.height, 0, "\(theme.rawValue) height")
            XCTAssertLessThanOrEqual(size.width, 300, "\(theme.rawValue) should stay compact")
            XCTAssertLessThanOrEqual(size.height, 900, "\(theme.rawValue) should fit a laptop display")

            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                XCTFail("Could not create \(theme.rawValue) bitmap")
                continue
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 1_000, "\(theme.rawValue) render should not be blank")

            let url = URL(fileURLWithPath: "/private/tmp/ClaudeUsage-\(theme.rawValue)-widget.png")
            try png.write(to: url, options: .atomic)
        }
    }

    private func stressOpenAIUsage() throws -> OpenAIUsageData {
        let models = ["Sol", "Terra", "Luna"].map { tier in
            """
            {
              "limit_name": "GPT-5.6-\(tier)",
              "metered_feature": "gpt_5_6_\(tier.lowercased())",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 24,
                  "reset_after_seconds": 4000,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 11,
                  "reset_after_seconds": 300000,
                  "limit_window_seconds": 604800
                }
              }
            }
            """
        }.joined(separator: ",")

        let json = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 20,
              "reset_after_seconds": 4000,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 31,
              "reset_after_seconds": 300000,
              "limit_window_seconds": 604800
            }
          },
          "additional_rate_limits": [\(models)]
        }
        """
        return try JSONDecoder().decode(OpenAIUsageData.self, from: Data(json.utf8))
    }
}
