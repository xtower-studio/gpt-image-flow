import AppKit
import Observation
import WebKit

@MainActor @Observable final class WebSession: NSObject, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {
    enum Status: String { case disconnected = "연결 필요", checking = "연결 확인 중", ready = "ChatGPT 연결됨" }
    var status: Status = .disconnected
    @ObservationIgnored let dataStore = WKWebsiteDataStore.default()
    @ObservationIgnored var browser: WKWebView?
    @ObservationIgnored var window: NSWindow?
    @ObservationIgnored var popups: [NSWindow] = []
    @ObservationIgnored var checkTask: Task<Void, Never>?

    func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        return config
    }
    func makeBrowser() -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: configuration())
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        return web
    }
    func connect() { openConnection(show: true) }
    func restore() { openConnection(show: false) }
    func openConnection(show: Bool) {
        if browser == nil {
            let web = makeBrowser()
            browser = web
            web.uiDelegate = self; web.navigationDelegate = self
            let window = NSWindow(contentRect: NSRect(x: 180, y: 120, width: 1080, height: 760),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Image Flow · ChatGPT 연결"
            window.delegate = self
            window.isReleasedWhenClosed = false
            web.frame = window.contentView!.bounds
            web.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(web)
            self.window = window
            web.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
        }
        status = .checking
        if show { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        startChecking()
    }
    func startChecking() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: .seconds(status == .ready ? 20 : 3))
            }
        }
    }
    func refresh() async {
        guard let browser, browser.url?.host == "chatgpt.com" else { status = .disconnected; return }
        let ready = (try? await browser.evaluateJavaScript(Self.readinessScript)) as? Bool == true
        status = ready ? .ready : .disconnected
        if ready && window?.isVisible != true { releaseBrowser() }
    }
    static let readinessScript = """
    (() => {
      const profile = document.querySelector('[data-testid="accounts-profile-button"],button[data-testid="profile-button"],button[aria-label*="Open profile"],button[aria-label*="프로필"]');
      const login = document.querySelector('[data-testid="login-button"]');
      return !!document.querySelector('#prompt-textarea,[contenteditable="true"]') && !!profile && !login;
    })()
    """
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { await refresh() } }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 760), configuration: configuration)
        popup.uiDelegate = self; popup.navigationDelegate = self
        let panel = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "ChatGPT 로그인"; panel.isReleasedWhenClosed = false
        panel.contentView = popup; popups.append(panel); panel.center(); panel.makeKeyAndOrderFront(nil)
        return popup
    }
    func webViewDidClose(_ webView: WKWebView) {
        if let panel = popups.first(where: { $0.contentView === webView }) {
            panel.close(); popups.removeAll { $0 === panel }
        }
    }
    func windowWillClose(_ notification: Notification) {
        if status == .ready { releaseBrowser() }
    }
    func releaseBrowser() {
        checkTask?.cancel(); checkTask = nil
        browser?.stopLoading(); browser?.removeFromSuperview(); browser?.uiDelegate = nil; browser?.navigationDelegate = nil
        browser = nil; window?.delegate = nil; window = nil
    }
}
