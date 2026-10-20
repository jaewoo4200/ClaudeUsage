import AppKit
import WebKit
import SwiftUI

final class LoginWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private let onCookies: (String) -> Void
    private var webView: WKWebView!
    private var capturedAndClosed = false
    private var pollingTimer: Timer?
    private var statusLabel: NSTextField!
    private var dataStore: WKWebsiteDataStore!
    private var sessionSheet: NSWindow?
    private var popups: [ObjectIdentifier: (window: NSWindow, webView: WKWebView)] = [:]

    private let sessionCookieCandidates: Set<String> = [
        "sessionKey",
        "__Secure-next-auth.session-token",
        "next-auth.session-token"
    ]

    init(onCookies: @escaping (String) -> Void) {
        self.onCookies = onCookies
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.t("login_window_title")
        win.center()
        win.minSize = NSSize(width: 460, height: 640)
        super.init(window: win)

        let config = WKWebViewConfiguration()
        // 격리된 데이터 store — 다른 앱(Claude Desktop 등)의 캐시/쿠키와 분리
        // 매번 fresh state로 시작 → 이전 잔재로 인한 redirect loop 방지
        dataStore = WKWebsiteDataStore.nonPersistent()
        config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        guard let contentView = win.contentView else { fatalError() }

        // 툴바 영역 (상단)
        let toolbarHeight: CGFloat = 78
        let toolbar = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - toolbarHeight,
                                            width: contentView.bounds.width, height: toolbarHeight))
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let reloadBtn = NSButton(title: "↻ \(L10n.t("login_reload"))", target: self, action: #selector(reload))
        reloadBtn.bezelStyle = .rounded
        reloadBtn.frame = NSRect(x: 12, y: 43, width: 80, height: 24)
        toolbar.addSubview(reloadBtn)

        let safariBtn = NSButton(title: "login_browser_open".l, target: self, action: #selector(openInBrowser))
        safariBtn.bezelStyle = .rounded
        safariBtn.frame = NSRect(x: 98, y: 43, width: 120, height: 24)
        toolbar.addSubview(safariBtn)

        let clearBtn = NSButton(title: L10n.t("login_clear_data"), target: self, action: #selector(clearAndReload))
        clearBtn.bezelStyle = .rounded
        clearBtn.frame = NSRect(x: 224, y: 43, width: 70, height: 24)
        toolbar.addSubview(clearBtn)

        let sessionBtn = NSButton(title: "login_browser_session".l, target: self, action: #selector(openSessionSheet))
        sessionBtn.bezelStyle = .rounded
        sessionBtn.frame = NSRect(x: 300, y: 43, width: 145, height: 24)
        toolbar.addSubview(sessionBtn)

        statusLabel = NSTextField(wrappingLabelWithString: "login_email_hint".l)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 12, y: 4, width: contentView.bounds.width - 24, height: 34)
        statusLabel.autoresizingMask = [.width]
        toolbar.addSubview(statusLabel)

        contentView.addSubview(toolbar)

        // 웹뷰 영역 (툴바 아래)
        let wvFrame = NSRect(x: 0, y: 0, width: contentView.bounds.width,
                              height: contentView.bounds.height - toolbarHeight)
        let wv = WKWebView(frame: wvFrame, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        contentView.addSubview(wv)
        webView = wv

        loadInitial()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tryCapture(reason: "poll")
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        pollingTimer?.invalidate()
    }

    func prepareForClose() {
        closePopups()
        closeSessionSheet()
        pollingTimer?.invalidate()
        pollingTimer = nil
        webView.stopLoading()
        capturedAndClosed = true
    }

    // MARK: - 사용자 액션

    private func loadInitial() {
        let url = URL(string: "https://claude.ai/login")!
        webView.load(URLRequest(url: url))
        updateStatus("loading_status".l)
    }

    @objc private func reload() {
        webView.reload()
        updateStatus("loading_status".l)
    }

    @objc private func clearAndReload() {
        closePopups()
        // 쿠키 + 캐시 다 비우고 처음부터
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                self?.loadInitial()
            }
        }
    }

    @objc private func openInBrowser() {
        NSWorkspace.shared.open(BrowserSession.loginURL)
        updateStatus("login_browser_hint".l)
    }

    @objc private func openSessionSheet() {
        guard sessionSheet == nil, let window else { return }
        closePopups()
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "login_browser_session".l
        let host = NSHostingView(rootView: BrowserSessionLoginView(onCookies: { [weak self] cookie in
            guard let self, !self.capturedAndClosed else { return }
            self.closeSessionSheet()
            self.capturedAndClosed = true
            self.pollingTimer?.invalidate()
            self.onCookies(cookie)
        }, onCancel: { [weak self] in self?.closeSessionSheet() }))
        sheet.contentView = host
        sheet.setContentSize(host.fittingSize)
        sessionSheet = sheet
        window.beginSheet(sheet)
    }

    private func closeSessionSheet() {
        guard let sessionSheet else { return }
        window?.endSheet(sessionSheet)
        self.sessionSheet = nil
    }

    private func updateStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, BrowserSession.needsExternalBrowser(url) {
            decisionHandler(.cancel)
            openInBrowser()
            openSessionSheet()
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("[Login] didFinish host: \(webView.url?.host ?? "nil")")
        #endif
        if let url = webView.url {
            updateStatus(url.host == "claude.ai" ? "login_email_hint".l : (url.host ?? ""))
        }
        tryCapture(reason: "didFinish")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        #if DEBUG
        print("[Login] didCommit host: \(webView.url?.host ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        #if DEBUG
        print("[Login] redirect host: \(webView.url?.host ?? "nil")")
        #endif
        tryCapture(reason: "redirect")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        #if DEBUG
        print("[Login] didFailProvisional: \(error.localizedDescription)")
        #endif
        updateStatus("⚠️ \(error.localizedDescription)")
    }

    // MARK: - WKUIDelegate (popup 처리)

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        #if DEBUG
        print("[Login] popup host: \(navigationAction.request.url?.host ?? "nil")")
        #endif
        guard !capturedAndClosed, sessionSheet == nil, popups.count < 4,
              let url = navigationAction.request.url else { return nil }
        if BrowserSession.needsExternalBrowser(url) {
            openInBrowser()
            openSessionSheet()
            return nil
        }
        guard url.scheme == "https" || url.absoluteString == "about:blank" else { return nil }
        // Returning the supplied configuration preserves the opener and shared ephemeral cookies.
        let popupView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        popupView.navigationDelegate = self
        popupView.uiDelegate = self
        popupView.autoresizingMask = [.width, .height]
        let popup = NSWindow(contentRect: popupView.bounds, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        popup.title = "login_window_title".l
        popup.contentView = popupView
        popup.isReleasedWhenClosed = false
        popup.delegate = self
        popups[ObjectIdentifier(popup)] = (popup, popupView)
        window?.addChildWindow(popup, ordered: .above)
        popup.center()
        popup.makeKeyAndOrderFront(nil)
        return popupView
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.values.first(where: { $0.webView === webView })?.window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let popup = popups.removeValue(forKey: ObjectIdentifier(window)) else { return }
        popup.webView.stopLoading()
        popup.webView.navigationDelegate = nil
        popup.webView.uiDelegate = nil
        self.window?.removeChildWindow(window)
    }

    private func closePopups() {
        for popup in Array(popups.values) { popup.window.close() }
    }

    // MARK: - 쿠키 캡처

    private func tryCapture(reason: String) {
        guard !capturedAndClosed, sessionSheet == nil else { return }

        if let url = webView.url {
            let path = url.path
            if path.contains("/login") || path.contains("/auth") || path.contains("/oauth") || path.contains("/signin") {
                return
            }
        }

        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.capturedAndClosed, self.sessionSheet == nil else { return }
            let claudeCookies = cookies.filter { c in
                let d = c.domain
                return d == "claude.ai" || d == ".claude.ai" || d.hasSuffix(".claude.ai")
            }
            if !claudeCookies.isEmpty {
                let names = claudeCookies.map { $0.name }.joined(separator: ", ")
                #if DEBUG
                print("[Login] [\(reason)] claude.ai cookies: \(names)")
                #endif
            }
            let hasSession = claudeCookies.contains { self.sessionCookieCandidates.contains($0.name) }
            guard hasSession else { return }

            let cookieString = claudeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            self.capturedAndClosed = true
            self.pollingTimer?.invalidate()
            #if DEBUG
            print("[Login] ✅ captured \(claudeCookies.count) cookies, has session token")
            #endif
            DispatchQueue.main.async { self.onCookies(cookieString) }
        }
    }
}
