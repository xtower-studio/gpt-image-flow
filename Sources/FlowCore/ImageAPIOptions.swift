import Foundation

public struct ImageAPIOptions: Codable, Equatable, Sendable {
    public static let modelID = "gpt-image-2.5-sunburst"
    public static let snapshotID = "gpt-image-2.5-sunburst-2026-09-08"
    public var model = modelID
    public var quality = "high"
    public var size = "auto"
    public var count = 2
    public var background = "auto"
    public var outputFormat = "png"
    public var compression = 100
    public var moderation = "auto"
    public var inputFidelity = "auto"
    public var stream = false
    public var partialImages = 0
    public var user = ""
    public var maskAssetID: UUID?
    public init() {}
    public static let qualities = ["auto", "low", "medium", "high", "xhigh", "max"]
    public static let sizes = ["auto", "1024x1024", "1536x1024", "1024x1536", "1536x864", "864x1536", "2048x2048", "2048x1152", "1152x2048", "2560x1440", "3840x2160", "2160x3840"]
    public var modelInfo: ImageAPIModel? { ImageAPIModel.resolve(model) }
    public mutating func selectModel(_ id: String) {
        guard let info = ImageAPIModel.resolve(id) else { return }
        model = id
        if !info.qualities.contains(quality) { quality = "high" }
        if !info.flexibleSize && !info.sizes.contains(size) { size = "auto" }
        if !info.adjustableFidelity { inputFidelity = "auto" }
    }
    public func validate(prompt: String, referenceCount: Int) throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw FlowError.message(message) } }
        guard let info = modelInfo else { throw FlowError.message("지원하는 이미지 모델을 선택하세요.") }
        try require(!info.hasRetired, "제공이 종료된 모델입니다. 다른 이미지 모델을 선택하세요.")
        try require(!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prompt.count <= 32000, "API 프롬프트는 1~32,000자로 입력하세요.")
        try require((1...10).contains(count), "API 요청당 이미지는 1~10장입니다.")
        try require((0...16).contains(referenceCount), "API 참조 이미지는 최대 16개입니다.")
        try require(info.qualities.contains(quality), "선택한 모델이 지원하는 품질을 선택하세요.")
        try require(info.flexibleSize || info.sizes.contains(size), "이 모델은 자동, 1:1 · 1K, 3:2 · 1.5K, 2:3 · 1.5K 크기를 지원합니다.")
        try require(info.adjustableFidelity || inputFidelity == "auto", "이 모델은 입력 충실도를 자동으로 처리합니다.")
        try require(["auto", "opaque", "transparent"].contains(background), "배경 옵션을 확인하세요.")
        try require(["png", "jpeg", "webp"].contains(outputFormat), "이미지 형식을 확인하세요.")
        try require(!(background == "transparent" && outputFormat == "jpeg"), "투명 배경에는 PNG 또는 WebP를 선택하세요.")
        try require((0...100).contains(compression), "압축 값은 0~100입니다.")
        try require(["auto", "low"].contains(moderation), "필터 옵션을 확인하세요.")
        try require(["auto", "high", "low"].contains(inputFidelity), "입력 충실도를 확인하세요.")
        try require(referenceCount > 0 || (maskAssetID == nil && inputFidelity == "auto"), "마스크와 입력 충실도는 참조 이미지가 있을 때 사용합니다.")
        try require((0...3).contains(partialImages), "중간 이미지는 0~3개입니다.")
        if size != "auto" {
            let components = size.split(separator: "x", omittingEmptySubsequences: false)
            let parts = components.compactMap { Int($0) }
            try require(components.count == 2 && parts.count == 2 && components.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }, "크기는 가로x세로 형식으로 입력하세요. 예: 1536x864")
            let w = parts[0], h = parts[1]
            try require(w > 0 && h > 0 && w <= 3840 && h <= 3840 && w % 16 == 0 && h % 16 == 0, "각 변은 16의 배수이며 최대 3,840px입니다.")
            try require(max(w,h) <= min(w,h)*3 && (655360...8294400).contains(w*h), "비율은 1:3~3:1, 총 픽셀 수는 655,360~8,294,400이어야 합니다.")
        }
    }
    public func parameters(prompt: String, editing: Bool) -> [String: Any] {
        var result: [String: Any] = ["model": model, "prompt": prompt, "n": count, "quality": quality,
            "size": size, "background": background, "output_format": outputFormat, "moderation": moderation, "stream": stream]
        if outputFormat != "png" { result["output_compression"] = compression }
        if editing && inputFidelity != "auto" && modelInfo?.adjustableFidelity == true { result["input_fidelity"] = inputFidelity }
        if stream { result["partial_images"] = partialImages }
        if !user.isEmpty { result["user"] = user }
        return result
    }
}
