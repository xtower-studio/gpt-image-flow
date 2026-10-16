import Foundation

public enum AssetPaths {
    public static func component(_ text: String) -> String {
        let value = text.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t").union(.controlCharacters)).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String((value.isEmpty ? "Untitled" : value).prefix(60))
    }
    public static func projectFolder(name: String, id: UUID) -> String { String(component(name).prefix(40)) + " — " + id.uuidString.prefix(8) }
    public static func relativePath(_ asset: Asset, folder: String) -> String {
        let ext = URL(fileURLWithPath: asset.filename).pathExtension
        return "\(component(folder))/\(component(asset.title)).\(ext)"
    }
    public static func availablePath(_ asset: Asset, folder: String, root: URL, reserved: Set<String> = []) -> String {
        let base = relativePath(asset, folder: folder)
        var path = base, index = 2
        while reserved.contains(path.lowercased()) || FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
            let url = URL(fileURLWithPath: base)
            path = "\(component(folder))/\(url.deletingPathExtension().lastPathComponent) (\(index)).\(url.pathExtension)"; index += 1
        }
        return path
    }
    /// Recover files manually moved within the library using their persistent ID
    /// and digest. Never accept a filename match without checking the original bytes.
    public static func recoverOriginal(_ asset: Asset, in root: URL) throws -> URL {
        let expected = try original(asset, in: root)
        if FileManager.default.fileExists(atPath: expected.path) { return expected }
        let candidates = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let url = candidates?.nextObject() as? URL {
            guard url.lastPathComponent.contains(asset.id.uuidString), url.pathExtension.lowercased() != "json",
                  url.resolvingSymlinksInPath().path.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/"),
                  let bytes = try? Data(contentsOf: url), AssetVault.hash(bytes) == asset.digest else { continue }
            return url
        }
        throw FlowError.message("원본을 찾을 수 없습니다: \(asset.title). 보관함 안으로 파일을 되돌린 뒤 다시 열어 주세요.")
    }
    public static func metadata(_ asset: Asset, in root: URL) throws -> URL {
        let original = try original(asset, in: root)
        return original.deletingLastPathComponent().appendingPathComponent(".imageflow/images/\(asset.id).json")
    }
    public static func relativePath(_ asset: Asset) -> String { asset.relativePath ?? "Originals/\(asset.filename)" }
    public static func original(_ asset: Asset, in root: URL) throws -> URL {
        let path = relativePath(asset), parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.contains("\\"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              parts.first?.hasPrefix(".") == false,
              parts.count == 2 || parts.first == "Projects",
              asset.relativePath != nil || parts.count == 2 else { throw FlowError.message("이미지 파일 경로가 올바르지 않습니다.") }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let result = base.appendingPathComponent(path).resolvingSymlinksInPath()
        guard result.path.hasPrefix(base.path + "/") else { throw FlowError.message("보관함 밖의 이미지 경로는 사용할 수 없습니다.") }
        return result
    }
}
