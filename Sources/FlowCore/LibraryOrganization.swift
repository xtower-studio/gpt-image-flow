import Foundation

extension PortableLibrary {
    /// Copy and verify every affected original before publishing paths. Existing
    /// unrelated files are never overwritten; interrupted copies can be reused.
    public func organized(in root: URL) throws -> Self {
        var result = self; result.version = 3
        AssetNaming.migrate(library: &result.library, jobs: &result.journal.jobs)
        for i in result.library.projects.indices where result.library.projects[i].storageFolder == nil {
            result.library.projects[i].storageFolder = AssetPaths.projectFolder(name: result.library.projects[i].name, id: result.library.projects[i].id)
        }
        let folders = Dictionary(result.library.projects.map { ($0.id, $0.storageFolder!) }, uniquingKeysWith: { a, _ in a })
        let fm = FileManager.default
        var oldFiles: [URL] = []
        var reserved = Set(result.library.assets.compactMap(\.relativePath).filter { !$0.hasPrefix("Projects/") && !$0.hasPrefix("Originals/") }.map { $0.lowercased() })
        for i in result.library.assets.indices {
            var asset = result.library.assets[i]
            guard asset.relativePath == nil || asset.relativePath!.hasPrefix("Projects/") || asset.relativePath!.hasPrefix("Originals/") else { continue }
            let old = try AssetPaths.recoverOriginal(asset, in: root)
            let bytes = try Data(contentsOf: old, options: .mappedIfSafe)
            guard AssetVault.hash(bytes) == asset.digest else { throw FlowError.message("원본 검증에 실패했습니다: \(asset.title)") }
            let folder = folders[asset.projectID] ?? asset.projectID.uuidString
            let preferred = AssetPaths.relativePath(asset, folder: folder)
            let candidate = root.appendingPathComponent(preferred)
            if !reserved.contains(preferred.lowercased()), let existing = try? Data(contentsOf: candidate), AssetVault.hash(existing) == asset.digest {
                asset.relativePath = preferred
            } else { asset.relativePath = AssetPaths.availablePath(asset, folder: folder, root: root, reserved: reserved) }
            let target = try Self.original(asset, in: root)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: old, to: target) }
            guard AssetVault.hash(try Data(contentsOf: target)) == asset.digest else { throw FlowError.message("복사한 파일을 검증하지 못했습니다.") }
            asset.filename = target.lastPathComponent
            asset.title = target.deletingPathExtension().lastPathComponent
            reserved.insert(asset.relativePath!.lowercased())
            result.library.assets[i] = asset; oldFiles.append(old)
        }
        let assets = Dictionary(result.library.assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in result.journal.jobs.indices { result.journal.jobs[i].results = result.journal.jobs[i].results.map { assets[$0.id] ?? $0 } }
        let hidden = root.appendingPathComponent(".imageflow")
        let receipts = hidden.appendingPathComponent("Receipts")
        try fm.createDirectory(at: receipts, withIntermediateDirectories: true)
        for asset in result.library.assets { try JSONEncoder().encode(asset).write(to: receipts.appendingPathComponent("\(asset.id).json"), options: .atomic) }
        // Retain the pre-migration manifest as a hidden recovery record.
        let previous = Self.manifestURL(in: root), backup = hidden.appendingPathComponent("before-v3.json")
        if !oldFiles.isEmpty, fm.fileExists(atPath: previous.path), !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: previous, to: backup) }
        try result.journal.save(root.appendingPathComponent(Self.journalFilename))
        try result.save(to: root)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let priorAssets = (try? decoder.decode(Self.self, from: Data(contentsOf: backup)))?.library.assets ?? []
        for original in library.assets + priorAssets {
            if let updated = assets[original.id], AssetPaths.relativePath(original) != AssetPaths.relativePath(updated),
               let metadata = try? AssetPaths.metadata(original, in: root) {
                guard let saved = try? Self.original(updated, in: root),
                      let bytes = try? Data(contentsOf: saved), AssetVault.hash(bytes) == updated.digest else { continue }
                try? fm.removeItem(at: metadata)
                if let old = try? Self.original(original, in: root) {
                    if let bytes = try? Data(contentsOf: old), AssetVault.hash(bytes) == original.digest { try? fm.removeItem(at: old) }
                    try? fm.removeItem(at: old.deletingPathExtension().appendingPathExtension("json"))
                }
            }
        }
        for old in oldFiles { try? fm.removeItem(at: old); try? fm.removeItem(at: old.deletingPathExtension().appendingPathExtension("json")) }
        for asset in result.library.assets {
            for path in ["Thumbnails/\(asset.id).png", "Metadata/\(asset.id).json", "Receipts/\(asset.id).json"] { try? fm.removeItem(at: root.appendingPathComponent(path)) }
        }
        for project in result.library.projects {
            if let folder = project.storageFolder { try? fm.removeItem(at: root.appendingPathComponent("Projects/\(AssetPaths.component(folder))/project.json")) }
        }
        for path in ["ImageFlow.library.json", "Jobs.json", "보관함 안내.txt"] { try? fm.removeItem(at: root.appendingPathComponent(path)) }
        // Keep old database files as a hidden backup after the new cache is opened.
        for name in ["Library.store", "Library.store-wal", "Library.store-shm"] {
            let old = root.appendingPathComponent(name), target = hidden.appendingPathComponent("LegacyCache/" + name)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: target.path) {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: old, to: target)
            }
        }
        for folder in ["Originals", "Projects", "Thumbnails", "Metadata", "Receipts"] {
            let url = root.appendingPathComponent(folder)
            let directories = (fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey])?.allObjects as? [URL] ?? []).sorted { $0.path.count > $1.path.count }
            for directory in directories + [url] {
                if let contents = try? fm.contentsOfDirectory(atPath: directory.path), contents.isEmpty || contents == [".DS_Store"] {
                    if contents == [".DS_Store"] { try? fm.removeItem(at: directory.appendingPathComponent(".DS_Store")) }
                    try? fm.removeItem(at: directory)
                }
            }
        }
        return result
    }
}
