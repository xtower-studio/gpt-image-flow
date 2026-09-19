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
    public var model: ImageModel? {
        // Only gen_size identifies the model. gen_size_v2 is retained as raw
        // metadata for compatibility and must never override this field.
        switch genSize {
        case "smimage": .flare
        case "image": .sunburst
        default: nil
        }
    }
}
