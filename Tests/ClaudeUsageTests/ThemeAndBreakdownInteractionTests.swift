import AppKit
import SwiftUI
import XCTest
@testable import ClaudeUsage

final class ThemeAndBreakdownInteractionTests: XCTestCase {
    func testLegacyThemeIDsRemainSeparateFromNewGauges() throws {
        XCTAssertEqual(ThemeKind.allCases.count, 6)
        for theme in ThemeKind.legacyThemes {
            XCTAssertTrue(theme.isLegacy)
            XCTAssertEqual(try JSONDecoder().decode(ThemeKind.self, from: JSONEncoder().encode(theme)), theme)
            XCTAssertFalse(ThemeKind.gaugeThemes.contains(theme))
        }
        XCTAssertEqual(ThemeKind(rawValue: "daangn"), .daangn)
        XCTAssertEqual(ThemeKind(rawValue: "toss"), .toss)
        XCTAssertEqual(ThemeKind(rawValue: "hybrid"), .hybrid)
        XCTAssertEqual(Set(ThemeKind.gaugeThemes.map(\.rawValue)), ["donut", "halo", "aura"])
    }

    @MainActor
    func testSavedLegacyAndNewThemeSelectionsReloadWithoutMigration() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "selectedTheme")
        defer { defaults.set(original, forKey: "selectedTheme") }
        for theme in ThemeKind.allCases {
            defaults.set(theme.rawValue, forKey: "selectedTheme")
            XCTAssertEqual(ThemeStore().current, theme)
        }
    }

    @MainActor
    func testDaangnKeepsOrangeInsteadOfNewDonutBlue() throws {
        let orange = try XCTUnwrap(NSColor(ThemeKind.daangn.tokens.accent).usingColorSpace(.sRGB))
        XCTAssertEqual(orange.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(orange.greenComponent, 111.0 / 255, accuracy: 0.01)
        XCTAssertEqual(orange.blueComponent, 15.0 / 255, accuracy: 0.01)
    }

    @MainActor
    func testHoverStaysOpenAcrossRowsAndClosesOnlyAfterWidgetExit() {
        let presentation = WidgetBreakdownPresentation()
        XCTAssertFalse(presentation.isOpen(pinned: false))
        presentation.isWidgetHovered = true
        presentation.reveal()
        presentation.dismissAfterExit()
        XCTAssertTrue(presentation.isOpen(pinned: false), "Crossing from Claude to Codex must not close details")
        presentation.isWidgetHovered = false
        presentation.isWidgetHovered = true
        presentation.dismissAfterExit()
        XCTAssertTrue(presentation.isOpen(pinned: false), "Re-entry cancels a pending hover exit")
        presentation.isWidgetHovered = false
        presentation.dismissAfterExit()
        XCTAssertFalse(presentation.isOpen(pinned: false))
    }

    @MainActor
    func testExplicitCloseDoesNotReopenDuringResizeHoverEvents() {
        let presentation = WidgetBreakdownPresentation()
        presentation.isWidgetHovered = true
        presentation.reveal()
        presentation.dismiss()
        presentation.reveal()
        XCTAssertFalse(presentation.isOpen(pinned: false))
        presentation.show()
        XCTAssertTrue(presentation.isOpen(pinned: false), "A click may reopen without leaving the widget")
        presentation.dismiss()
        presentation.isWidgetHovered = false
        presentation.dismissAfterExit()
        presentation.isWidgetHovered = true
        presentation.reveal()
        XCTAssertTrue(presentation.isOpen(pinned: false))
    }

    @MainActor
    func testLayoutResetDoesNotSuppressFirstHover() {
        let presentation = WidgetBreakdownPresentation()
        for _ in ThemeKind.allCases {
            presentation.dismiss()
            presentation.resetForLayoutChange()
            presentation.isWidgetHovered = true
            presentation.reveal()
            XCTAssertTrue(presentation.revealed)
            presentation.isWidgetHovered = false
            presentation.dismissAfterExit()
        }
    }

    @MainActor
    func testNativeHoverRegionIsAlwaysActiveAndPassesClicksThrough() throws {
        let view = WidgetHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 211, height: 48))
        view.isTrackingEnabled = true
        let area = try XCTUnwrap(view.trackingAreas.first)
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertNil(view.hitTest(NSPoint(x: 10, y: 10)), "Hover tracking must not intercept pins or widget dragging")
    }

    @MainActor
    func testFirstNativeHoverAfterEachThemeChangeInSameWidget() throws {
        let vm = UsageViewModel(autoStart: false)
        vm.state = .loaded(AccountSnapshot(
            organization: Organization(uuid: "fixture", name: nil, capabilities: ["claude_max"], rateLimitTier: "max_20x"),
            usage: try UsageData.decode(from: UsageBreakdownTests.fixture)
        ))
        let settings = AppSettings()
        let theme = ThemeStore()
        let language = LanguageStore.shared
        let presentation = WidgetBreakdownPresentation()
        let original = (settings.showClaude, settings.showCodex, settings.widgetLayoutMode,
                        settings.widgetBreakdownPinned, settings.usagePetEnabled, theme.current)
        defer {
            settings.showClaude = true
            settings.showCodex = original.1
            settings.showClaude = original.0
            settings.widgetLayoutMode = original.2
            settings.widgetBreakdownPinned = original.3
            settings.usagePetEnabled = original.4
            theme.current = original.5
        }
        settings.showClaude = true
        settings.showCodex = true
        settings.widgetLayoutMode = .horizontal
        settings.widgetBreakdownPinned = false
        settings.usagePetEnabled = false
        let history = UsageHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let host = NSHostingView(rootView: WidgetView(breakdownPresentation: presentation)
            .environmentObject(vm).environmentObject(settings).environmentObject(theme)
            .environmentObject(language).environmentObject(history))

        func trackingViews(_ view: NSView) -> [WidgetHoverTrackingView] {
            (view as? WidgetHoverTrackingView).map { [$0] } ?? view.subviews.flatMap(trackingViews)
        }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
                                                timestamp: 0, windowNumber: 0, context: nil,
                                                eventNumber: 0, trackingNumber: 0, userData: nil))
        }

        for kind in ThemeKind.allCases {
            presentation.isWidgetHovered = false
            presentation.dismissAfterExit()
            theme.current = kind
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            let weeklyRows = trackingViews(host).filter {
                $0.isTrackingEnabled && $0.bounds.width < 300 && $0.bounds.width > 180
                    && $0.bounds.height >= 35 && $0.bounds.height < 80
            }
            XCTAssertEqual(weeklyRows.count, 1, "\(kind) must expose a full-width weekly hover target")
            let row = try XCTUnwrap(weeklyRows.first)
            presentation.isWidgetHovered = true
            row.mouseEntered(with: try event(.mouseEntered))
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            XCTAssertTrue(presentation.revealed, "\(kind) failed its first hover after switching themes")
            row.mouseExited(with: try event(.mouseExited))
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @MainActor
    func testPinPersistsButTransientHoverDoesNot() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "widgetBreakdownPinned")
        defer { defaults.set(original, forKey: "widgetBreakdownPinned") }
        defaults.removeObject(forKey: "widgetBreakdownPinned")
        let settings = AppSettings()
        XCTAssertFalse(settings.widgetBreakdownPinned)
        let presentation = WidgetBreakdownPresentation()
        presentation.reveal()
        XCTAssertFalse(AppSettings().widgetBreakdownPinned)
        settings.widgetBreakdownPinned = true
        XCTAssertTrue(AppSettings().widgetBreakdownPinned)
        presentation.dismissAfterExit()
        XCTAssertTrue(presentation.isOpen(pinned: settings.widgetBreakdownPinned))
        XCTAssertTrue(WidgetBreakdownPresentation().isOpen(pinned: settings.widgetBreakdownPinned))
        settings.widgetBreakdownPinned = false
        XCTAssertFalse(AppSettings().widgetBreakdownPinned)
        XCTAssertFalse(presentation.isOpen(pinned: false))
    }
}
