import Foundation

/// Actual output names, also retained to decode old model preferences.
public enum ImageModel: String, Codable, CaseIterable, Sendable {
    case flare, sunburst
    public var label: String { self == .flare ? "Flare" : "Sunburst" }
}
public enum GenerationMode: String, Codable, CaseIterable, Sendable {
    case automatic, sunburstExperimental, sunburstAPI, instant
    public static let allCases: [Self] = [.automatic, .sunburstAPI, .instant]
    public var selectable: Self { self == .sunburstExperimental ? .automatic : self }
    public var label: String {
        switch self { case .automatic: "자동"; case .sunburstExperimental: "이전 Sunburst 실험"; case .sunburstAPI: "고급"; case .instant: "빠르게" }
    }
    public var imagesPerRequest: Int {
        switch self { case .automatic: 4; case .sunburstExperimental: 2; case .sunburstAPI: 2; case .instant: 1 }
    }
    public var explanation: String {
        switch self {
        case .automatic: "가장 적절한 모델을 자동으로 선택합니다. 한 번에 4장을 생성합니다."
        case .sunburstExperimental: "이전 ChatGPT 실험 방식입니다. 실제 모델은 확인할 수 없습니다."
        case .sunburstAPI: "OpenAI API로 직접 생성합니다. API 키와 별도 사용 요금이 필요합니다."
        case .instant: "가장 빠르고 저렴한 모델을 사용합니다. 한 번에 1장을 생성합니다."
        }
    }
    // Non-instant reasoning enables automatic routing; it does not select a model.
    public var reasoning: ReasoningLevel { self == .instant ? .instant : self == .automatic ? .extended : .light }
    public static func migrated(from legacy: ImageModel?) -> Self {
        switch legacy { case .flare: .instant; case .sunburst: .automatic; case nil: .automatic }
    }
}
public enum BackgroundOption: String, Codable, CaseIterable, Sendable {
    case automatic, transparent, opaque
    public var label: String {
        switch self { case .automatic: "자동"; case .transparent: "투명"; case .opaque: "불투명" }
    }
    public var promptOption: String? {
        switch self {
        case .automatic: nil
        case .transparent: "transparent_background: true"
        case .opaque: "transparent_background: false"
        }
    }
}

// Retained for decoding historical requests; new requests use GenerationMode.
public enum ReasoningLevel: Int, Codable, CaseIterable, Sendable {
    case instant = 0, light, standard, extended, heavy
    public var label: String {
        switch self {
        case .instant: "Instant · 빠르게"
        case .light: "추론 1 · 중간"
        case .standard: "추론 2 · 높음"
        case .extended: "추론 3 · 매우 높음"
        case .heavy: "추론 4 · 최대"
        }
    }
}
public struct CanvasPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
public struct CanvasViewport: Codable, Equatable, Sendable {
    public var x: Double = 40
    public var y: Double = 40
    public var scale: Double = 1
    public init(x: Double = 40, y: Double = 40, scale: Double = 1) { self.x = x; self.y = y; self.scale = scale }
    public func world(x: Double, y: Double) -> CanvasPoint { CanvasPoint(x: (x-self.x)/scale, y: (y-self.y)/scale) }
}
public struct Recipe: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var settings: Project
    public init(name: String, settings: Project) { self.name = name; self.settings = settings }
}
public enum QueueAdmission {
    public static func slots(limit: Int, occupied: Set<Int>, availableAt: [String: Date], now: Date) -> [Int] {
        guard occupied.count < limit else { return [] }
        return Array((0..<limit).filter { !occupied.contains($0) && (availableAt[String($0)] ?? .distantPast) <= now }.prefix(limit-occupied.count))
    }
    public static func canStart(_ job: Job, alongside running: [Job]) -> Bool {
        guard let conversation = job.conversationID else { return true }
        return !running.contains { $0.conversationID == conversation }
    }
}
