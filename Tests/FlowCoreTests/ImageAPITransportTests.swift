import XCTest
@testable import FlowCore

final class ImageAPITransportTests: XCTestCase, @unchecked Sendable {
    func client() -> ImageAPIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [APIProtocolFixture.self]
        return ImageAPIClient(session: URLSession(configuration: config))
    }
    func testVerifyAndJSONGenerationUseDedicatedEndpointAndHeaders() async throws {
        let credentials = APICredentials(key: "fixture-only", organization: "org-test", project: "proj-test")
        try await client().verify(credentials)
        let result = try await client().generate(prompt: "teapot", options: ImageAPIOptions(), references: [], mask: nil, credentials: credentials)
        XCTAssertEqual(result.requestID, "req_fixture"); XCTAssertEqual(result.images.count, 1)
    }
    func testStreamingReceivesPreviewAndFinal() async throws {
        let recorder = PreviewRecorder(); var options = ImageAPIOptions(); options.stream = true; options.partialImages = 1
        let result = try await client().generate(prompt: "stream", options: options, references: [], mask: nil, credentials: APICredentials(key: "fixture-only"), preview: { await recorder.record($0) })
        XCTAssertEqual(result.images, [Data("final".utf8)])
        let previews = await recorder.values; XCTAssertEqual(previews, [Data("preview".utf8)])
    }
    func testHTTPFailureIsNotAutomaticallyResubmitted() async throws {
        do { _ = try await client().generate(prompt: "limit", options: ImageAPIOptions(), references: [], mask: nil, credentials: APICredentials(key: "fixture-only")); XCTFail("Expected 429") }
        catch { XCTAssertEqual((error as? ImageAPIError)?.status, 429); XCTAssertFalse(error.localizedDescription.contains("fixture-only")) }
    }
    func testCompletedImageIsDeliveredBeforeLaterStreamFailure() async throws {
        let recorder = PreviewRecorder(); var options = ImageAPIOptions(); options.stream = true; options.count = 2
        do {
            _ = try await client().generate(prompt: "late-error", options: options, references: [], mask: nil,
                credentials: APICredentials(key: "fixture-only"), completedImage: { data, _ in await recorder.record(data) })
            XCTFail("Expected a late stream error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("스트림")) }
        let saved = await recorder.values; XCTAssertEqual(saved, [Data("final".utf8)])
    }
    func testInvalidAttachmentFailsBeforeSubmission() async throws {
        let recorder = PreviewRecorder()
        do {
            _ = try await client().generate(prompt: "edit", options: ImageAPIOptions(),
                references: [URL(fileURLWithPath: "/nonexistent-imageflow-fixture.png")], mask: nil,
                credentials: APICredentials(key: "fixture-only"), willSend: { await recorder.record(Data()) })
            XCTFail("Expected local validation failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("PNG")) }
        let submissions = await recorder.values; XCTAssertTrue(submissions.isEmpty)
    }
    func testMultipartEditUsesEditEndpoint() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("input.png"); try ImageAPITests.png().write(to: file)
        let result = try await client().generate(prompt: "edit", options: ImageAPIOptions(), references: [file], mask: file, credentials: APICredentials(key: "fixture-only"))
        XCTAssertEqual(result.images.count, 1)
    }
}
private actor PreviewRecorder { var values: [Data] = []; func record(_ data: Data) { values.append(data) } }
private final class APIProtocolFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "api.openai.com", request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only" else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let path = request.url!.path
        if path == "/v1/models" {
            respond(#"{"data":[{"id":"gpt-image-2.5-flare"}]}"#); return
        }
        guard request.httpMethod == "POST" else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        if path == "/v1/images/edits" {
            guard request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
            respond(#"{"data":[{"b64_json":"aGk="}]}"#); return
        }
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var content = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; content.append(buffer, count: count) }; data = content
        } else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["model"] as? String == ImageAPIOptions.modelID else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        if json["prompt"] as? String == "limit" { respond(#"{"error":{"message":"do not expose fixture-only"}}"#, status: 429); return }
        if json["prompt"] as? String == "late-error" {
            respond("data: {\"type\":\"image_generation.completed\",\"b64_json\":\"ZmluYWw=\"}\n\ndata: {\"type\":\"error\"}\n\n", contentType: "text/event-stream"); return
        }
        if json["stream"] as? Bool == true {
            respond("data: {\"type\":\"image_generation.partial_image\",\"b64_json\":\"cHJldmlldw==\"}\n\ndata: {\"type\":\"image_generation.completed\",\"b64_json\":\"ZmluYWw=\"}\n\n", contentType: "text/event-stream")
        } else { respond(#"{"data":[{"b64_json":"aGk="}]}"#) }
    }
    private func respond(_ text: String, status: Int = 200, contentType: String = "application/json") {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":contentType,"x-request-id":"req_fixture"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
