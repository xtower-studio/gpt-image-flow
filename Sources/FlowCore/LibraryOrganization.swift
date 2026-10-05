import Foundation

extension PortableLibrary {
    /// Publish verified new paths before removing any old originals. Safe to retry
    /// after interruption: identical destination files are reused, never overwritten.
    public func organized(in root: URL) throws -> Self {
        var result = self; result.version = 2
        for i in result.library.projects.indices where result.library.projects[i].storageFolder == nil {
            result.library.projects[i].storageFolder = AssetPaths.projectFolder(name: result.library.projects[i].name, id: result.library.projects[i].id)
        }
        let folders = Dictionary(result.library.projects.map { ($0.id, $0.storageFolder!) }, uniquingKeysWith: { a, _ in a })
        let fm = FileManager.default
        var oldFiles: [URL] = []
        for i in result.library.assets.indices {
            var asset = result.library.assets[i]
            guard asset.relativePath == nil else { continue }
            let old = try Self.original(asset, in: root)
            let bytes = try Data(contentsOf: old, options: .mappedIfSafe)
            guard AssetVault.hash(bytes) == asset.digest else { throw FlowError.message("원본 검증에 실패했습니다: \(asset.title)") }
            asset.relativePath = AssetPaths.relativePath(asset, folder: folders[asset.projectID] ?? asset.projectID.uuidString)
            let target = try Self.original(asset, in: root)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                guard AssetVault.hash(try Data(contentsOf: target)) == asset.digest else { throw FlowError.message("정리할 위치에 다른 파일이 있습니다: \(asset.title)") }
            } else { try fm.copyItem(at: old, to: target) }
            guard AssetVault.hash(try Data(contentsOf: target)) == asset.digest else { throw FlowError.message("복사한 파일을 검증하지 못했습니다.") }
            result.library.assets[i] = asset; oldFiles.append(old)
        }
        let assets = Dictionary(result.library.assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in result.journal.jobs.indices { result.journal.jobs[i].results = result.journal.jobs[i].results.map { assets[$0.id] ?? $0 } }
        try result.journal.save(root.appendingPathComponent("Jobs.json"))
        try result.save(to: root)
        // Receipts must adopt the new paths before old files are removed.
        let receipts = root.appendingPathComponent("Receipts")
        try fm.createDirectory(at: receipts, withIntermediateDirectories: true)
        for asset in result.library.assets { try JSONEncoder().encode(asset).write(to: receipts.appendingPathComponent("\(asset.id).json"), options: .atomic) }
        // A prior process may have published the new manifest before cleanup.
        // Remove those leftover copies only when their contents still match.
        for asset in result.library.assets where asset.relativePath != nil {
            var legacy = asset; legacy.relativePath = nil
            if let old = try? Self.original(legacy, in: root),
               let bytes = try? Data(contentsOf: old), AssetVault.hash(bytes) == asset.digest {
                oldFiles.append(old)
            }
        }
        for old in Set(oldFiles) { try? fm.removeItem(at: old); try? fm.removeItem(at: old.deletingPathExtension().appendingPathExtension("json")) }
        // Remove only derived files belonging to known assets, never unrelated files.
        for asset in result.library.assets {
            try? fm.removeItem(at: root.appendingPathComponent("Thumbnails/\(asset.id).png"))
            try? fm.removeItem(at: root.appendingPathComponent("Metadata/\(asset.id).json"))
        }
        for folder in ["Originals", "Thumbnails", "Metadata"] {
            let url = root.appendingPathComponent(folder)
            if let contents = try? fm.contentsOfDirectory(atPath: url.path), contents.isEmpty { try? fm.removeItem(at: url) }
        }
        return result
    }
}
