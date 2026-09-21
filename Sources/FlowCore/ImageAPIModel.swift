import Foundation

/// Images API catalog verified against the official documentation on 2026-09-22.
/// Retired DALL·E endpoints are intentionally absent. Account access is separate.
public struct ImageAPIModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public var snapshot: String? = nil
    public var retirement: String? = nil
    public var flexibleSize = false
    public var extendedQuality = false
    public var adjustableFidelity = true
    public var qualities: [String] { extendedQuality ? ImageAPIOptions.qualities : ["auto", "low", "medium", "high"] }
    public var sizes: [String] { flexibleSize ? ImageAPIOptions.sizes : ["auto", "1024x1024", "1536x1024", "1024x1536"] }
    public var versions: [String] { [id] + (snapshot.map { [$0] } ?? []) }
    public var hasRetired: Bool {
        guard let retirement, let date = ISO8601DateFormatter().date(from: retirement + "T00:00:00Z") else { return false }
        return Date() >= date
    }
    public static let all: [Self] = [
        .init(id: "gpt-image-2.5-sunburst", name: "Sunburst", summary: "정교한 표현과 세밀한 이미지 수정", snapshot: "gpt-image-2.5-sunburst-2026-09-08", flexibleSize: true, extendedQuality: true),
        .init(id: "gpt-image-2.5-flare", name: "Flare", summary: "빠른 생성과 일상적인 디자인 작업", snapshot: "gpt-image-2.5-flare-2026-09-08", flexibleSize: true, extendedQuality: true),
        .init(id: "gpt-image-2", name: "GPT Image 2", summary: "이전 세대 · 다양한 비율과 해상도", snapshot: "gpt-image-2-2026-04-21", flexibleSize: true, adjustableFidelity: false),
        .init(id: "gpt-image-1.5", name: "GPT Image 1.5", summary: "이전 세대 이미지 모델", retirement: "2026-12-01"),
        .init(id: "gpt-image-1", name: "GPT Image 1", summary: "이전 세대 이미지 모델", retirement: "2026-10-23"),
        .init(id: "gpt-image-1-mini", name: "GPT Image 1 Mini", summary: "이전 세대 소형 이미지 모델", retirement: "2026-12-01"),
        .init(id: "chatgpt-image-latest", name: "ChatGPT Image (이전)", summary: "이전 ChatGPT 이미지 스냅샷", retirement: "2026-12-01")
    ]
    public static func resolve(_ id: String) -> Self? { all.first { $0.versions.contains(id) } }
    public static func label(_ id: String) -> String { resolve(id)?.name ?? id }
}

public enum ImageAPISize {
    /// K describes the longer edge (rounded to the nearest half K); 3840 is 4K UHD.
    public static func label(_ size: String) -> String {
        if size == "auto" { return "자동" }
        let parts = size.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ (1...3840).contains($0) }) else { return "사용자 지정" }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let d = gcd(parts[0], parts[1]), longest = max(parts[0], parts[1])
        let k = Double(longest) / 1024
        let rounded = (k * 2).rounded() / 2
        let resolution = longest == 3840 ? "4" : (rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded))
        return "\(parts[0]/d):\(parts[1]/d) · \(resolution)K"
    }
}
