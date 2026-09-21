import Foundation

/// Human-facing choices backed by sizes supported by the selected model.
public enum ImageSizeSelection {
    public static func sizes(for options: ImageAPIOptions) -> [String] {
        let presets = options.modelInfo?.sizes ?? ImageAPIOptions.sizes
        return presets.filter { $0 != "auto" } + (options.modelInfo?.flexibleSize == true ? ["2016x1344", "1344x2016"] : [])
    }
    public static func aspect(_ size: String) -> String {
        guard size != "auto" else { return "자동" }
        return ImageAPISize.label(size).components(separatedBy: " · ").first ?? "사용자 지정"
    }
    public static func resolution(_ size: String) -> String {
        guard size != "auto" else { return "자동" }
        return ImageAPISize.label(size).components(separatedBy: " · ").dropFirst().first ?? "사용자 지정"
    }
    public static func aspects(for options: ImageAPIOptions) -> [String] {
        unique(sizes(for: options).map(aspect))
    }
    public static func resolutions(for options: ImageAPIOptions) -> [String] {
        let candidates = sizes(for: options).filter { options.size == "auto" || aspect($0) == aspect(options.size) }
        return unique(candidates.map(resolution))
    }
    public static func selectingAspect(_ value: String, in options: ImageAPIOptions) -> String {
        guard value != "자동" else { return "auto" }
        let candidates = sizes(for: options).filter { aspect($0) == value }
        return candidates.first { resolution($0) == resolution(options.size) } ?? candidates.first ?? options.size
    }
    public static func selectingResolution(_ value: String, in options: ImageAPIOptions) -> String {
        guard value != "자동" else { return "auto" }
        let candidates = sizes(for: options).filter { resolution($0) == value }
        return candidates.first { aspect($0) == aspect(options.size) } ?? candidates.first ?? options.size
    }
    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
