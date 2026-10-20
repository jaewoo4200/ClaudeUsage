import AppKit
import SwiftUI

/// Nonactivating panels need tracking even when another app owns the key window.
struct WidgetHoverRegion: NSViewRepresentable {
    var enabled = true
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> WidgetHoverTrackingView {
        WidgetHoverTrackingView()
    }

    func updateNSView(_ view: WidgetHoverTrackingView, context: Context) {
        view.onChange = onChange
        view.isTrackingEnabled = enabled
    }

    static func dismantleNSView(_ view: WidgetHoverTrackingView, coordinator: ()) {
        view.onChange = nil
        view.isTrackingEnabled = false
    }
}

final class WidgetHoverTrackingView: NSView {
    var onChange: ((Bool) -> Void)?
    var isTrackingEnabled = false {
        didSet {
            guard oldValue != isTrackingEnabled else { return }
            updateTrackingAreas()
        }
    }
    private var area: NSTrackingArea?
    private var pointerInside = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        area = nil
        guard isTrackingEnabled else {
            report(false)
            return
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        self.area = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isTrackingEnabled else { return }
        report(true)
    }

    override func mouseExited(with event: NSEvent) { report(false) }

    private func report(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        // AppKit can update tracking while SwiftUI is laying out the view.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pointerInside == inside else { return }
            self.onChange?(inside)
        }
    }
}
