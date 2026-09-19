import XCTest
import WebKit

final class AdapterTests: XCTestCase {
    @MainActor func testCurrentImageCardsWithoutAssistantRoleExcludeReferencesAndDuplicates() async throws {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        // HTML is local. The base URL supplies only an origin; no URL is requested.
        web.loadHTMLString("""
        <main><div data-message-author-role="user" id="user"></div><div id="result"></div><form id="form"><div id="prompt-textarea" contenteditable="true"></div></form></main>
        <script>
        function add(parent, id, alt) {
          const im = document.createElement('img'); im.alt = alt;
          Object.defineProperties(im, {src:{value:'https://chatgpt.com/backend-api/estuary/content?id='+id},currentSrc:{value:''},naturalWidth:{value:1254},naturalHeight:{value:1254},complete:{value:true}});
          document.querySelector(parent).append(im);
        }
        add('#user','file_reference','생성된 이미지: input');
        add('#form','file_upload','생성된 이미지: upload');
        add('#result','file_result','생성된 이미지: vase');
        add('#result','file_result','');
        add('#result','file_other','unrelated');
        window.fixtureReady = true;
        </script>
        """, baseURL: URL(string: "https://chatgpt.com/"))
        for _ in 0..<50 {
            if (try? await web.evaluateJavaScript("window.fixtureReady === true")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ImageFlow/Resources/chatgpt-adapter.js"), encoding: .utf8)
        let json: String = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(source, arguments: ["operation": "snapshot", "payload": [:]], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    if let string = value as? String { continuation.resume(returning: string) }
                    else { continuation.resume(throwing: NSError(domain: "fixture", code: 1)) }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        let result = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let images = result["images"] as! [[String: Any]]
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?["fileID"] as? String, "file_result")
        XCTAssertEqual(result["assistantCount"] as? Int, 1)
        XCTAssertEqual(result["userCount"] as? Int, 1)
        web.stopLoading()
    }
}
