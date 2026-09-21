import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import FlowCore

final class ImageAPITests: XCTestCase {
    func testAPIJobsSnapshotOptionsAndDoNotAppendWebDirectives() throws {
        var p = Project(name: "API"); p.prompt = "teapot"; p.copies = 2; p.generationMode = .sunburstAPI
        p.aspect = "16:9"; p.background = .transparent
        var options = ImageAPIOptions(); options.count = 3; options.quality = "max"; p.apiOptions = options
        let jobs = try JobRules.makeBatch(project: p)
        p.apiOptions?.quality = "low"
        XCTAssertEqual(jobs.count, 2); XCTAssertEqual(jobs[0].expectedImageCount, 3)
        XCTAssertEqual(jobs[0].prompt, "teapot"); XCTAssertEqual(jobs[0].apiOptions?.quality, "max")
        let restored = try JSONDecoder().decode(Job.self, from: JSONEncoder().encode(jobs[0]))
        XCTAssertEqual(restored.apiOptions, options)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(restored), as: UTF8.self).contains("Authorization"))
    }
    func testLegacySelectionNeverBecomesPaidAndFrozenReasoningSurvives() {
        XCTAssertEqual(GenerationMode.sunburstExperimental.selectable, .automatic)
        XCTAssertFalse(GenerationMode.allCases.contains(.sunburstExperimental))
        var old = Job(batchID: UUID(), projectID: UUID(), prompt: "old", label: "old", referenceIDs: [])
        old.generationMode = .automatic; old.reasoning = .light
        XCTAssertEqual(old.executionReasoning, .light)
        XCTAssertEqual(GenerationMode.automatic.reasoning.rawValue, 3)
        XCTAssertEqual(GenerationMode.instant.reasoning.rawValue, 0)
        XCTAssertNil(old.apiOptions)
    }
    func testSizeAndFormatValidation() throws {
        var o = ImageAPIOptions()
        for size in ImageAPIOptions.sizes { o.size = size; XCTAssertNoThrow(try o.validate(prompt: "test", referenceCount: 0), size) }
        for size in ["1025x1024", "32x32", "3840x3840", "4000x1024", "500x2000", "0x1024", "garbage", "1024xgarbagex1024", "1024xx1024", "+1024x1024", "1024x1024x"] {
            o.size = size; XCTAssertThrowsError(try o.validate(prompt: "test", referenceCount: 0), size)
        }
        o.size = "auto"; o.background = "transparent"; o.outputFormat = "jpeg"
        XCTAssertThrowsError(try o.validate(prompt: "test", referenceCount: 0))
        o.outputFormat = "webp"; XCTAssertNoThrow(try o.validate(prompt: "test", referenceCount: 0))
        o.maskAssetID = UUID(); XCTAssertThrowsError(try o.validate(prompt: "test", referenceCount: 0))
        XCTAssertThrowsError(try o.validate(prompt: "test", referenceCount: 17))
    }
    func testAllApplicableParametersAreRepresented() {
        var o = ImageAPIOptions(); o.quality = "xhigh"; o.outputFormat = "webp"; o.compression = 73
        o.inputFidelity = "high"; o.moderation = "low"; o.stream = true; o.partialImages = 3; o.user = "designer-1"
        let p = o.parameters(prompt: "edit", editing: true)
        XCTAssertEqual(Set(p.keys), Set(["model","prompt","n","quality","size","background","output_format","output_compression","input_fidelity","moderation","stream","partial_images","user"]))
        XCTAssertEqual(p["quality"] as? String, "xhigh"); XCTAssertEqual(p["output_compression"] as? Int, 73)
        o.stream = false; o.outputFormat = "png"; o.user = ""
        let simple = o.parameters(prompt: "new", editing: false)
        for key in ["input_fidelity","output_compression","partial_images","user","style","response_format"] { XCTAssertNil(simple[key]) }
    }
    func testStreamSeparatesPreviewsFromFinalAndReportsErrors() throws {
        var parser = ImageAPIStreamParser()
        XCTAssertNil(try parser.consume("data: {\"type\":\"image_generation.partial_image\",\"b64_json\":\"aGk=\"}"))
        XCTAssertEqual(try parser.consume(""), Data("hi".utf8)); XCTAssertTrue(parser.images.isEmpty)
        _ = try parser.consume("data: {\"type\":\"image_generation.completed\",\"b64_json\":\"b2s=\",\"usage\":{\"total_tokens\":12}}")
        XCTAssertNil(try parser.consume("")); XCTAssertEqual(parser.images, [Data("ok".utf8)])
        XCTAssertTrue(parser.usageJSON?.contains("12") == true)
        _ = try parser.consume("data: {\"type\":\"error\"}")
        XCTAssertThrowsError(try parser.consume(""))
    }
    func testResponseAndErrorDoNotExposeRemoteSecrets() throws {
        let result = try ImageAPIClient.decode(Data(#"{"data":[{"b64_json":"aGk="}],"usage":{"total_tokens":42}}"#.utf8), requestID: "req_test")
        XCTAssertEqual(result.images, [Data("hi".utf8)]); XCTAssertEqual(result.requestID, "req_test")
        XCTAssertThrowsError(try ImageAPIClient.decode(Data(#"{"data":[]}"#.utf8), requestID: nil))
        let response = HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 429, httpVersion: nil, headerFields: ["x-request-id":"req_limit"])!
        XCTAssertThrowsError(try ImageAPIClient.check(response)) { XCTAssertTrue($0.localizedDescription.contains("사용 한도")) }
    }
    func testAPIIdentityIsExplicitAndSurvivesReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = AssetVault(root: root)
        let asset = try await vault.store(Self.png(), projectID: UUID(), title: "API", isReference: false, jobID: UUID(), apiModel: ImageAPIOptions.modelID)
        XCTAssertEqual(asset.actualModelLabel, "Sunburst · API")
        let receipts = try await vault.receipts(); XCTAssertEqual(receipts.first?.apiModel, ImageAPIOptions.modelID)
    }
    func testMultipartReferencesMaskAndBooleans() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("image.png"), body = root.appendingPathComponent("body")
        try Self.png().write(to: image)
        try ImageAPIClient.multipart(parameters: ["stream":false,"prompt":"한글 test"], references: [image,image], mask: image, boundary: "BOUNDARY", to: body)
        let text = String(decoding: try Data(contentsOf: body), as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "name=\"image[]\"").count-1, 2)
        XCTAssertTrue(text.contains("name=\"mask\"")); XCTAssertTrue(text.contains("\r\nfalse\r\n")); XCTAssertTrue(text.contains("한글 test"))
    }
    static func png() -> Data {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData(); let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil); CGImageDestinationFinalize(dest); return data as Data
    }
}
