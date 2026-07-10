import SwiftUI

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var themeStore = ThemeStore.shared
    @StateObject private var languageStore = LanguageStore.shared
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var usageHistory = UsageHistoryStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
                .environmentObject(appDelegate)
                .environmentObject(themeStore)
                .environmentObject(languageStore)
                .environmentObject(appSettings)
                .environmentObject(usageHistory)
        } label: {
            MenuBarLabel()
                .environmentObject(viewModel)
                .environmentObject(themeStore)
                .environmentObject(languageStore)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var widgetWindows: [WidgetPanelKind: FloatingPanel] = [:]
    private weak var widgetViewModel: UsageViewModel?
    private var loginWindow: NSWindow?
    private var loginController: LoginWindowController?  // ⬅️ retain
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    @Published var widgetVisible: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        NSApp.setActivationPolicy(.accessory)
        // 저장된 appearance 즉시 적용
        AppSettings.shared.applyAppearance()
        #if DEBUG
        print("[App] launched")
        #endif
        // 위젯 alwaysOnTop 토글 시 panel level 갱신
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateWidgetLevel),
            name: AppSettings.widgetAlwaysOnTopChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resizeWidgetToContent),
            name: .widgetContentSizeDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateConfiguredWidgetWindows),
            name: AppSettings.widgetConfigurationChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateWidgetLayoutForTheme),
            name: ThemeStore.themeChanged,
            object: nil
        )

    }

    @objc private func updateWidgetLevel() {
        let alwaysOnTop = AppSettings.shared.widgetAlwaysOnTop
        for panel in widgetWindows.values {
            panel.level = alwaysOnTop ? .statusBar : .normal
            panel.collectionBehavior = alwaysOnTop
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                : [.canJoinAllSpaces, .stationary]
        }
        #if DEBUG
        print("[Widget] level changed: alwaysOnTop=\(alwaysOnTop)")
        #endif
    }

    @objc private func resizeWidgetToContent(_ notification: Notification) {
        guard let size = notification.userInfo?["size"] as? CGSize,
              let panelID = notification.userInfo?["panelID"] as? String,
              let kind = WidgetPanelKind(rawValue: panelID) else { return }
        resizeWidgetWindow(kind, to: size)
    }

    private func resizeWidgetWindow(_ kind: WidgetPanelKind, to size: CGSize) {
        guard let panel = widgetWindows[kind] else { return }
        let width = max(ceil(size.width), 240)
        let height = max(ceil(size.height), 180)
        guard width.isFinite, height.isFinite else { return }

        var frame = panel.frame
        guard abs(frame.width - width) >= 0.5 || abs(frame.height - height) >= 0.5 else { return }

        let previousMaxY = frame.maxY
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = previousMaxY - height

        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if frame.minX < visible.minX { frame.origin.x = visible.minX + 20 }
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width - 20 }
            if frame.minY < visible.minY { frame.origin.y = visible.minY + 20 }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height - 20 }
        }

        panel.setFrame(frame, display: true)
    }

    @objc private func updateConfiguredWidgetWindows() {
        guard widgetVisible, let widgetViewModel else { return }
        reconcileWidgetWindows(viewModel: widgetViewModel)
    }

    @objc private func updateWidgetLayoutForTheme() {
        guard widgetVisible, let widgetViewModel else { return }
        DispatchQueue.main.async { [weak self, weak widgetViewModel] in
            guard let self, let widgetViewModel else { return }
            for panel in self.widgetWindows.values {
                panel.contentView?.invalidateIntrinsicContentSize()
                panel.contentView?.needsLayout = true
                panel.contentView?.layoutSubtreeIfNeeded()
            }
            self.reconcileWidgetWindows(viewModel: widgetViewModel)
        }
    }

    func toggleWidget(viewModel: UsageViewModel) {
        if widgetVisible {
            hideWidget()
        } else {
            showWidget(viewModel: viewModel)
        }
    }

    func openSettings(viewModel: UsageViewModel) {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Claude + Codex Usage"
        win.isReleasedWhenClosed = false
        win.center()
        let root = SettingsView()
            .environmentObject(self)
            .environmentObject(ThemeStore.shared)
            .environmentObject(AppSettings.shared)
            .environmentObject(LanguageStore.shared)
            .environmentObject(viewModel)
            .environmentObject(UsageHistoryStore.shared)
        win.contentView = NSHostingView(rootView: root)
        win.delegate = SettingsWindowDelegate.shared
        SettingsWindowDelegate.shared.onClose = { [weak self] in self?.settingsWindow = nil }
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openUsageHistory(viewModel: UsageViewModel) {
        if let win = historyWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "usage_history_dashboard".l
        win.minSize = NSSize(width: 640, height: 480)
        win.isReleasedWhenClosed = false
        win.center()
        let root = UsageHistoryDashboardView()
            .environmentObject(ThemeStore.shared)
            .environmentObject(AppSettings.shared)
            .environmentObject(LanguageStore.shared)
            .environmentObject(viewModel)
            .environmentObject(UsageHistoryStore.shared)
        win.contentView = NSHostingView(rootView: root)
        win.delegate = HistoryWindowDelegate.shared
        HistoryWindowDelegate.shared.onClose = { [weak self] in self?.historyWindow = nil }
        historyWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWidget(viewModel: UsageViewModel) {
        #if DEBUG
        print("[Widget] showWidget called")
        #endif
        widgetViewModel = viewModel
        AppSettings.shared.floatingWidgetVisible = true
        reconcileWidgetWindows(viewModel: viewModel)
        widgetVisible = !widgetWindows.isEmpty
        if !widgetVisible {
            AppSettings.shared.floatingWidgetVisible = false
        }
        #if DEBUG
        print("[Widget] ordered \(widgetWindows.count) panel(s) front")
        #endif
    }

    func hideWidget() {
        AppSettings.shared.floatingWidgetVisible = false
        for (kind, win) in widgetWindows {
            WidgetPositionStore.save(win.frame.origin, id: kind.rawValue)
            win.orderOut(nil)
        }
        widgetVisible = false
    }

    private func reconcileWidgetWindows(viewModel: UsageViewModel) {
        let desired = desiredWidgetKinds()
        let desiredSet = Set(desired)
        let obsolete = widgetWindows.keys.filter { !desiredSet.contains($0) }
        for kind in obsolete {
            removeWidgetWindow(kind)
        }

        for (slot, kind) in desired.enumerated() where widgetWindows[kind] == nil {
            widgetWindows[kind] = makeWidgetWindow(kind, slot: slot, viewModel: viewModel)
        }

        for kind in desired {
            guard let panel = widgetWindows[kind] else { continue }
            if let contentView = panel.contentView {
                contentView.layoutSubtreeIfNeeded()
                resizeWidgetWindow(kind, to: contentView.fittingSize)
            }
            panel.orderFrontRegardless()
        }
        updateWidgetLevel()
    }

    private func desiredWidgetKinds() -> [WidgetPanelKind] {
        let settings = AppSettings.shared
        guard settings.widgetLayoutMode == .separate else { return [.combined] }

        var kinds: [WidgetPanelKind] = []
        if settings.separateClaudeWidgetEnabled { kinds.append(.claude) }
        if settings.separateOpenAIWidgetEnabled { kinds.append(.openAI) }
        return kinds.isEmpty ? [.claude] : kinds
    }

    private func makeWidgetWindow(
        _ kind: WidgetPanelKind,
        slot: Int,
        viewModel: UsageViewModel
    ) -> FloatingPanel {
        let host = NSHostingView(rootView: WidgetView(panelID: kind.rawValue, provider: kind.provider)
            .environmentObject(viewModel)
            .environmentObject(ThemeStore.shared)
            .environmentObject(LanguageStore.shared)
            .environmentObject(AppSettings.shared)
            .environmentObject(UsageHistoryStore.shared))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let width = max(fitting.width, 240)
        let height = max(fitting.height, 180)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        var origin = WidgetPositionStore.load(id: kind.rawValue)
            ?? defaultWidgetOrigin(size: NSSize(width: width, height: height), slot: slot)
        origin = clampedWidgetOrigin(origin, size: NSSize(width: width, height: height), screen: NSScreen.main)
        panel.setFrameOrigin(origin)
        return panel
    }

    private func removeWidgetWindow(_ kind: WidgetPanelKind) {
        guard let panel = widgetWindows.removeValue(forKey: kind) else { return }
        WidgetPositionStore.save(panel.frame.origin, id: kind.rawValue)
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func defaultWidgetOrigin(size: NSSize, slot: Int) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 100, y: 100) }
        return NSPoint(
            x: visible.maxX - size.width - 20 - CGFloat(slot) * (size.width + 16),
            y: visible.maxY - size.height - 20
        )
    }

    private func clampedWidgetOrigin(_ origin: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
        guard let visible = screen?.visibleFrame else { return origin }
        let maximumX = max(visible.minX + 20, visible.maxX - size.width - 20)
        let maximumY = max(visible.minY + 20, visible.maxY - size.height - 20)
        return NSPoint(
            x: min(max(origin.x, visible.minX + 20), maximumX),
            y: min(max(origin.y, visible.minY + 20), maximumY)
        )
    }

    func presentLogin(onCookies: @escaping (String) -> Void) {
        if let existing = loginWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = LoginWindowController(onCookies: { [weak self] cookieString in
            onCookies(cookieString)
            self?.loginWindow?.close()
        })
        loginController = controller  // ⬅️ retain — 안 그러면 dealloc되어 navigationDelegate 끊김
        let win = controller.window!
        win.delegate = LoginWindowDelegate.shared
        LoginWindowDelegate.shared.onClose = { [weak self] in
            self?.loginWindow = nil
            self?.loginController = nil
        }
        loginWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        print("[Login] window presented, controller retained")
        #endif
    }
}

final class LoginWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = LoginWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class HistoryWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}
