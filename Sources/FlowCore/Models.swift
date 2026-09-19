import Foundation

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var createdAt = Date()
    public var prompt = ""
    public var variations = ""
    public var copies = 1
    public var aspect = "자유"
    public var background: BackgroundOption?
    public var referenceIDs: [UUID] = []
    public var reasoning: ReasoningLevel?
    public var imageModel: ImageModel?
    public var layout: [String: CanvasPoint]?
    public var viewport: CanvasViewport?
    public init(name: String) { self.name = name }
}

public struct Asset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var filename: String
    public var title: String
    public var width: Int
    public var height: Int
    public var digest: String
    public var createdAt: Date
    public var isReference: Bool
    public var isFavorite: Bool
    public var jobID: UUID?
    public var parentID: UUID?
    public init(id: UUID = UUID(), projectID: UUID, filename: String, title: String,
                width: Int, height: Int, digest: String, isReference: Bool,
                jobID: UUID? = nil, parentID: UUID? = nil) {
        self.id = id; self.projectID = projectID; self.filename = filename; self.title = title
        self.width = width; self.height = height; self.digest = digest; self.isReference = isReference
        self.jobID = jobID; self.parentID = parentID; createdAt = Date(); isFavorite = false
    }
}

public enum JobState: String, Codable, CaseIterable, Sendable {
    case queued, preparing, uploading, submitting, generating, collecting, saved
    case needsLogin, needsReview, failed, cancelled, responded
    public var label: String {
        switch self {
        case .queued: "대기 중"
        case .preparing: "작업 준비"
        case .uploading: "참조 첨부 중"
        case .submitting: "요청 전송 중"
        case .generating: "이미지 생성 중"
        case .collecting: "원본 저장 중"
        case .saved: "완료"
        case .needsLogin: "로그인 필요"
        case .needsReview: "상태 확인 필요"
        case .failed: "생성 실패"
        case .responded: "답변 도착"
        case .cancelled: "취소됨"
        }
    }
    public var isRunning: Bool { [.preparing, .uploading, .submitting, .generating, .collecting].contains(self) }
    public var needsAttention: Bool { [.needsLogin, .needsReview, .failed, .responded].contains(self) }
}

public struct Job: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var batchID: UUID
    public var projectID: UUID
    public var prompt: String
    public var label: String
    public var referenceIDs: [UUID]
    public var parentID: UUID?
    public var state: JobState = .queued
    public var createdAt = Date()
    public var startedAt: Date?
    public var conversationID: String?
    public var responseID: String?
    public var error: String?
    public var results: [Asset] = []
    public var reasoning: ReasoningLevel?
    public var imageModel: ImageModel?
    public var dismissedAttentionState: JobState?
    public var showsAttention: Bool { state.needsAttention && dismissedAttentionState != state }
    public var requestedModel: ImageModel { imageModel ?? (reasoning == nil || reasoning == .standard ? .sunburst : .flare) }
    public var appliedReasoning: Int?
    public var continuationOf: UUID?
    public var responseText: String?
    public var excludedFileIDs: [String]?
    public var baselineAssistantCount: Int?
    public var submittedAt: Date?
    public var finishedAt: Date?
    public init(batchID: UUID, projectID: UUID, prompt: String, label: String,
                referenceIDs: [UUID], parentID: UUID? = nil) {
        self.batchID = batchID; self.projectID = projectID; self.prompt = prompt
        self.label = label; self.referenceIDs = referenceIDs; self.parentID = parentID
    }
    public var conversationURL: URL? {
        guard let conversationID, UUID(uuidString: conversationID) != nil else { return nil }
        return URL(string: "https://chatgpt.com/c/\(conversationID)")
    }
}

public struct Library: Codable, Sendable {
    public var schemaVersion = 1
    public var projects: [Project] = []
    public var assets: [Asset] = []
    public var preferredModel: ImageModel?
    public var recipes: [Recipe]?
    public var hiddenAssetIDs: [UUID]?
    public init() {}
    // Journal/receipt snapshots recover missing files, but must not undo later user edits.
    public mutating func restoreMissingAssets(_ recovered: [Asset]) {
        var known = Set(assets.map(\.id))
        for asset in recovered where known.insert(asset.id).inserted { assets.append(asset) }
    }
}

public enum FlowError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
