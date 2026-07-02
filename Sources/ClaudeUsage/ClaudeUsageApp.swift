import SwiftUI

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var themeStore = ThemeStore.shared
    @StateObject private var languageStore = LanguageStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
                .environmentObject(appDelegate)
                .environmentObject(themeStore)
                .environmentObject(languageStore)
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
    private var widgetWindow: FloatingPanel?
    private var loginWindow: NSWindow?
    private var loginController: LoginWindowController?  // ⬅️ retain
    private var settingsWindow: NSWindow?
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
    }

    @objc private func updateWidgetLevel() {
        guard let panel = widgetWindow else { return }
        let alwaysOnTop = AppSettings.shared.widgetAlwaysOnTop
        panel.level = alwaysOnTop ? .statusBar : .normal
        panel.collectionBehavior = alwaysOnTop
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.canJoinAllSpaces, .stationary]
        #if DEBUG
        print("[Widget] level changed: alwaysOnTop=\(alwaysOnTop)")
        #endif
    }

    @objc private func resizeWidgetToContent(_ notification: Notification) {
        guard let size = notification.userInfo?["size"] as? CGSize else { return }
        resizeWidgetWindow(to: size)
    }

    private func resizeWidgetWindow(to size: CGSize) {
        guard let panel = widgetWindow else { return }
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Claude Usage"
        win.isReleasedWhenClosed = false
        win.center()
        let root = SettingsView()
            .environmentObject(ThemeStore.shared)
            .environmentObject(AppSettings.shared)
            .environmentObject(LanguageStore.shared)
            .environmentObject(viewModel)
        win.contentView = NSHostingView(rootView: root)
        win.delegate = SettingsWindowDelegate.shared
        SettingsWindowDelegate.shared.onClose = { [weak self] in self?.settingsWindow = nil }
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWidget(viewModel: UsageViewModel) {
        #if DEBUG
        print("[Widget] showWidget called")
        #endif
        if widgetWindow == nil {
            let host = NSHostingView(rootView: WidgetView()
                .environmentObject(viewModel)
                .environmentObject(ThemeStore.shared)
                .environmentObject(LanguageStore.shared))
            host.translatesAutoresizingMaskIntoConstraints = true
            let fitting = host.fittingSize
            let w = max(fitting.width, 240)
            let h = max(fitting.height, 180)
            #if DEBUG
            print("[Widget] hosting fitting size: \(w) x \(h)")
            #endif

            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            host.frame = NSRect(x: 0, y: 0, width: w, height: h)
            panel.contentView = host
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true  // NSPanel 시스템 shadow (boundary 안에서 잘리지 않음)
            let alwaysOnTop = AppSettings.shared.widgetAlwaysOnTop
            panel.level = alwaysOnTop ? .statusBar : .normal
            panel.collectionBehavior = alwaysOnTop
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                : [.canJoinAllSpaces, .stationary]
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false

            var origin: NSPoint
            if let saved = WidgetPositionStore.load() {
                origin = saved
            } else if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                origin = NSPoint(x: visible.maxX - w - 20, y: visible.maxY - h - 20)
            } else {
                origin = NSPoint(x: 100, y: 100)
            }
            // 화면 밖으로 나가지 않도록 보정
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                if origin.x < visible.minX { origin.x = visible.minX + 20 }
                if origin.x + w > visible.maxX { origin.x = visible.maxX - w - 20 }
                if origin.y < visible.minY { origin.y = visible.minY + 20 }
                if origin.y + h > visible.maxY { origin.y = visible.maxY - h - 20 }
            }
            panel.setFrameOrigin(origin)
            #if DEBUG
            print("[Widget] panel origin: \(origin)")
            #endif
            widgetWindow = panel
        }
        if let contentView = widgetWindow?.contentView {
            resizeWidgetWindow(to: contentView.fittingSize)
        }
        widgetWindow?.orderFrontRegardless()
        widgetVisible = true
        #if DEBUG
        print("[Widget] panel ordered front. isVisible=\(widgetWindow?.isVisible ?? false), frame=\(widgetWindow?.frame ?? .zero)")
        #endif
    }

    func hideWidget() {
        if let win = widgetWindow {
            WidgetPositionStore.save(win.frame.origin)
            win.orderOut(nil)
        }
        widgetVisible = false
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
