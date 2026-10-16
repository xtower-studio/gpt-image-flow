import XCTest
@testable import FlowCore

final class AssetNamingTests: XCTestCase {
    func testNumbersPersistAcrossBatchesCancellationAndQueueReorder() throws {
        var project = Project(name: "A"); project.prompt = "A teapot"; project.copies = 2
        var jobs = try JobRules.makeBatch(project: project)
        AssetNaming.number(&jobs)
        XCTAssertEqual(jobs.map(\.requestNumber), [1, 2])
        jobs[0].state = .cancelled
        jobs.reverse(); jobs += try JobRules.makeBatch(project: project)
        AssetNaming.number(&jobs)
        XCTAssertEqual(jobs.map(\.requestNumber), [2, 1, 3, 4])
        var restored = try JSONDecoder().decode([Job].self, from: JSONEncoder().encode(jobs))
        AssetNaming.number(&restored)
        XCTAssertEqual(restored, jobs)
        XCTAssertEqual(jobs[2].imageTitle(0), "3-1")
        XCTAssertEqual(jobs[2].imageTitle(1), "3-2")
    }
    func testMigrationRenamesDefaultsButPreservesUserTitles() throws {
        var project = Project(name: "A"); project.prompt = "test"
        var jobs = try JobRules.makeBatch(project: project)
        let first = Asset(projectID: project.id, filename: "a.png", title: "요청 1 · 1", width: 1, height: 1, digest: "", isReference: false, jobID: jobs[0].id)
        let second = Asset(projectID: project.id, filename: "b.png", title: "사용자 지정", width: 1, height: 1, digest: "", isReference: false, jobID: jobs[0].id)
        jobs[0].results = [first, second]
        var library = Library(); library.assets = [first, second]
        AssetNaming.migrate(library: &library, jobs: &jobs)
        XCTAssertEqual(library.assets.map(\.title), ["1-1", "사용자 지정"])
        XCTAssertEqual(library.assets.map(\.sequenceName), ["1-1", "1-2"])
        library.assets[0].title = "새 이름"
        AssetNaming.migrate(library: &library, jobs: &jobs)
        XCTAssertEqual(library.assets[0].title, "새 이름")
    }
    func testRenamingChangesFilenameWithoutOverwritingOrDeletingBeforeCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = AssetVault(root: root)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let id = UUID(), folder = "Project"
        let first = try await vault.store(png, projectID: id, title: "1-1", isReference: false, projectFolder: folder)
        let other = try await vault.store(png, projectID: id, title: "Final", isReference: false, projectFolder: folder)
        let renamed = try await vault.copyRenamed(first, title: "Final", folder: folder)
        XCTAssertEqual(renamed.filename, "Final (2).png")
        XCTAssertEqual(try Data(contentsOf: vault.original(first)), png)
        XCTAssertEqual(try Data(contentsOf: vault.original(other)), png)
        try await vault.removeSupersededFile(first, replacement: renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.original(first).path))
        XCTAssertEqual(try Data(contentsOf: vault.original(renamed)), png)
    }
}
