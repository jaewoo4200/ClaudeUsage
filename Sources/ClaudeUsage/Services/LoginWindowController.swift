import AppKit
import WebKit

final class LoginWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate {
    private let onCookies: (String) -> Void
    private var webView: WKWebView!
    private var capturedAndClosed = false
    private var pollingTimer: Timer?
    private var statusLabel: NSTextField!
    private var dataStore: WKWebsiteDataStore!

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
        let toolbar = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 36,
                                            width: contentView.bounds.width, height: 36))
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let reloadBtn = NSButton(title: "↻ \(L10n.t("login_reload"))", target: self, action: #selector(reload))
        reloadBtn.bezelStyle = .rounded
        reloadBtn.frame = NSRect(x: 12, y: 6, width: 100, height: 24)
        toolbar.addSubview(reloadBtn)

        let safariBtn = NSButton(title: "Safari ↗", target: self, action: #selector(openInSafari))
        safariBtn.bezelStyle = .rounded
        safariBtn.frame = NSRect(x: 120, y: 6, width: 90, height: 24)
        toolbar.addSubview(safariBtn)

        let clearBtn = NSButton(title: L10n.t("login_clear_data"), target: self, action: #selector(clearAndReload))
        clearBtn.bezelStyle = .rounded
        clearBtn.frame = NSRect(x: 218, y: 6, width: 100, height: 24)
        toolbar.addSubview(clearBtn)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 326, y: 9, width: 180, height: 18)
        statusLabel.autoresizingMask = [.width]
        toolbar.addSubview(statusLabel)

        contentView.addSubview(toolbar)

        // 웹뷰 영역 (툴바 아래)
        let wvFrame = NSRect(x: 0, y: 0, width: contentView.bounds.width,
                              height: contentView.bounds.height - 36)
        let wv = WKWebView(frame: wvFrame, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
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

    func windowWillClose(_ notification: Notification) {
        pollingTimer?.invalidate()
        pollingTimer = nil
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
        // 쿠키 + 캐시 다 비우고 처음부터
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                self?.loadInitial()
            }
        }
    }

    @objc private func openInSafari() {
        // 사용자가 Safari에서 직접 로그인 후 다시 우리 창에 와서 retry할 수 있게
        if let url = URL(string: "https://claude.ai/login") {
            NSWorkspace.shared.open(url)
            updateStatus("login_safari_hint".l)
        }
    }

    private func updateStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("[Login] didFinish: \(webView.url?.absoluteString ?? "nil")")
        #endif
        if let url = webView.url {
            updateStatus("📍 \(url.host ?? "")")
        }
        tryCapture(reason: "didFinish")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        #if DEBUG
        print("[Login] didCommit: \(webView.url?.absoluteString ?? "nil")")
        #endif
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        #if DEBUG
        print("[Login] redirect: \(webView.url?.absoluteString ?? "nil")")
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
        print("[Login] popup requested: \(navigationAction.request.url?.absoluteString ?? "nil")")
        #endif
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // MARK: - 쿠키 캡처

    private func tryCapture(reason: String) {
        guard !capturedAndClosed else { return }

        if let url = webView.url {
            let path = url.path
            if path.contains("/login") || path.contains("/auth") || path.contains("/oauth") || path.contains("/signin") {
                return
            }
        }

        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
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
