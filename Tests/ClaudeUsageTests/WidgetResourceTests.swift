import AppKit
import Darwin
import XCTest
@testable import ClaudeUsage

final class WidgetResourceTests: XCTestCase {
    @MainActor
    func testProfileVisibleAndHiddenWidget() async throws {
        guard ProcessInfo.processInfo.environment["CLAUDE_USAGE_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in local UI-only resource measurement")
        }
        let settings = AppSettings.shared
        let theme = ThemeStore.shared
        let original = (settings.widgetLayoutMode, settings.usagePetEnabled, settings.mimoAnimationMode,
                        settings.companionKind, settings.usageHistoryEnabled, settings.showClaude,
                        settings.showCodex, settings.widgetBreakdownPinned, theme.current,
                        settings.floatingWidgetVisible)
        let position = UserDefaults.standard.object(forKey: "widget.position")
        let delegate = AppDelegate()
        defer {
            delegate.hideWidget()
            settings.widgetLayoutMode = original.0
            settings.usagePetEnabled = original.1
            settings.mimoAnimationMode = original.2
            settings.companionKind = original.3
            settings.usageHistoryEnabled = original.4
            settings.showClaude = true
            settings.showCodex = original.6
            settings.showClaude = original.5
            settings.widgetBreakdownPinned = original.7
            theme.current = original.8
            settings.floatingWidgetVisible = original.9
            UserDefaults.standard.set(position, forKey: "widget.position")
        }
        settings.widgetLayoutMode = .horizontal
        settings.usagePetEnabled = true
        settings.mimoAnimationMode = .automatic
        settings.companionKind = .mimo
        settings.usageHistoryEnabled = false
        settings.showClaude = true
        settings.showCodex = true
        settings.widgetBreakdownPinned = false
        theme.current = .daangn
        let vm = UsageViewModel(autoStart: false)
        let now = Date()
        vm.state = .loaded(AccountSnapshot(
            organization: .init(uuid: "profile-fixture", name: nil, capabilities: ["claude_max"], rateLimitTier: "max_20x"),
            usage: .init(fiveHour: .init(utilization: 58, resetsAt: now.addingTimeInterval(9_000)),
                         sevenDay: .init(utilization: 18, resetsAt: now.addingTimeInterval(300_000)),
                         sevenDayFable: .init(utilization: 24, resetsAt: now.addingTimeInterval(300_000)))
        ))
        vm.openAIState = .loaded(OpenAIUsageData(
            planType: "pro", rateLimit: .init(
                primaryWindow: .init(usedPercent: 42, resetAt: nil, resetAfterSeconds: 5_400, limitWindowSeconds: 18_000),
                secondaryWindow: .init(usedPercent: 28, resetAt: nil, resetAfterSeconds: 400_000, limitWindowSeconds: 604_800)
            ), codeReviewRateLimit: nil, additionalRateLimits: []
        ))
        delegate.showWidget(viewModel: vm)
        if let value = ProcessInfo.processInfo.environment["CLAUDE_USAGE_PREVIEW_SECONDS"],
           let duration = Double(value), duration > 0 {
            let panel = try XCTUnwrap(delegate.widgetWindows[.combined])
            panel.title = "ClaudeUsage Widget Preview"
            panel.center()
            print("[WidgetPreview] initial=\(panel.frame)")
            try await Task.sleep(nanoseconds: UInt64(min(duration, 180) * 1_000_000_000))
            print("[WidgetPreview] final=\(panel.frame) visible=\(panel.isVisible) dragging=\(panel.isDraggingWidget)")
            return
        }
        measureCPU(phase: "visible-auto")
        settings.mimoAnimationMode = .still
        measureCPU(phase: "visible-still")
        delegate.hideWidget()
        measureCPU(phase: "hidden")
    }

    @MainActor
    private func measureCPU(phase: String) {
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        var before = rusage(), after = rusage()
        getrusage(RUSAGE_SELF, &before)
        let start = ProcessInfo.processInfo.systemUptime
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        getrusage(RUSAGE_SELF, &after)
        func seconds(_ value: timeval) -> Double { Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000 }
        let cpu = seconds(after.ru_utime) + seconds(after.ru_stime) - seconds(before.ru_utime) - seconds(before.ru_stime)
        print(String(format: "[WidgetProfile] %@ cpu=%.3f%% wall=%.2fs peakRSS=%.1fMiB", phase,
                     cpu / elapsed * 100, elapsed, Double(after.ru_maxrss) / 1_048_576))
    }
}
