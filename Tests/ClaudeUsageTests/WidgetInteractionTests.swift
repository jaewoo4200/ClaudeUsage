import AppKit
import SwiftUI
import XCTest
@testable import ClaudeUsage

final class WidgetInteractionTests: XCTestCase {
    @MainActor
    private final class DragSpyPanel: FloatingPanel {
        var dragEvents: [NSEvent] = []
        override func performDrag(with event: NSEvent) { dragEvents.append(event) }
    }

    @MainActor
    private func panel() -> DragSpyPanel {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let panel = DragSpyPanel(contentRect: NSRect(x: visible.minX + 100, y: visible.minY + 100,
                                                    width: 480, height: 300),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.positionID = "test-\(UUID().uuidString)"
        return panel
    }

    @MainActor
    private func down(in panel: FloatingPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
                                        modifierFlags: [], timestamp: 1, windowNumber: panel.windowNumber,
                                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    @MainActor
    func testNativeDragReceivesOriginalDownOnceWithoutManualFrameMovement() throws {
        let panel = panel()
        defer {
            panel.orderOut(nil)
            UserDefaults.standard.removeObject(forKey: "widget.position.\(panel.positionID)")
        }
        let event = try down(in: panel)
        let frame = panel.frame
        panel.beginPointerInteraction(with: event)
        panel.beginWidgetDrag()
        panel.beginWidgetDrag()
        XCTAssertEqual(panel.dragEvents.count, 1)
        XCTAssertTrue(panel.dragEvents.first === event)
        XCTAssertTrue(panel.isDraggingWidget)
        XCTAssertEqual(panel.frame, frame, "SwiftUI must not run a competing frame movement loop")
        panel.finishWidgetInteraction()
        XCTAssertFalse(panel.isInteractingWithWidget)
        XCTAssertEqual(WidgetPositionStore.load(id: panel.positionID), panel.frame.origin)
        panel.beginWidgetDrag()
        XCTAssertEqual(panel.dragEvents.count, 1, "No drag may start from a stale mouse-down")
    }

    @MainActor
    func testHoverAndResizeWaitForReleaseAndUseLatestSizeAtNewLocation() throws {
        let panel = panel()
        defer { panel.orderOut(nil) }
        let tracking = WidgetHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        panel.contentView = tracking
        tracking.isTrackingEnabled = true
        var hoverChanges = 0
        tracking.onChange = { _ in hoverChanges += 1 }
        panel.beginPointerInteraction(with: try down(in: panel))
        let original = panel.frame
        panel.resizeToContent(CGSize(width: 480, height: 400))
        panel.resizeToContent(CGSize(width: 480, height: 320))
        XCTAssertEqual(panel.frame, original, "Breakdown expansion must not move a held widget")
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 2, windowNumber: panel.windowNumber, context: nil,
            eventNumber: 2, trackingNumber: 0, userData: nil))
        tracking.mouseEntered(with: entered)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(hoverChanges, 0)
        panel.setFrameOrigin(NSPoint(x: original.minX + 40, y: original.minY + 40))
        let movedTop = panel.frame.maxY
        panel.finishWidgetInteraction()
        XCTAssertEqual(panel.frame.width, 480)
        XCTAssertEqual(panel.frame.height, 320)
        XCTAssertEqual(panel.frame.maxY, movedTop, accuracy: 0.01)
        XCTAssertEqual(panel.frame.minX, original.minX + 40, accuracy: 0.01)
        let settled = panel.frame
        panel.resizeToContent(CGSize(width: CGFloat.nan, height: 999))
        XCTAssertEqual(panel.frame, settled)
    }

    @MainActor
    func testMissingOrForeignMouseDownCannotStartDrag() throws {
        let first = panel(), second = panel()
        defer { first.orderOut(nil); second.orderOut(nil) }
        first.beginWidgetDrag()
        first.beginPointerInteraction(with: try down(in: second))
        first.beginWidgetDrag()
        XCTAssertFalse(first.isInteractingWithWidget)
        XCTAssertTrue(first.dragEvents.isEmpty)
    }

