import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import FlowCore

final class PortableLibraryTests: XCTestCase {
    private func png() -> Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")! }
    func testCopyAndJSONOnlyRestoreIncludeReferencesRecipesAndJobInformation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source"), destination = base.appendingPathComponent("restored")
        let vault = AssetVault(root: source)
        var project = Project(name: "Restorable project"); project.prompt = "A teapot"; project.generationMode = .instant
        let ref = try await vault.store(png(), projectID: project.id, title: "Reference", isReference: true)
        project.referenceIDs = [ref.id]
        var job = try JobRules.makeBatch(project: project)[0]
        let result = try await vault.store(png(), projectID: project.id, title: "Result", isReference: false, jobID: job.id)
        job.results = [result]; job.state = .saved; job.apiUsageJSON = "{\"total_tokens\":123}"
        var library = Library(); library.projects = [project]; library.assets = [ref,result]; library.recipes = [Recipe(name: "Template", settings: project)]
        var journal = QueueJournal(); journal.jobs = [job]
        let archive = PortableLibrary(library: library, journal: journal)
        try archive.copy(from: source, to: destination)
        try FileManager.default.removeItem(at: destination.appendingPathComponent("Thumbnails"))
        let restored = try PortableLibrary.load(from: destination)
        let restoredVault = AssetVault(root: destination)
        try await restoredVault.rebuildMissingThumbnails(restored.library.assets)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredVault.thumbnail(ref).path))
        try restored.verifyFiles(in: destination)
        XCTAssertEqual(restored.library.assets.count, 2)
        XCTAssertEqual(restored.library.projects[0].referenceIDs, [ref.id])
        XCTAssertEqual(restored.library.recipes?.first?.name, "Template")
        XCTAssertEqual(restored.journal.jobs[0].apiUsageJSON, job.apiUsageJSON)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.original(result).path))
        let sidecar = try String(contentsOf: destination.appendingPathComponent("Metadata/\(result.id).json"), encoding: .utf8)
        XCTAssertTrue(sidecar.contains("A teapot")); XCTAssertTrue(sidecar.contains(ref.id.uuidString))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Metadata/\(ref.id).json").path))
        let receipts = try await vault.receipts()
        XCTAssertEqual(receipts.count, 2, "Imported references need crash-recovery receipts too")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Library.store").path), "Restore must not depend on SwiftData")
    }
    func testRejectsOccupiedDestinationAndMissingOriginalWithoutTouchingSource() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source"), target = base.appendingPathComponent("target")
        let vault = AssetVault(root: source)
        let asset = try await vault.store(png(), projectID: UUID(), title: "original", isReference: true)
        var library = Library(); library.assets = [asset]
        let archive = PortableLibrary(library: library, journal: QueueJournal())
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: marker)
        XCTAssertThrowsError(try archive.copy(from: source, to: target))
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "keep")
        XCTAssertThrowsError(try archive.copy(from: source, to: source.appendingPathComponent("nested")))
        try FileManager.default.removeItem(at: vault.original(asset))
        XCTAssertThrowsError(try archive.copy(from: source, to: base.appendingPathComponent("empty")))
    }
    func testRejectsTraversalInRecoveryMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let asset = Asset(projectID: UUID(), filename: "../outside.png", title: "bad", width: 1, height: 1, digest: "", isReference: true)
        XCTAssertThrowsError(try PortableLibrary.original(asset, in: root))
    }
}
