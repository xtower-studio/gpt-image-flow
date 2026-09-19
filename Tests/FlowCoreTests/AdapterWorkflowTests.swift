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
    @MainActor func testImagePillInjectionIsLiteralIdempotentAndDoesNotSendOrOpenMenus() async throws {
        let web = try await fixture("""
        <form><div id="prompt-textarea" contenteditable="true"></div>
        <button type="button" data-testid="composer-plus-btn" onclick="window.menuOpened=true">+</button>
        <button type="button" data-testid="send-button" onclick="window.sent=true">Send</button></form>
        <script>
        window.inputs=[];window.changes=0;
        document.querySelector('#prompt-textarea').addEventListener('input',e=>window.inputs.push(e.inputType));
        document.querySelector('#prompt-textarea').addEventListener('change',()=>window.changes++);
        </script>
        """)
        defer { web.stopLoading() }
        let prompt = "A <img src=x onerror=alert(1)> & \"teapot\"\n\nsize:1:1\nn=4"
        for _ in 0..<2 { _ = try await call(web, "composeImage", payload: ["prompt": prompt]) }
        let result = try await web.evaluateJavaScript("""
        (()=>{const el=document.querySelector('#prompt-textarea'),pill=el.querySelector('[data-id="picture_v2"]');
        const copy=el.cloneNode(true);copy.querySelector('span').remove();copy.firstChild.firstChild.remove();
        return {count:el.querySelectorAll('span').length,editable:pill.contentEditable,symbol:pill.dataset.symbol,
        keyword:pill.dataset.keyword,hint:pill.dataset.systemHintType,inline:pill.hasAttribute('data-inline-selection-pill'),
        prompt:Array.from(copy.children).map(p=>p.textContent).join('\\n'),imgs:el.querySelectorAll('img').length,
        sent:window.sent===true,menu:window.menuOpened===true,inputs:window.inputs,changes:window.changes};})()
        """) as! [String: Any]
        XCTAssertEqual(result["count"] as? Int, 1)
        XCTAssertEqual(result["editable"] as? String, "false")
        XCTAssertEqual(result["symbol"] as? String, "ecosystemMention")
        XCTAssertEqual(result["keyword"] as? String, "이미지 만들기")
        XCTAssertEqual(result["hint"] as? String, "picture_v2")
        XCTAssertEqual(result["inline"] as? Bool, true)
        XCTAssertEqual(result["prompt"] as? String, prompt)
        XCTAssertEqual(result["imgs"] as? Int, 0)
        XCTAssertEqual(result["sent"] as? Bool, false)
        XCTAssertEqual(result["menu"] as? Bool, false)
        XCTAssertEqual(result["inputs"] as? [String], ["insertHTML", "insertHTML"])
        XCTAssertEqual(result["changes"] as? Int, 2)
        _ = try await call(web, "verifyImageMode")
        _ = try await call(web, "submit")
        let sent = try await web.evaluateJavaScript("window.sent===true") as? Bool
        XCTAssertEqual(sent, true)
    }
    @MainActor func testImagePillReconciliationFailureStopsPreparation() async throws {
        let web = try await fixture("""
        <div id="prompt-textarea" contenteditable="true"></div>
        <script>document.querySelector('#prompt-textarea').addEventListener('input',()=>setTimeout(()=>document.querySelector('span')?.remove(),20));</script>
        """)
        defer { web.stopLoading() }
        do { _ = try await call(web, "composeImage", payload: ["prompt":"A teapot"]); XCTFail("Accepted a discarded pill") }
        catch { XCTAssertTrue(String(describing: error).contains("image-mode-not-applied")) }
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
        <nav><a tabindex="0" onclick="window.wrongConversation=true">이미지 만들기</a><button type="button" onclick="window.wrongConversation=true">Create image</button></nav>
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
