import XCTest
@testable import FlowCore

final class LibraryOrganizationTests: XCTestCase {
    func testLegacyMigrationPreservesBytesReferencesAndRecoveryAcrossRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default, vault = AssetVault(root: root)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        var project = Project(name: "제품 / 세라믹"); project.storageFolder = nil; project.prompt = "teapot"
        var assets: [Asset] = []
        for reference in [true, false] {
            var asset = try await vault.store(png, projectID: project.id, title: reference ? "참조" : "결과", isReference: reference)
            let grouped = vault.original(asset); asset.relativePath = nil
            let old = vault.original(asset)
            try fm.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: grouped, to: old)
            try fm.createDirectory(at: root.appendingPathComponent("Thumbnails"), withIntermediateDirectories: true)
            try png.write(to: root.appendingPathComponent("Thumbnails/\(asset.id).png"))
            assets.append(asset)
        }
        project.referenceIDs = [assets[0].id]
        var job = try JobRules.makeBatch(project: project)[0]; job.results = [assets[1]]; job.state = .saved
        var library = Library(); library.projects = [project]; library.assets = assets
        var journal = QueueJournal(); journal.jobs = [job]
        var legacy = PortableLibrary(library: library, journal: journal); legacy.version = 1
        try legacy.save(to: root)
        let migrated = try PortableLibrary.load(from: root).organized(in: root)
        try migrated.verifyFiles(in: root)
        XCTAssertEqual(migrated.version, 3)
        XCTAssertEqual(migrated.library.assets[0].relativePath!.split(separator: "/").count, 2)
        XCTAssertEqual(migrated.library.assets[1].relativePath!.split(separator: "/").count, 2)
        XCTAssertEqual(migrated.journal.jobs[0].results[0].relativePath, migrated.library.assets[1].relativePath)
        XCTAssertEqual(migrated.library.projects[0].referenceIDs, [assets[0].id])
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Originals").path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Thumbnails").path))
        let retried = try PortableLibrary.load(from: root).organized(in: root)
        try retried.verifyFiles(in: root)
        let receipts = try await vault.receipts()
        XCTAssertEqual(Set(receipts.compactMap(\.relativePath)), Set(migrated.library.assets.compactMap(\.relativePath)))
    }
    func testConflictingDestinationNeverDeletesOrOverwritesOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let project = Project(name: "Collision")
        let bytes = Data("original source".utf8)
        var asset = Asset(projectID: project.id, filename: "legacy.png", title: "Result", width: 1, height: 1, digest: AssetVault.hash(bytes), isReference: false)
        let source = try AssetPaths.original(asset, in: root)
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: source)
        asset.relativePath = AssetPaths.relativePath(asset, folder: project.storageFolder!)
        let destination = try AssetPaths.original(asset, in: root)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let conflict = Data("do not overwrite".utf8); try conflict.write(to: destination)
        asset.relativePath = nil
        var library = Library(); library.projects = [project]; library.assets = [asset]
        let result = try PortableLibrary(library: library, journal: QueueJournal()).organized(in: root)
        XCTAssertEqual(try Data(contentsOf: AssetPaths.original(result.library.assets[0], in: root)), bytes)
        XCTAssertEqual(try Data(contentsOf: destination), conflict)
    }
    func testMovedV2OriginalIsRecoveredAndOnlyImagesRemainVisible() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default, bytes = Data("verified original".utf8)
        let project = Project(name: "제품")
        var asset = Asset(projectID: project.id, filename: "old.png", title: "result", width: 1, height: 1, digest: AssetVault.hash(bytes), isReference: false)
        let name = "result — \(asset.id).png"
        asset.relativePath = "Projects/\(project.storageFolder!)/Generated/2026-10-01/\(name)"
        let moved = root.appendingPathComponent("Projects/\(project.storageFolder!)/직접 정리/\(name)")
        try fm.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: moved)
        var library = Library(); library.projects = [project]; library.assets = [asset]
        var archive = PortableLibrary(library: library, journal: QueueJournal()); archive.version = 2
        try archive.save(to: root)
        let result = try archive.organized(in: root)
        try result.verifyFiles(in: root)
        let visibleRoot = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        XCTAssertEqual(visibleRoot.map(\.lastPathComponent), [project.storageFolder!])
        let visibleProject = try fm.contentsOfDirectory(at: visibleRoot[0], includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        XCTAssertEqual(visibleProject.map(\.lastPathComponent), ["result.png"])
        XCTAssertTrue(fm.fileExists(atPath: try AssetPaths.metadata(result.library.assets[0], in: root).path))
        XCTAssertFalse(fm.fileExists(atPath: moved.path))
        _ = try PortableLibrary.load(from: root).organized(in: root)
    }
    func testUnsafePathsAreRejectedAndProjectNamesDoNotCollide() throws {
        let root = FileManager.default.temporaryDirectory
        var asset = Asset(projectID: UUID(), filename: "safe.png", title: "Result", width: 1, height: 1, digest: "", isReference: false)
        for path in ["Projects/../outside.png", "/tmp/out.png", "Projects//out.png", ".imageflow/out.png"] {
            asset.relativePath = path
            XCTAssertThrowsError(try AssetPaths.original(asset, in: root))
        }
        XCTAssertNotEqual(AssetPaths.projectFolder(name: String(repeating: "a", count: 100), id: UUID()), AssetPaths.projectFolder(name: String(repeating: "a", count: 100), id: UUID()))
    }
}
