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
        XCTAssertEqual(migrated.version, 2)
        XCTAssertTrue(migrated.library.assets[0].relativePath!.contains("/References/"))
        XCTAssertTrue(migrated.library.assets[1].relativePath!.contains("/Generated/"))
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
        XCTAssertThrowsError(try PortableLibrary(library: library, journal: QueueJournal()).organized(in: root))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: destination), conflict)
    }
    func testUnsafePathsAreRejectedAndProjectNamesDoNotCollide() throws {
        let root = FileManager.default.temporaryDirectory
        var asset = Asset(projectID: UUID(), filename: "safe.png", title: "Result", width: 1, height: 1, digest: "", isReference: false)
        for path in ["Projects/../outside.png", "/tmp/out.png", "Projects//out.png", "Other/out.png"] {
            asset.relativePath = path
            XCTAssertThrowsError(try AssetPaths.original(asset, in: root))
        }
        XCTAssertNotEqual(AssetPaths.projectFolder(name: String(repeating: "a", count: 100), id: UUID()), AssetPaths.projectFolder(name: String(repeating: "a", count: 100), id: UUID()))
    }
}
