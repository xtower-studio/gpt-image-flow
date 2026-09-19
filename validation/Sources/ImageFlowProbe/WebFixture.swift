import AppKit
import WebKit

@MainActor final class WebFixture: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    let view: WKWebView
    let slot: Int
    var attachments: [URL] = []
    var panelCalls = 0
    var cancelled = false
    var downloadDestination: URL?
    var downloadFinished = false
    var downloadError: String?
    var downloadReference: WKDownload?

    init(slot: Int, store: WKWebsiteDataStore) {
        self.slot = slot
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        view = WKWebView(frame: NSRect(x: slot * 260, y: 0, width: 260, height: 260), configuration: config)
        super.init()
        view.uiDelegate = self
        view.navigationDelegate = self
        view.loadHTMLString("""
        <!doctype html><meta charset="utf-8"><title>Image Flow Offline Probe</title>
        <h3>로컬 검증 워커 \(slot + 1)</h3>
        <p>ChatGPT에 접속하지 않는 테스트입니다.</p>
        <input id="upload" type="file" multiple accept="image/*">
        <script>
        window.slot = \(slot);
        window.ticks = 0;
        setInterval(() => window.ticks++, 250);
        window.readFiles = async () => Promise.all(Array.from(document.querySelector('#upload').files)
          .map(async file => ({name: file.name, size: file.size, data: await new Promise((resolve, reject) => {
            const reader = new FileReader(); reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = reject; reader.readAsDataURL(file);
          })})));
        </script>
        """, baseURL: nil)
    }

    func choose(_ files: [URL]) async throws {
        attachments = files
        cancelled = false
        let before = panelCalls
        try await view.evaluateJavaScript("document.querySelector('#upload').value = ''; document.querySelector('#upload').click();")
        try await waitUntil("file panel callback") { self.panelCalls > before }
        let expected = files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } ? files : []
        try await waitUntil("file input populated") { try await self.filesMatch(expected) }
        try await Task.sleep(for: .milliseconds(150))
    }

    func filesMatch(_ files: [URL]) async throws -> Bool {
        let result = try await javaScript("return await window.readFiles();")
        guard let rows = result as? [[String: Any]], rows.count == files.count else { return false }
        for (row, file) in zip(rows, files) {
            guard row["name"] as? String == file.lastPathComponent,
                  row["data"] as? String == (try Data(contentsOf: file)).base64EncodedString() else { return false }
        }
        return true
    }

    func javaScript(_ source: String, arguments: [String: Any] = [:]) async throws -> Any {
        let snapshot: JavaScriptSnapshot = try await withCheckedThrowingContinuation { continuation in
            view.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: JavaScriptSnapshot(value: value))
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        return snapshot.value
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        panelCalls += 1
        guard frame.isMainFrame, !cancelled,
              attachments.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
              parameters.allowsMultipleSelection || attachments.count <= 1 else {
            completionHandler(nil); return
        }
        completionHandler(attachments)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        // The probe cannot navigate to a remote service.
        guard scheme == "about" || scheme == "blob" || scheme == "file" || scheme == nil else {
            decisionHandler(.cancel); return
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloadReference = download
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloadReference = download
        download.delegate = self
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        completionHandler(downloadDestination)
    }
    func downloadDidFinish(_ download: WKDownload) { downloadFinished = true }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadError = error.localizedDescription
    }
}

// Serialized JS values are created and read on MainActor; the box crosses only
// the continuation boundary, never another application actor.
private struct JavaScriptSnapshot: @unchecked Sendable { let value: Any }
