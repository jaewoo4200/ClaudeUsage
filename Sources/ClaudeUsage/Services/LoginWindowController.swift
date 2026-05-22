import AppKit
import WebKit

final class LoginWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate {
    private let onCookies: (String) -> Void
    private var webView: WKWebView!
    private var capturedAndClosed = false
    private var pollingTimer: Timer?

    // claude.ai 진짜 세션 쿠키 후보 — 인증 토큰 역할만 (방문 잔재인 lastActiveOrg, intercom 등은 제외)
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
        config.websiteDataStore = WKWebsiteDataStore.default()
        // JavaScript 자동 실행 등 기본값 OK
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let wv = WKWebView(frame: win.contentView!.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        // 진짜 macOS Safari 17 UA — Google이 차단 안 하는 정상 브라우저 UA
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        win.contentView?.addSubview(wv)
        webView = wv

        let url = URL(string: "https://claude.ai/login")!
        wv.load(URLRequest(url: url))

        // 1초마다도 폴링 — navigation 이벤트 안 잡혀도 캡처되도록
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

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        print("[Login] didFinish: \(webView.url?.absoluteString ?? "nil")")
        #endif
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
    }

    // MARK: - WKUIDelegate (popup 처리)

    // Google OAuth 등이 새 창(target=_blank, window.open)을 띄우려고 할 때
    // 새 창을 만들지 말고 현재 webView에 그대로 로드시킴
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

        // 현재 URL이 로그인/인증 페이지면 캡처하지 않음 (사용자가 폼을 보고 입력하도록)
        if let url = webView.url {
            let path = url.path
            if path.contains("/login") || path.contains("/auth") || path.contains("/oauth") || path.contains("/signin") {
                return
            }
        }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
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
