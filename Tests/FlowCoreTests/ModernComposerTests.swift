import XCTest
import WebKit

extension AdapterWorkflowTests {
    private var modernComposer: String {
        """
        <nav><button onclick="window.wrongNavigation=true">이미지 생성</button></nav>
        <main><form data-chatgpt-composer>
        <div class="ProseMirror" contenteditable="true" data-composer-markdown></div>
        <button type="button" data-composer-navigation-target="add-context" aria-expanded="false">+</button>
        <button type="button" data-composer-navigation-target="reasoning" data-selected-reasoning-effort="none">Instant</button>
        <button type="submit" aria-label="보내기" onclick="event.preventDefault();window.sent=(window.sent||0)+1">Send</button>
        </form></main>
        <script>
        const form=document.querySelector('form'),plus=form.querySelector('[data-composer-navigation-target="add-context"]');
        plus.onclick=()=>{
          window.menuOpened=(window.menuOpened||0)+1;plus.setAttribute('aria-expanded','true');
          setTimeout(()=>{
            const item=document.createElement('button');item.type='button';item.dataset.listNavigationItem='true';
            item.innerHTML='<span>이미지 생성</span><span>무엇이든 시각화하세요</span>';
            item.onclick=()=>{const selected=document.createElement('button');selected.type='button';selected.setAttribute('aria-label','이미지 생성 제거');selected.textContent='이미지 생성';form.append(selected);item.remove();plus.setAttribute('aria-expanded','false');};
            document.body.append(item);
          },100);
        };
        document.querySelector('.ProseMirror').addEventListener('input',e=>{
          // New ProseMirror schema strips unsupported inline tool nodes.
          e.target.querySelectorAll('[data-id="picture_v2"]').forEach(n=>n.replaceWith(n.textContent));
        });
        </script>
        """
    }

    @MainActor func testModernComposerSelectsNativeToolAndSendsOnce() async throws {
        let web = try await fixture(modernComposer)
        defer { web.stopLoading() }
        let prompt = "A <teapot> & a cup\n\nn=4"
        for _ in 0..<2 { _ = try await call(web, "composeImage", payload: ["prompt": prompt]) }
        let evidence = try await web.evaluateJavaScript("""
        ({prompt:Array.from(document.querySelector('.ProseMirror').children).map(p=>p.textContent).join('\\n'),
        menus:window.menuOpened,sent:window.sent||0,wrong:window.wrongNavigation===true,
        pills:document.querySelectorAll('[aria-label="이미지 생성 제거"]').length})
        """) as! [String: Any]
        XCTAssertEqual(evidence["prompt"] as? String, prompt)
        XCTAssertEqual(evidence["menus"] as? Int, 1)
        XCTAssertEqual(evidence["pills"] as? Int, 1)
        XCTAssertEqual(evidence["sent"] as? Int, 0)
        XCTAssertEqual(evidence["wrong"] as? Bool, false)
        let snapshot = try await call(web, "snapshot")
        XCTAssertEqual(snapshot["ready"] as? Bool, true)
        XCTAssertEqual(snapshot["sendEnabled"] as? Bool, true)
        _ = try await call(web, "verifyImageMode")
        _ = try await call(web, "submit")
        let sent = try await web.evaluateJavaScript("window.sent") as? Int
        XCTAssertEqual(sent, 1)
        _ = try await web.evaluateJavaScript("document.querySelector('[aria-label=\"이미지 생성 제거\"]').remove()")
        do { _ = try await call(web, "submit"); XCTFail("Sent after tool was removed") }
        catch { XCTAssertTrue(String(describing: error).contains("image-mode-not-applied")) }
    }

    @MainActor func testModernComposerWaitsForHydrationAndDoesNotClickDisabledControls() async throws {
        let web = try await fixture(modernComposer)
        defer { web.stopLoading() }
        _ = try await web.evaluateJavaScript("document.querySelector('[data-composer-navigation-target=\"add-context\"]').disabled=true")
        let state = try await call(web, "snapshot")
        XCTAssertEqual(state["ready"] as? Bool, false)
        do { _ = try await call(web, "composeImage", payload: ["prompt": "A teapot"]); XCTFail("Accepted disabled tool menu") }
        catch { XCTAssertTrue(String(describing: error).contains("image-tool-menu-unavailable")) }
        let untouched = try await web.evaluateJavaScript("!window.menuOpened && !window.sent && !window.wrongNavigation") as? Bool
        XCTAssertEqual(untouched, true)
    }

    @MainActor func testRejectedLegacyPillFallsBackWithoutLeakingToolLabelIntoPrompt() async throws {
        let web = try await fixture(modernComposer.replacingOccurrences(of: "data-composer-markdown", with: "id=\"prompt-textarea\""))
        defer { web.stopLoading() }
        _ = try await call(web, "composeImage", payload: ["prompt": "A teapot"])
        let text = try await web.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String
        XCTAssertEqual(text, "A teapot")
        _ = try await call(web, "verifyImageMode")
    }

