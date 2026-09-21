import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct APICredentials: Codable, Sendable {
    public var key: String
    public var organization: String
    public var project: String
    public init(key: String, organization: String = "", project: String = "") { self.key = key; self.organization = organization; self.project = project }
}
public struct ImageAPIError: LocalizedError, Sendable {
    public let status: Int
    public let requestID: String?
    public var errorDescription: String? {
        let message: String
        switch status {
        case 401: message = "API 키를 확인하세요. 키가 잘못되었거나 폐기되었습니다."
        case 403: message = "이 프로젝트에 선택한 모델 또는 요청 기능 권한이 없습니다. API 권한과 조직 인증을 확인하세요."
        case 404: message = "이 계정에서 선택한 모델을 찾을 수 없습니다. 모델 접근 권한을 확인하세요."
        case 429: message = "API 잔액 또는 사용 한도에 도달했습니다. 결제·사용량을 확인한 뒤 다시 요청하세요."
        case 400, 422: message = "API가 요청을 거절했습니다. 프롬프트, 이미지와 고급 옵션 조합을 확인하세요."
        default: message = "OpenAI API 응답 오류 (\(status)). 자동으로 재전송하지 않았습니다."
        }
        return message + (requestID.map { "\n요청 ID: \($0)" } ?? "")
    }
    public init(status: Int, requestID: String?) { self.status = status; self.requestID = requestID }
}
public struct ImageAPIResult: Sendable {
    public var images: [Data]
    public var requestID: String?
    public var usageJSON: String?
}

