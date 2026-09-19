import XCTest
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FlowCore

final class FlowCoreTests: XCTestCase {
    func testRecoveryPreservesFavoritesAndRestoresMissingResultsOnce() {
        let receipt = Asset(projectID: UUID(), filename: "image.png", title: "original", width: 16, height: 16, digest: "hash", isReference: false)
        var edited = receipt; edited.isFavorite = true; edited.title = "chosen"
        let missing = Asset(projectID: receipt.projectID, filename: "missing.png", title: "recovered", width: 16, height: 16, digest: "other", isReference: false)
        var library = Library(); library.assets = [edited]
        library.restoreMissingAssets([receipt, missing, receipt, missing])
        library.restoreMissingAssets([receipt, missing])
        XCTAssertEqual(library.assets, [edited, missing])
    }
    func testBatchFreezesInputAndSharesGroup() throws {
        var project = Project(name: "Fixture")
        project.prompt = "제품 사진"; project.variations = "밝은 배경\n\n 어두운 배경 \n"; project.copies = 5
        let reference = UUID(); project.referenceIDs = [reference]
        let jobs = try JobRules.makeBatch(project: project)
        project.prompt = "바뀐 요청"; project.referenceIDs = []
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].batchID, jobs[1].batchID)
        XCTAssertNotEqual(jobs[0].id, jobs[1].id)
        XCTAssertTrue(jobs[0].prompt.contains("밝은 배경"))
        XCTAssertEqual(jobs[0].referenceIDs, [reference])
        XCTAssertFalse(jobs[0].prompt.contains("바뀐 요청"))
    }
    func testBatchBoundsAndEmptyRequest() throws {
        var project = Project(name: "Fixture")
        XCTAssertThrowsError(try JobRules.makeBatch(project: project))
        project.prompt = "test"; project.copies = 51
        XCTAssertThrowsError(try JobRules.makeBatch(project: project))
        project.copies = 50
        XCTAssertEqual(try JobRules.makeBatch(project: project).count, 50)
    }
    func testEveryInterruptedRemoteStateRequiresReview() {
        for state in [JobState.submitting, .generating, .collecting] {
            var job = Job(batchID: UUID(), projectID: UUID(), prompt: "test", label: "test", referenceIDs: [])
            job.state = state
            XCTAssertEqual(JobRules.recovered(job).state, .needsReview)
            job.conversationID = UUID().uuidString
            XCTAssertEqual(JobRules.recovered(job).state, .needsReview)
        }
    }
    func testPreSubmissionRecoveryAndFinishedJobsAreStable() {
        for state in JobState.allCases {
            var job = Job(batchID: UUID(), projectID: UUID(), prompt: "test", label: "test", referenceIDs: [])
            job.state = state
            if [.preparing, .uploading].contains(state) { XCTAssertEqual(JobRules.recovered(job).state, .queued) }
            else if !state.isRunning { XCTAssertEqual(JobRules.recovered(job).state, state) }
        }
    }
    func testJournalPreservesAccountPacingAndCorruptionFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("jobs.json")
        var journal = QueueJournal(); journal.paused = true; journal.nextSubmissionAt = Date(timeIntervalSince1970: 200)
        var project = Project(name: "Fixture"); project.prompt = "test"
        journal.jobs = try JobRules.makeBatch(project: project)
        try journal.save(url)
        let restored = try QueueJournal.load(url)
        XCTAssertEqual(restored.jobs, journal.jobs)
        XCTAssertEqual(restored.nextSubmissionAt, journal.nextSubmissionAt)
        XCTAssertTrue(restored.paused)
        try Data("invalid".utf8).write(to: url)
        XCTAssertThrowsError(try QueueJournal.load(url))
    }
    func testConversationURLRequiresUUID() {
        var job = Job(batchID: UUID(), projectID: UUID(), prompt: "test", label: "test", referenceIDs: [])
        job.conversationID = "../bad?query=1"
        XCTAssertNil(job.conversationURL)
        job.conversationID = UUID().uuidString
        XCTAssertEqual(job.conversationURL?.host, "chatgpt.com")
    }
    func png() throws -> Data {
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
                                bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
    func testOriginalAndReceiptSurviveSeparateVaultInstance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = AssetVault(root: root), bytes = try png(), job = UUID()
        let asset = try await vault.store(bytes, projectID: UUID(), title: "test", isReference: false, jobID: job)
        XCTAssertEqual(try Data(contentsOf: vault.original(asset)), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.thumbnail(asset).path))
        let receipts = try await AssetVault(root: root).receipts()
        XCTAssertEqual(receipts.map(\.id), [asset.id])
        XCTAssertEqual(receipts.first?.jobID, job)
        try Data("broken".utf8).write(to: vault.original(asset))
        let corrupt = try await AssetVault(root: root).receipts()
        XCTAssertTrue(corrupt.isEmpty)
    }
    func testHTMLCannotBeSavedAsImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = AssetVault(root: root)
        do {
            _ = try await vault.store(Data("<html>login</html>".utf8), projectID: UUID(), title: "bad", isReference: false)
            XCTFail("Accepted HTML")
        } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: root.path)) }
    }
    func testImportedReferenceDoesNotDependOnOriginalLocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("참조 1.png"), bytes = try png()
        try bytes.write(to: original)
        let vault = AssetVault(root: root.appendingPathComponent("Vault"))
        let asset = try await vault.ingest(url: original, projectID: UUID())
        try FileManager.default.removeItem(at: original)
        XCTAssertEqual(try Data(contentsOf: vault.original(asset)), bytes)
        XCTAssertTrue(asset.isReference)
    }
    func testExportMapsUniqueNamesToOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = AssetVault(root: root.appendingPathComponent("Vault")), bytes = try png()
        let a = try await vault.store(bytes, projectID: UUID(), title: "같은 / 이름", isReference: false)
        let b = try await vault.store(bytes, projectID: a.projectID, title: "같은 / 이름", isReference: false)
        let folder = try await vault.export([a,b], jobs: [], to: root.appendingPathComponent("Export"))
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as! [String: Any]
        let entries = manifest["assets"] as! [[String: Any]]
        XCTAssertEqual(entries.count, 2)
        let names = entries.map { $0["file"] as! String }
        XCTAssertNotEqual(names[0], names[1])
        for name in names { XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(name)), bytes) }
    }
}
