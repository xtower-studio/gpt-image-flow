import AppKit
import WebKit
import FlowCore

struct WebSnapshot: Decodable {
    struct RemoteImage: Decodable {
        let url: String, fileID: String, responseID: String
        let width: Int, height: Int
        let complete: Bool
    }
    let path: String, ready: Bool, login: Bool, generating: Bool
    let assistantCount: Int, userCount: Int, reply: String
    let composerEmpty: Bool, sendEnabled: Bool, limitation: Bool
    let images: [RemoteImage]
    let serviceError: String?
    let fileInputs: Int
    var conversationID: String? {
        let parts = path.split(separator: "/")
        guard parts.count == 2, parts[0] == "c", UUID(uuidString: String(parts[1])) != nil else { return nil }
        return String(parts[1])
    }
}

enum WorkerError: LocalizedError {
    case login, attachment, limited, uncertain(String), website(String), generationFailed(String)
    var errorDescription: String? {
        switch self {
        case .login: "ChatGPT에 다시 로그인해 주세요. 작업 내용은 보관되어 있습니다."
        case .attachment: "참조 이미지 업로드를 확인할 수 없어 요청을 보내지 않았습니다."
        case .limited: "ChatGPT에서 사용 제한을 알려왔습니다. 새 전송을 일시정지했습니다."
        case .uncertain(let reason), .website(let reason), .generationFailed(let reason): reason
        }
    }
}

@MainActor final class WebWorker: NSObject, WKUIDelegate, WKNavigationDelegate {
    let web: WKWebView
    let host: NSWindow
    let slot: Int
    var pendingFiles: [URL] = []
    var panelDelivered = false
    var appliedReasoning: Int?
    var processTerminated = false
    let source: String
    var pendingCalls: [UUID: CheckedContinuation<String, Error>] = [:]
    var callTimeouts: [UUID: Task<Void, Never>] = [:]