/// A session per operation prevents cookies, disk cache and credential forwarding.
public final class ImageAPIClient: Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCache = nil
            config.timeoutIntervalForRequest = 300; config.timeoutIntervalForResource = 900
            self.session = URLSession(configuration: config, delegate: NoAPIRedirect(), delegateQueue: nil)
        }
    }
    private func request(path: String, credentials: APICredentials) throws -> URLRequest {
        guard !credentials.key.isEmpty, [credentials.key, credentials.organization, credentials.project].allSatisfy({ !$0.contains("\n") && !$0.contains("\r") }) else { throw FlowError.message("API 연결 정보를 확인하세요.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/" + path)!)
        request.setValue("Bearer " + credentials.key, forHTTPHeaderField: "Authorization")
        if !credentials.organization.isEmpty { request.setValue(credentials.organization, forHTTPHeaderField: "OpenAI-Organization") }
        if !credentials.project.isEmpty { request.setValue(credentials.project, forHTTPHeaderField: "OpenAI-Project") }
        return request
    }
    public func verify(_ credentials: APICredentials) async throws {
        let request = try request(path: "models", credentials: credentials)
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["data"] is [[String: Any]] else { throw FlowError.message("OpenAI API 연결을 확인하지 못했습니다.") }
    }
    public static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw FlowError.message("API 응답을 읽을 수 없습니다.") }
        guard (200..<300).contains(http.statusCode) else { throw ImageAPIError(status: http.statusCode, requestID: http.value(forHTTPHeaderField: "x-request-id")) }
    }
    public func generate(prompt: String, options: ImageAPIOptions, references: [URL], mask: URL?, credentials: APICredentials,
                         preview: @escaping @Sendable (Data) async -> Void = { _ in },
                         willSend: @escaping @Sendable () async throws -> Void = {},
                         completedImage: @escaping @Sendable (Data, Int) async throws -> Void = { _, _ in }) async throws -> ImageAPIResult {
        try options.validate(prompt: prompt, referenceCount: references.count)
        let editing = !references.isEmpty
        var request = try request(path: editing ? "images/edits" : "images/generations", credentials: credentials)
        request.httpMethod = "POST"
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".multipart")
        defer { if FileManager.default.fileExists(atPath: temporary.path) { try? FileManager.default.removeItem(at: temporary) } }
        let parameters = options.parameters(prompt: prompt, editing: editing)
        if editing {
            let boundary = "ImageFlow-" + UUID().uuidString
            try Self.multipart(parameters: parameters, references: references, mask: mask, boundary: boundary, to: temporary)
            request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
            request.setValue(String(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), forHTTPHeaderField: "Content-Length")
            request.httpBodyStream = InputStream(url: temporary)
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        }
        try await willSend()
        if options.stream {
            let (bytes, response) = try await session.bytes(for: request)
            try Self.check(response)
            var parser = ImageAPIStreamParser()
            // AsyncBytes.lines discards empty lines; SSE requires blank event boundaries.
            var line = Data()
            var delivered = 0
            for try await byte in bytes {
                if byte == 10 {
                    try Task.checkCancellation()
                    if let partial = try parser.consume(String(decoding: line, as: UTF8.self)) { await preview(partial) }
                    while delivered < parser.images.count {
                        try await completedImage(parser.images[delivered], delivered); delivered += 1
                    }
                    line.removeAll(keepingCapacity: true)
                } else if byte != 13 {
                    line.append(byte)
                    guard line.count < 100 * 1024 * 1024 else { throw FlowError.message("API 스트림 이미지가 너무 큽니다.") }
                }
            }
            if !line.isEmpty { _ = try parser.consume(String(decoding: line, as: UTF8.self)) }
            _ = try parser.consume("")
            while delivered < parser.images.count { try await completedImage(parser.images[delivered], delivered); delivered += 1 }
            guard !parser.images.isEmpty else { throw FlowError.message("API 스트림에 완성된 이미지가 없습니다. 사용량을 확인하세요.") }
            return ImageAPIResult(images: parser.images, requestID: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-request-id"), usageJSON: parser.usageJSON)
        }
        let data: Data, response: URLResponse
        if editing {
            request.httpBodyStream = nil
            (data, response) = try await session.upload(for: request, fromFile: temporary)
        } else { (data, response) = try await session.data(for: request) }
        try Self.check(response)
        return try Self.decode(data, requestID: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-request-id"))
    }
    public static func decode(_ data: Data, requestID: String?) throws -> ImageAPIResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let entries = object["data"] as? [[String: Any]], !entries.isEmpty else { throw FlowError.message("API가 이미지를 반환하지 않았습니다. 사용량을 확인하세요.") }
        let images = try entries.map { entry -> Data in
            guard let encoded = entry["b64_json"] as? String, let image = Data(base64Encoded: encoded), !image.isEmpty else { throw FlowError.message("API 이미지 데이터를 읽을 수 없습니다.") }
            return image
        }
        return ImageAPIResult(images: images, requestID: requestID, usageJSON: jsonString(object["usage"]))
    }
    static func jsonString(_ object: Any?) -> String? {
        guard let object, JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public static func multipart(parameters: [String: Any], references: [URL], mask: URL?, boundary: String, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        func write(_ string: String) throws { try output.write(contentsOf: Data(string.utf8)) }
        for key in parameters.keys.sorted() {
            let value = parameters[key]!
            let text = (key == "stream") ? ((value as? Bool == true) ? "true" : "false") : String(describing: value)
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(text)\r\n")
        }
        func imageInfo(_ url: URL) throws -> (String, Int, Int, Bool) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) as String?, let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, let mime = UTType(type)?.preferredMIMEType, ["image/png", "image/jpeg", "image/webp"].contains(mime), (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 50*1024*1024 else { throw FlowError.message("API 입력은 50MB 미만 PNG·JPEG·WebP 이미지여야 합니다.") }
            return (mime, w, h, props[kCGImagePropertyHasAlpha] as? Bool == true)
        }
        if let mask {
            guard let first = references.first else { throw FlowError.message("마스크의 원본 참조를 추가하세요.") }
            let m = try imageInfo(mask), base = try imageInfo(first)
            guard m.0 == "image/png", m.1 == base.1, m.2 == base.2, m.3 else { throw FlowError.message("마스크는 첫 참조와 크기가 같은 투명 채널이 있는 PNG여야 합니다.") }
        }
        for (index, file) in (references.map { ("image[]", $0) } + (mask.map { [("mask", $0)] } ?? [])).enumerated() {
            let info = try imageInfo(file.1)
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.0)\"; filename=\"input-\(index)\"\r\nContent-Type: \(info.0)\r\n\r\n")
            let input = try FileHandle(forReadingFrom: file.1); defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1024*1024), !chunk.isEmpty { try output.write(contentsOf: chunk) }
            try write("\r\n")
        }
        try write("--\(boundary)--\r\n")
    }
}
private final class NoAPIRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct ImageAPIStreamParser {
    public private(set) var images: [Data] = []
    public private(set) var usageJSON: String?
    private var buffer = ""
    public init() {}
    public mutating func consume(_ line: String) throws -> Data? {
        if line.hasPrefix("data:") { buffer += line.dropFirst(5).trimmingCharacters(in: .whitespaces) + "\n"; return nil }
        guard line.isEmpty, !buffer.isEmpty else { return nil }
        let payload = buffer.trimmingCharacters(in: .whitespacesAndNewlines); buffer = ""
        if payload == "[DONE]" { return nil }
        guard let json = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return nil }
        let type = json["type"] as? String ?? ""
        if json["error"] != nil || type == "error" { throw FlowError.message("이미지 생성 스트림이 오류로 종료되었습니다. 자동 재전송하지 않았습니다.") }
        if let usage = ImageAPIClient.jsonString(json["usage"]) { usageJSON = usage }
        guard let encoded = json["b64_json"] as? String, let bytes = Data(base64Encoded: encoded) else { return nil }
        if type.hasSuffix(".completed") { images.append(bytes) }
        else if type.hasSuffix(".partial_image") { return bytes }
        return nil
    }
}
