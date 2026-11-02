import AppKit

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var positionID = WidgetPanelKind.combined.rawValue
    private(set) var isDraggingWidget = false
    var isInteractingWithWidget: Bool { mouseDownEvent != nil || isDraggingWidget }
    private var mouseDownEvent: NSEvent?
    private var pendingContentSize: CGSize?
    private var dragCompletionTask: Task<Void, Never>?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { beginPointerInteraction(with: event) }
        super.sendEvent(event)
        if event.type == .leftMouseUp || (event.type == .leftMouseDown && NSEvent.pressedMouseButtons & 1 == 0) {
            finishWidgetInteraction()
        }
    }

    func beginPointerInteraction(with event: NSEvent) {
        guard event.type == .leftMouseDown, event.window === self else { return }
        mouseDownEvent = event
    }

    func beginWidgetDrag() {
        guard !isDraggingWidget, let mouseDownEvent else { return }
        isDraggingWidget = true
        // Use the original down event. Window Server owns movement, not a second SwiftUI frame loop.
        performDrag(with: mouseDownEvent)
        // Native dragging returns immediately and may consume mouse-up before sendEvent sees it.
        dragCompletionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled, let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.finishWidgetInteraction()
                    return
                }
            }
        }
    }

    func finishWidgetInteraction() {
        dragCompletionTask?.cancel()
        dragCompletionTask = nil
        let wasDragging = isDraggingWidget
        mouseDownEvent = nil
        isDraggingWidget = false
        if let size = pendingContentSize {
            pendingContentSize = nil
            resizeToContent(size)
        }
        if wasDragging { WidgetPositionStore.save(frame.origin, id: positionID) }
        func refreshHover(in view: NSView) {
            (view as? WidgetHoverTrackingView)?.refreshPointerLocation()
            view.subviews.forEach { refreshHover(in: $0) }
        }
        if let contentView { refreshHover(in: contentView) }
    }

    func resizeToContent(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        guard !isInteractingWithWidget else {
            pendingContentSize = size
            return
        }
        var next = frame
        let width = max(ceil(size.width), 240)
        let height = max(ceil(size.height), 180)
        guard abs(next.width - width) >= 0.5 || abs(next.height - height) >= 0.5 else { return }
        next.origin.y = next.maxY - height
        next.size = NSSize(width: width, height: height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            let minX = visible.minX + 20, minY = visible.minY + 20
            next.origin.x = min(max(next.origin.x, minX), max(minX, visible.maxX - width - 20))
            next.origin.y = min(max(next.origin.y, minY), max(minY, visible.maxY - height - 20))
        }
        setFrame(next, display: true)
    }

    override func orderOut(_ sender: Any?) {
        finishWidgetInteraction()
        super.orderOut(sender)
    }
}