    init(slot: Int, session: WebSession) throws {
        self.slot = slot
        source = try String(contentsOf: Bundle.module.url(forResource: "chatgpt-adapter", withExtension: "js", subdirectory: "Resources")!, encoding: .utf8)
        web = session.makeBrowser()
        host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        host.title = "Image Flow · 생성 \(slot + 1)"; host.isReleasedWhenClosed = false
        web.frame = host.contentView!.bounds; web.autoresizingMask = [.width, .height]
        host.contentView?.addSubview(web); host.orderOut(nil)
        web.uiDelegate = self; web.navigationDelegate = self
    }
    func call<T: Decodable>(_ operation: String, payload: [String: Any] = [:], as type: T.Type) async throws -> T {
        guard !processTerminated else { throw WorkerError.uncertain("웹 프로세스가 종료됐습니다. 기존 대화 상태를 확인하세요.") }
        let requestID = UUID()
        let result: String = try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { continuation in
            pendingCalls[requestID] = continuation
            callTimeouts[requestID] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.finishCall(requestID, .failure(WorkerError.uncertain("웹 응답 확인이 지연됐습니다. 기존 대화를 확인하세요.")))
            }
            web.callAsyncJavaScript(source, arguments: ["operation": operation, "payload": payload], in: nil, in: .page) { [weak self] result in
                switch result {
                case .success(let value):
                    if let text = value as? String { self?.finishCall(requestID, .success(text)) }
                    else { self?.finishCall(requestID, .failure(WorkerError.website("웹 응답을 읽을 수 없습니다."))) }
                case .failure(let error): self?.finishCall(requestID, .failure(error))
                }
            }
          }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishCall(requestID, .failure(CancellationError())) }
        }
        return try JSONDecoder().decode(type, from: Data(result.utf8))
    }
    func finishCall(_ id: UUID, _ result: Result<String, Error>) {
        callTimeouts.removeValue(forKey: id)?.cancel()
        pendingCalls.removeValue(forKey: id)?.resume(with: result)
    }
    struct Ack: Decodable { let ok: Bool }
    struct AttachmentState: Decodable { let count: Int; let busy: Bool; let sendEnabled: Bool }
    struct ReasoningResult: Decodable { let level: Int; let label: String }
    struct MetadataEnvelope: Decodable { let images: [ImageGenerationMetadata] }
    func generationMetadata() async throws -> [ImageGenerationMetadata] {
        try await call("generationMetadata", as: MetadataEnvelope.self).images
    }
    struct Download: Decodable { let base64: String; let mime: String; let size: Int }
    func snapshot() async throws -> WebSnapshot { try await call("snapshot", as: WebSnapshot.self) }
    func wait(_ seconds: Double = 1) async throws { try Task.checkCancellation(); try await Task.sleep(for: .seconds(seconds)); try Task.checkCancellation() }
    func load(_ conversation: String? = nil) async throws {
        processTerminated = false
        let address = conversation.map { "https://chatgpt.com/c/\($0)" } ?? "https://chatgpt.com/"
        web.load(URLRequest(url: URL(string: address)!))
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            try await wait()
            if let state = try? await snapshot() {
                if state.login { throw WorkerError.login }
                if state.ready, !web.isLoading {
                    if let conversation, state.conversationID != conversation { continue }
                    if conversation == nil, state.conversationID != nil { throw WorkerError.website("새 대화를 열 수 없습니다. 연결 창에서 상태를 확인해 주세요.") }
                    return
                }
            }
        }
        throw WorkerError.website("ChatGPT 화면을 불러오지 못했습니다. 네트워크와 연결 창을 확인해 주세요.")
    }
    func prepare(job: Job, files: [URL]) async throws -> WebSnapshot {
        try await load(job.continuationOf != nil ? job.conversationID : nil)
        do {
            // Only retry local preparation, before attachment or submission. A
            // late React layout replacement can discard the first tool selection.
            for attempt in 0..<3 {
                do {
                    _ = try await call("composeImage", payload: ["prompt": job.prompt], as: Ack.self)
                    break
                } catch {
                    let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
                    guard attempt < 2, ["image-mode-not-applied", "image-tool-menu-unavailable", "image-composer-unavailable"].contains(where: message.contains) else { throw error }
                    try await wait(0.6)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
            let reason: String
            if message.contains("image-tool-menu-unavailable") {
                reason = "ChatGPT의 도구 메뉴가 준비되지 않았습니다."
            } else if message.contains("image-composer-unavailable") {
                reason = "ChatGPT 입력창을 찾을 수 없습니다."
            } else {
                reason = "ChatGPT에서 이미지 생성 도구의 선택을 확인하지 못했습니다."
            }
            throw WorkerError.website("\(reason) 요청은 전송되지 않았으므로 다시 시도할 수 있습니다.")
        }
        try await wait(0.4)
        if !files.isEmpty {
            guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw WorkerError.attachment }
            pendingFiles = files; panelDelivered = false
            _ = try await call("attach", as: Ack.self)
            let deadline = Date().addingTimeInterval(60)
            var confirmed = false
            while Date() < deadline {
                try await wait()
                let state = try await call("attachments", as: AttachmentState.self)
                if panelDelivered, state.count >= files.count, !state.busy, state.sendEnabled { confirmed = true; break }
            }
            pendingFiles = []
            guard confirmed else { throw WorkerError.attachment }
        }
        try await applyReasoning(job.executionReasoning)
        _ = try await call("verifyImageMode", as: Ack.self)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let state = try await snapshot()
            if state.sendEnabled { return state }
            try await wait()
        }
        throw WorkerError.website("전송 버튼을 사용할 수 없습니다. 요청을 보내지 않았습니다.")
    }
    func applyReasoning(_ level: ReasoningLevel) async throws {
        var opened = false
        for _ in 0..<15 {
            if try await call("openReasoning", as: Ack.self).ok { opened = true; break }
            try await wait(0.3)
        }
        guard opened else { throw WorkerError.website("생성 방식 설정을 찾을 수 없어 요청을 보내지 않았습니다. 연결 창에서 ChatGPT 화면을 확인해 주세요.") }
        try await wait(0.3)
        let result = try await call("setReasoning", payload: ["level": level.rawValue], as: ReasoningResult.self)
        guard result.level == level.rawValue else { throw WorkerError.website("생성 방식 적용을 확인하지 못해 전송하지 않았습니다.") }
        appliedReasoning = result.level
        try await wait(0.2)
    }
    func submit() async throws { _ = try await call("submit", as: Ack.self) }
    func bytes(for image: WebSnapshot.RemoteImage) async throws -> Data {
        let result = try await call("download", payload: ["url": image.url], as: Download.self)
        guard let data = Data(base64Encoded: result.base64), data.count == result.size else { throw WorkerError.website("원본 이미지 다운로드가 완전하지 않습니다.") }
        return data
    }
    func close() {
        for id in Array(pendingCalls.keys) { finishCall(id, .failure(CancellationError())) }
        pendingFiles = []; web.stopLoading(); host.close(); web.uiDelegate = nil; web.navigationDelegate = nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { processTerminated = true }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        guard frame.isMainFrame, frame.request.url?.host == "chatgpt.com", !pendingFiles.isEmpty,
              parameters.allowsMultipleSelection || pendingFiles.count == 1 else { completionHandler(nil); return }
        panelDelivered = true; completionHandler(pendingFiles)
    }
}
