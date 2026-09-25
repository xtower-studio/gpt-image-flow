import Foundation

/// Per-file evidence from content.parts[i].metadata.generation, never request settings.
public struct ImageGenerationMetadata: Codable, Equatable, Sendable {
    public let fileID: String
    public let messageID: String
    public let genSize: String?
    public let genSizeV2: String?
    public init(fileID: String, messageID: String, genSize: String?, genSizeV2: String?) {
        self.fileID = fileID; self.messageID = messageID; self.genSize = genSize; self.genSizeV2 = genSizeV2
    }
    // Undocumented web metadata is not evidence of model identity.
    public var model: ImageModel? { nil }
    // Gallery containers can repeat the same message ID for each image. Match
    // earlier captures as well as the normalized ID used after a page reload.
    public func matches(fileID candidate: String) -> Bool {
        if fileID == candidate { return true }
        let messages = messageID.split(whereSeparator: { $0.isWhitespace })
        guard fileID.hasPrefix("generated-"), let first = messages.first,
              UUID(uuidString: String(first)) != nil, messages.allSatisfy({ $0 == first }),
              let ordinal = fileID.split(separator: "-").last, Int(ordinal) != nil else { return false }
        return candidate == "generated-\(first)-\(ordinal)"
    }
}