    @MainActor
    func testHideButtonsAcrossEveryThemeAndLayoutReleaseOnlyTheirOwnWidget() throws {
        let settings = AppSettings.shared
        let theme = ThemeStore.shared
        let original = (settings.widgetLayoutMode, settings.showClaude, settings.showCodex,
                        settings.separateClaudeWidgetEnabled, settings.separateOpenAIWidgetEnabled,
                        settings.usagePetEnabled, settings.floatingWidgetVisible, theme.current)
        let positions = Dictionary(uniqueKeysWithValues: WidgetPanelKind.allCases.map { kind in
            (kind, UserDefaults.standard.object(forKey: kind == .combined ? "widget.position" : "widget.position.\(kind.rawValue)"))
        })
        let delegate = AppDelegate()
        defer {
            delegate.hideWidget()
            settings.widgetLayoutMode = original.0
            settings.showClaude = true
            settings.showCodex = original.2
            settings.showClaude = original.1
            settings.separateClaudeWidgetEnabled = original.3
            settings.separateOpenAIWidgetEnabled = original.4
            settings.usagePetEnabled = original.5
            settings.floatingWidgetVisible = original.6
            theme.current = original.7
            for (kind, value) in positions {
                UserDefaults.standard.set(value, forKey: kind == .combined ? "widget.position" : "widget.position.\(kind.rawValue)")
            }
        }
        settings.showClaude = true
        settings.showCodex = true
        settings.separateClaudeWidgetEnabled = true
        settings.separateOpenAIWidgetEnabled = true
        settings.usagePetEnabled = false
        let vm = UsageViewModel(autoStart: false)
        vm.state = .needsLogin
        vm.openAIState = .unavailable

        for kind in ThemeKind.allCases {
            theme.current = kind
            for layout in WidgetLayoutMode.allCases {
                settings.widgetLayoutMode = layout
                delegate.showWidget(viewModel: vm)
                let expected = layout == .separate ? 2 : 1
                XCTAssertEqual(delegate.widgetWindows.count, expected)
                for (id, panel) in Array(delegate.widgetWindows) {
                    let host = try XCTUnwrap(panel.contentView)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                    let buttons = hideButtons(in: host)
                    XCTAssertEqual(buttons.count, 1, "\(kind)/\(layout)/\(id) must have one hide button")
                    let button = try XCTUnwrap(buttons.first)
                    XCTAssertEqual(button.accessibilityIdentifier(), "widget-hide")
                    XCTAssertFalse(button.toolTip?.isEmpty ?? true)
                    XCTAssertFalse(button.isBordered)
                    XCTAssertEqual(button.imageScaling, .scaleNone)
                    button.performClick(nil)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    XCTAssertNil(delegate.widgetWindows[id])
                    XCTAssertFalse(panel.isVisible)
                    XCTAssertNil(panel.contentView, "Hidden panels must release SwiftUI timelines")
                    XCTAssertTrue(settings.showClaude && settings.showCodex, "Hiding must not disable account polling")
                    XCTAssertEqual(delegate.widgetVisible, !delegate.widgetWindows.isEmpty)
                    XCTAssertEqual(settings.floatingWidgetVisible, delegate.widgetVisible)
                }
                delegate.showWidget(viewModel: vm)
                XCTAssertEqual(delegate.widgetWindows.count, expected, "Showing again restores hidden panels")
                delegate.hideWidget()
                XCTAssertTrue(delegate.widgetWindows.isEmpty)
            }
        }
    }

    @MainActor
    private func hideButtons(in view: NSView) -> [NSButton] {
        let own = (view as? NSButton).flatMap { $0.identifier?.rawValue == "widget-hide" ? $0 : nil }
        return (own.map { [$0] } ?? []) + view.subviews.flatMap(hideButtons)
    }

    func testCountdownStopsWithoutDateOrAfterReset() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        for reset in [nil, now, now.addingTimeInterval(-1)] as [Date?] {
            var entries = UsageCountdownSchedule(resetsAt: reset, isWeekly: true).entries(from: now, mode: .normal)
            XCTAssertEqual(entries.next(), now)
            XCTAssertNil(entries.next())
        }
    }

    func testWeeklyCountdownUpdatesAtMinuteBoundariesThenSwitchesToSeconds() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let reset = now.addingTimeInterval(3_665.5)
        var entries = UsageCountdownSchedule(resetsAt: reset, isWeekly: true).entries(from: now, mode: .normal)
        _ = entries.next()
        let first = try XCTUnwrap(entries.next())
        let second = try XCTUnwrap(entries.next())
        let third = try XCTUnwrap(entries.next())
        XCTAssertEqual(first.timeIntervalSince(now), 5.501, accuracy: 0.001)
        XCTAssertEqual(second.timeIntervalSince(first), 60, accuracy: 0.001)
        XCTAssertEqual(third.timeIntervalSince(second), 1, accuracy: 0.001)
        XCTAssertEqual(GaugeCountdown.text(resetsAt: reset, isWeekly: true, now: second, short: true), "0:59:59")
    }

    func testShortCountdownKeepsSecondPrecisionAndFinalResetTick() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        var entries = UsageCountdownSchedule(resetsAt: now.addingTimeInterval(2.5), isWeekly: false)
            .entries(from: now, mode: .normal)
        let dates = Array(entries)
        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(dates.last!.timeIntervalSince(now), 2.501, accuracy: 0.001)
        XCTAssertEqual(dates[2].timeIntervalSince(dates[1]), 1, accuracy: 0.001)
        _ = entries.next()
    }
}
