import XCTest
import WebKit

final class AdapterWorkflowTests: XCTestCase {
    @MainActor func fixture(_ html: String) async throws -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        web.loadHTMLString(html + "<script>window.fixtureReady=true</script>", baseURL: URL(string: "https://chatgpt.com/"))
        for _ in 0..<50 {
            if (try? await web.evaluateJavaScript("window.fixtureReady===true")) as? Bool == true { return web }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "fixture-load", code: 1)
    }
    @MainActor func call(_ web: WKWebView, _ operation: String, payload: [String: Any] = [:]) async throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ImageFlow/Resources/chatgpt-adapter.js"), encoding: .utf8)
        let value: String = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(source, arguments: ["operation":operation,"payload":payload], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    if let string = value as? String { continuation.resume(returning: string) }
                    else { continuation.resume(throwing: NSError(domain: "fixture-value", code: 1)) }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        return try JSONSerialization.jsonObject(with: Data(value.utf8)) as! [String: Any]
    }
    @MainActor func testReasoningUsesInteractiveSliderAndVerifiesEachLevel() async throws {
        let web = try await fixture("""
        <form><div id="prompt-textarea" contenteditable="true">request</div><button type="button" class="__composer-pill" aria-expanded="false" onclick="this.setAttribute('aria-expanded','true')">High</button></form>
        <span role="slider" tabindex="0" aria-valuemin="0" aria-valuemax="4" aria-valuenow="3"></span>
        <script>
        document.querySelector('[role=slider]').addEventListener('keydown',e=>{let n=Number(e.target.getAttribute('aria-valuenow'));if(e.key==='Home')n=0;if(e.key==='ArrowRight')n=Math.min(4,n+1);e.target.setAttribute('aria-valuenow',n);});
        </script>
        """)
        defer { web.stopLoading() }
        let opened = try await call(web, "openReasoning")
        XCTAssertEqual(opened["ok"] as? Bool, true)
        for level in [4,0,2,1,3] {
            let result = try await call(web, "setReasoning", payload: ["level":level])
            XCTAssertEqual(result["level"] as? Int, level)
        }
    }
    @MainActor func testReasoningFailsClosedWhenWebsiteDoesNotApplySelection() async throws {
        let web = try await fixture("<span role='slider' tabindex='0' aria-valuemin='0' aria-valuemax='4' aria-valuenow='0'></span>")
        defer { web.stopLoading() }
        do { _ = try await call(web,"setReasoning",payload:["level":4]); XCTFail("Silently accepted unapplied reasoning") }
        catch { XCTAssertTrue(String(describing:error).contains("reasoning-not-applied")) }
    }
    @MainActor func testImageModeUsesMenuPreservesPromptAndIsIdempotent() async throws {
        for (label, tag) in [("이미지 만들기", "button"), ("Create image", "div")] {
            let web = try await fixture("""
            <form><div id="prompt-textarea" contenteditable="true"></div>
            <button type="button" data-testid="composer-plus-btn" aria-expanded="false">+</button>
            <\(tag) class="choice" hidden>\(label)</\(tag)></form>
            <script>
            window.selections=0;
            const plus=document.querySelector('[data-testid=composer-plus-btn]');
            const choice=document.querySelector('.choice');if(choice.tagName==='DIV')choice.setAttribute('role','menuitem');
            plus.onclick=()=>{plus.setAttribute('aria-expanded','true');choice.hidden=false;};
            plus.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){plus.setAttribute('aria-expanded','true');document.querySelector('.choice').hidden=false;}});
            document.querySelector('.choice').onclick=()=>{window.selections++;const pill=document.createElement('span');pill.setAttribute('data-system-hint-type','picture_v2');pill.contentEditable='false';document.querySelector('#prompt-textarea').prepend(pill);};
            </script>
            """)
            defer { web.stopLoading() }
            _ = try await call(web, "type", payload: ["prompt":"A teapot\nsize:1:1"])
            for _ in 0..<2 { let result = try await call(web, "imageMode"); XCTAssertEqual(result["ok"] as? Bool, true) }
            let selections = try await web.evaluateJavaScript("window.selections") as? Int
            XCTAssertEqual(selections, 1)
            let text = try await web.evaluateJavaScript("document.querySelector('#prompt-textarea').innerText") as? String
            XCTAssertTrue(text?.contains("A teapot") == true); XCTAssertTrue(text?.contains("size:1:1") == true)
        }
    }
    @MainActor func testSubmitRejectsMissingImageModeBeforeClickingSend() async throws {
        let web = try await fixture("<form><div id='prompt-textarea' contenteditable='true'>A teapot</div><button type='button' data-testid='send-button' onclick='window.sent=true'>Send</button></form>")
        defer { web.stopLoading() }
        do { _ = try await call(web, "submit"); XCTFail("Sent without explicit image mode") }
        catch { XCTAssertTrue(String(describing: error).contains("image-mode-not-applied")) }
        let sent = try await web.evaluateJavaScript("window.sent === true") as? Bool
        XCTAssertEqual(sent, false)
    }
    @MainActor func testPlaceholderIsNotReplyAndActualMarkdownIsPreserved() async throws {
        let web = try await fixture("""
        <main><div data-message-author-role="assistant" id="response">원본 답변을 기다리는 중</div>
        <form><div id="prompt-textarea" contenteditable="true"></div><button data-testid="send-button" aria-disabled="true"></button></form></main>
        """)
        defer { web.stopLoading() }
        let pending = try await call(web,"snapshot")
        XCTAssertEqual(pending["reply"] as? String, "")
        XCTAssertEqual(pending["sendEnabled"] as? Bool, false)
        _ = try await web.evaluateJavaScript("document.querySelector('#response').innerHTML='<div class=markdown>어떤 색상을 원하시나요?</div>'")
        let reply = try await call(web,"snapshot")
        XCTAssertEqual(reply["reply"] as? String, "어떤 색상을 원하시나요?")
    }
}
