import Foundation

/// Output-only estimate. Official price tables/calculator verified 2026-09-26.
/// Input tokens are billed separately; `auto` size uses a clearly labeled 1K example.
public struct ImageCostEstimate: Equatable, Sendable {
    public let lowerUSD: Double
    public let upperUSD: Double
    public let usesExampleSize: Bool
    public static let source = URL(string: "https://developers.openai.com/api/docs/guides/image-generation#cost-and-latency")!
    public static func calculate(_ options: ImageAPIOptions, requests: Int = 1) -> Self? {
        guard let model = options.modelInfo, (1...10).contains(options.count), requests > 0 else { return nil }
        let size = options.size == "auto" ? "1024x1024" : options.size
        let dims = size.split(separator: "x").compactMap { Int($0) }
        guard dims.count == 2, dims.allSatisfy({ (1...3840).contains($0) }) else { return nil }
        let width = dims[0], height = dims[1]
        let qualities = options.quality == "auto" ? model.qualities.filter { $0 != "auto" } : [options.quality]
        let prices: [Double] = qualities.compactMap { quality in
            if model.flexibleSize {
                let scales = model.extendedQuality ? ["low":16.0,"medium":24,"high":48,"xhigh":64,"max":96] : ["low":16.0,"medium":48,"high":96]
                guard let scale = scales[quality] else { return nil }
                let ratio = Double(max(width,height)) / Double(min(width,height))
                let short = (scale / ratio).rounded(.toNearestOrEven)
                let tokens = ceil(scale * short * (2_000_000 + Double(width*height)) / 4_000_000)
                let rate = model.extendedQuality ? 30.0 : 15.0
                let partial = options.stream ? Double(options.partialImages) * 100 * rate / 1_000_000 : 0
                return tokens * rate / 1_000_000 + partial
            }
            guard ["1024x1024","1024x1536","1536x1024"].contains(size) else { return nil }
            let square = width == height
            let table: [String: Double]
            switch model.id {
            case "gpt-image-1": table = square ? ["low":0.011,"medium":0.042,"high":0.167] : ["low":0.016,"medium":0.063,"high":0.25]
            case "gpt-image-1-mini": table = square ? ["low":0.005,"medium":0.011,"high":0.036] : ["low":0.006,"medium":0.015,"high":0.052]
            default: table = square ? ["low":0.009,"medium":0.034,"high":0.133] : ["low":0.013,"medium":0.05,"high":0.20]
            }
            let rate = model.id == "gpt-image-1" ? 40.0 : model.id == "gpt-image-1-mini" ? 8.0 : 32.0
            return table[quality].map { $0 + (options.stream ? Double(options.partialImages) * 100 * rate / 1_000_000 : 0) }
        }
        guard let low = prices.min(), let high = prices.max(), prices.count == qualities.count else { return nil }
        let count = Double(options.count) * Double(requests)
        return Self(lowerUSD: low*count, upperUSD: high*count, usesExampleSize: options.size == "auto")
    }
    public var label: String {
        func usd(_ value: Double) -> String { value.formatted(.currency(code: "USD").precision(.fractionLength(3))) }
        return abs(upperUSD-lowerUSD) < 0.000001 ? "약 \(usd(lowerUSD))" : "\(usd(lowerUSD))–\(usd(upperUSD))"
    }
}
