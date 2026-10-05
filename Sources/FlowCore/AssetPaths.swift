import Foundation

public enum AssetPaths {
    public static func component(_ text: String) -> String {
        let value = text.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t").union(.controlCharacters)).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String((value.isEmpty ? "Untitled" : value).prefix(60))
    }
    public static func projectFolder(name: String, id: UUID) -> String { String(component(name).prefix(40)) + " — " + id.uuidString.prefix(8) }
    public static func relativePath(_ asset: Asset, folder: String) -> String {
        let date = ISO8601DateFormatter().string(from: asset.createdAt).prefix(10)
        let category = asset.isReference ? "References" : "Generated/\(date)"
        let ext = URL(fileURLWithPath: asset.filename).pathExtension
        return "Projects/\(component(folder))/\(category)/\(component(asset.title)) — \(asset.id).\(ext)"
    }
    public static func relativePath(_ asset: Asset) -> String { asset.relativePath ?? "Originals/\(asset.filename)" }
    public static func original(_ asset: Asset, in root: URL) throws -> URL {
        let path = relativePath(asset), parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.contains("\\"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              parts.first == "Originals" || parts.first == "Projects",
              asset.relativePath != nil || parts.count == 2 else { throw FlowError.message("이미지 파일 경로가 올바르지 않습니다.") }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let result = base.appendingPathComponent(path).resolvingSymlinksInPath()
        guard result.path.hasPrefix(base.path + "/") else { throw FlowError.message("보관함 밖의 이미지 경로는 사용할 수 없습니다.") }
        return result
    }
}
