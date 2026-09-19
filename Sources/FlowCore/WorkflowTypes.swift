import Foundation

/// User-facing image models. Keep routing separate from any quality ranking.
public enum ImageModel: String, Codable, CaseIterable, Sendable {
    case flare, sunburst
    public var label: String { self == .flare ? "Flare" : "Sunburst" }
    public var reasoning: ReasoningLevel { self == .flare ? .instant : .standard }
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

// Retained for decoding historical requests; new requests use ImageModel.
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
