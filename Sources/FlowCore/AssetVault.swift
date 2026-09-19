import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public actor AssetVault {
    public nonisolated let root: URL
    public init(root: URL) { self.root = root }
    public nonisolated func original(_ asset: Asset) -> URL { root.appendingPathComponent("Originals").appendingPathComponent(asset.filename) }
    public nonisolated func thumbnail(_ asset: Asset) -> URL { root.appendingPathComponent("Thumbnails/\(asset.id).png") }
    public func ingest(url: URL, projectID: UUID, title: String? = nil) throws -> Asset {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try store(Data(contentsOf: url), projectID: projectID, title: title ?? url.deletingPathExtension().lastPathComponent,
                         isReference: true)
    }
    public func store(_ bytes: Data, projectID: UUID, title: String, isReference: Bool,
                      jobID: UUID? = nil, parentID: UUID? = nil, generationMetadata: ImageGenerationMetadata? = nil) throws -> Asset {
        guard bytes.count <= 50 * 1024 * 1024 else { throw FlowError.message("앱에서 가져올 수 있는 파일은 50MB 이하입니다.") }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let type = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw FlowError.message("이미지 파일을 읽을 수 없습니다.") }
        let id = UUID()
        let ext = UTType(type as String)?.preferredFilenameExtension ?? "png"
        var asset = Asset(id: id, projectID: projectID, filename: "\(id).\(ext)", title: title,
                          width: width, height: height, digest: Self.hash(bytes), isReference: isReference,
                          jobID: jobID, parentID: parentID)
        asset.generationMetadata = generationMetadata
        for folder in ["Originals", "Thumbnails", "Receipts"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try bytes.write(to: original(asset), options: .atomic)
        let thumbnailData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(thumbnailData, UTType.png.identifier as CFString, 1, nil) else {
            throw FlowError.message("미리보기를 저장할 수 없습니다.")
        }
        CGImageDestinationAddImage(destination, small, nil)
        guard CGImageDestinationFinalize(destination) else { throw FlowError.message("미리보기를 저장할 수 없습니다.") }
        try (thumbnailData as Data).write(to: thumbnail(asset), options: .atomic)
        if jobID != nil {
            try JSONEncoder().encode(asset).write(to: root.appendingPathComponent("Receipts/\(id).json"), options: .atomic)
        }
        return asset
    }
    public func updateReceipt(_ asset: Asset) throws {
        guard asset.jobID != nil else { return }
        try JSONEncoder().encode(asset).write(to: root.appendingPathComponent("Receipts/\(asset.id).json"), options: .atomic)
    }
    public func receipts() throws -> [Asset] {
        let directory = root.appendingPathComponent("Receipts")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { url in
                let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
                guard let bytes = try? Data(contentsOf: original(asset)), Self.hash(bytes) == asset.digest else { return nil }
                return asset
            }
    }
    public static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    public func export(_ assets: [Asset], jobs: [Job], to directory: URL) throws -> URL {
        let name = "Image Flow — " + Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)) + " — " + UUID().uuidString.prefix(6)
        let folder = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        struct ExportedAsset: Codable { let asset: Asset; let file: String }
        var exported: [ExportedAsset] = []
        for (index, asset) in assets.enumerated() {
            let safe = asset.title.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: "-")
            let target = folder.appendingPathComponent(String(format: "%02d", index + 1) + "-" + String(safe.prefix(60)) + "." + URL(fileURLWithPath: asset.filename).pathExtension)
            try FileManager.default.copyItem(at: original(asset), to: target)
            exported.append(ExportedAsset(asset: asset, file: target.lastPathComponent))
        }
        struct Manifest: Codable { let assets: [ExportedAsset]; let jobs: [Job] }
        let ids = Set(assets.compactMap(\.jobID))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Manifest(assets: exported, jobs: jobs.filter { ids.contains($0.id) }))
            .write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        return folder
    }
}