    @MainActor func testToolLabelInsidePromptIsNotEvidenceOfSelectedTool() async throws {
        let web = try await fixture(modernComposer)
        defer { web.stopLoading() }
        _ = try await web.evaluateJavaScript("document.querySelector('.ProseMirror').textContent='이미지 생성 제거 Create image'")
        do { _ = try await call(web, "verifyImageMode"); XCTFail("Accepted plain prompt text as a selected tool") }
        catch { XCTAssertTrue(String(describing: error).contains("image-mode-not-applied")) }
    }
}

extension AdapterWorkflowTests {
    @MainActor func testGeneratedBlobImagesUseStableMessageIdentityAndExcludeReferences() async throws {
        let web = try await fixture("""
        <main><div data-chatgpt-search-unit-key="turn:0:user" data-chatgpt-search-message-ids="user-id"><div data-user-message-bubble><img alt="생성된 이미지 1" id="reference"></div></div>
        <div data-chatgpt-search-message-ids="reply-id"><button data-testid="generated-image-preview"><img id="result" alt="생성된 이미지 1"></button></div></main>
        <script>
        const bytes=Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='),c=>c.charCodeAt(0));
        window.imageBlob=new Blob([bytes],{type:'image/png'});
        document.querySelector('#result').src=URL.createObjectURL(window.imageBlob);
        document.querySelector('#reference').src=URL.createObjectURL(window.imageBlob);
        </script>
        """)
        defer { web.stopLoading() }
        let first = try await call(web, "snapshot")
        let images = first["images"] as! [[String: Any]]
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["fileID"] as? String, "generated-reply-id-0")
        XCTAssertEqual(first["userCount"] as? Int, 1)
        let download = try await call(web, "download", payload: ["url": images[0]["url"]!])
        XCTAssertEqual(download["mime"] as? String, "image/png")
        XCTAssertNotNil(Data(base64Encoded: download["base64"] as! String))
        _ = try await web.evaluateJavaScript("document.querySelector('#result').src=URL.createObjectURL(window.imageBlob)")
        let next = try await call(web, "snapshot")
        let nextImages = next["images"] as! [[String: Any]]
        XCTAssertEqual(nextImages[0]["fileID"] as? String, images[0]["fileID"] as? String)
        XCTAssertNotEqual(nextImages[0]["url"] as? String, images[0]["url"] as? String)
        let reference = try await web.evaluateJavaScript("document.querySelector('#reference').src") as! String
        do { _ = try await call(web, "download", payload: ["url":reference]); XCTFail("Downloaded an unverified blob") }
        catch { XCTAssertTrue(String(describing:error).contains("unexpected-image-origin")) }
    }
}

extension AdapterWorkflowTests {
    @MainActor func testModernTextReplyExcludesUserPromptAndRoleHeading() async throws {
        let web = try await fixture("""
        <main><div data-chatgpt-search-unit-key="turn:0:user" data-chatgpt-search-message-ids="user"><div data-user-message-bubble>Do not copy my prompt</div></div>
        <div data-chatgpt-search-unit-key="turn:1:assistant" data-chatgpt-search-message-ids="assistant"><h4 data-conversation-role="assistant">ChatGPT 답변:</h4>
        <div data-markdown-text-style="assistant-message"><p>어떤 색상을 원하시나요?</p></div></div></main>
        """)
        defer { web.stopLoading() }
        let snapshot = try await call(web, "snapshot")
        XCTAssertEqual(snapshot["reply"] as? String, "어떤 색상을 원하시나요?")
        XCTAssertEqual(snapshot["assistantCount"] as? Int, 1)
        XCTAssertEqual(snapshot["userCount"] as? Int, 1)
    }
}

extension AdapterWorkflowTests {
    @MainActor func testGalleryThumbnailsCollectAllImagesWithoutDuplicatingLargePreview() async throws {
        let web = try await fixture("""
        <main><div data-chatgpt-search-message-ids="reply reply reply reply">
        <button data-testid="generated-image-preview" aria-label="생성된 이미지 1"><img alt="생성된 이미지 1" src="blob:https://chatgpt.com/one"></button>
        <div role="group" aria-label="생성된 이미지">
        <button aria-label="생성된 이미지 1 표시"><img src="blob:https://chatgpt.com/one"></button>
        <button aria-label="생성된 이미지 2 표시"><img src="blob:https://chatgpt.com/two"></button>
        <button aria-label="생성된 이미지 3 표시"><img src="blob:https://chatgpt.com/three"></button>
        <button aria-label="생성된 이미지 4 표시"><img src="blob:https://chatgpt.com/four"></button>
        </div></div></main>
        """)
        defer { web.stopLoading() }
        let snapshot = try await call(web, "snapshot")
        let images = snapshot["images"] as! [[String: Any]]
        XCTAssertEqual(images.map { $0["fileID"] as! String }, (0..<4).map { "generated-reply-\($0)" })
    }
}
