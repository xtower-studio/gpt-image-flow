import Foundation

extension AssetVault {
    public func copyRenamed(_ original: Asset, title: String, folder: String) throws -> Asset {
        var asset = original; asset.title = AssetPaths.component(title)
        asset.relativePath = AssetPaths.availablePath(asset, folder: folder, root: root)
        let source = try AssetPaths.original(original, in: root), target = try AssetPaths.original(asset, in: root)
        let bytes = try Data(contentsOf: source)
        guard Self.hash(bytes) == original.digest else { throw FlowError.message("원본을 확인하지 못해 이름을 바꾸지 않았습니다.") }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
        guard Self.hash(try Data(contentsOf: target)) == original.digest else { throw FlowError.message("이름을 바꾼 파일을 검증하지 못했습니다. 기존 원본을 보존했습니다.") }
        asset.filename = target.lastPathComponent
        asset.title = target.deletingPathExtension().lastPathComponent
        return asset
    }
    public func removeSupersededFile(_ old: Asset, replacement: Asset) throws {
        let source = try AssetPaths.original(old, in: root), target = try AssetPaths.original(replacement, in: root)
        guard source != target, Self.hash(try Data(contentsOf: target)) == old.digest else { return }
        try FileManager.default.removeItem(at: source)
    }
}
