import XCTest
import Foundation
import SwiftData
@testable import PreflightCore

final class PreflightTests: XCTestCase {
    func policy() throws -> GenerationPolicy {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try GenerationPolicy.load(root.appendingPathComponent("config/generation-policy.json"))
    }
    func testThreeSlotsWithAccountWideSpacing() async throws {
        let gate = SubmissionGate(policy: try policy())
        let a = UUID(), b = UUID(), c = UUID()
        let t1 = await gate.claim(job: a, now: 0, delay: 30)
        XCTAssertNotNil(t1)
        let early = await gate.claim(job: b, now: 29, delay: 30)
        XCTAssertNil(early)
        let t2 = await gate.claim(job: b, now: 30, delay: 30)
        let t3 = await gate.claim(job: c, now: 60, delay: 30)
        XCTAssertNotNil(t2); XCTAssertNotNil(t3)
        let fourth = await gate.claim(job: UUID(), now: 90, delay: 30)
        XCTAssertNil(fourth)
        await gate.finish(job: a, token: t1!)
        let next = await gate.claim(job: UUID(), now: 90, delay: 30)
        XCTAssertNotNil(next)
    }
    func testConcurrentClaimsCannotOverbook() async throws {
        let gate = SubmissionGate(policy: try policy())
        let claims = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<100 { group.addTask { await gate.claim(job: UUID(), now: 0, delay: 30) != nil } }
            var successes = 0
            for await success in group { if success { successes += 1 } }
            return successes
        }
        XCTAssertEqual(claims, 1) // Spacing applies across every project/window.
    }
    func testEcoAndModeReductionDoNotCancelRunningJobs() async throws {
        let gate = SubmissionGate(policy: try policy())
        let a = UUID(), b = UUID()
        let ta = await gate.claim(job: a, now: 0, delay: 30)
        let tb = await gate.claim(job: b, now: 30, delay: 30)
        await gate.setEco(true)
        let count = await gate.activeCount()
        XCTAssertEqual(count, 2)
        await gate.finish(job: a, token: ta!)
        let blocked = await gate.claim(job: UUID(), now: 60, delay: 30)
        XCTAssertNil(blocked)
        await gate.finish(job: b, token: tb!)
        let resumed = await gate.claim(job: UUID(), now: 60, delay: 30)
        XCTAssertNotNil(resumed)
    }
    func testPauseRetainsActiveSlotsAndRequiresExplicitResume() async throws {
        let gate = SubmissionGate(policy: try policy())
        _ = await gate.claim(job: UUID(), now: 0, delay: 30)
        await gate.pauseForUncertainRemoteState()
        let blocked = await gate.claim(job: UUID(), now: 9999, delay: 30)
        let count = await gate.activeCount()
        XCTAssertNil(blocked); XCTAssertEqual(count, 1)
        await gate.resumeExplicitly()
        let resumed = await gate.claim(job: UUID(), now: 10000, delay: 30)
        XCTAssertNotNil(resumed)
    }
    func testDuplicateJobAndStaleCompletionCannotSubmitOrRelease() async throws {
        let gate = SubmissionGate(policy: try policy())
        let id = UUID()
        let token = await gate.claim(job: id, now: 0, delay: 30)
        await gate.finish(job: id, token: UUID())
        let count = await gate.activeCount()
        XCTAssertEqual(count, 1)
        await gate.finish(job: id, token: token!)
        let duplicate = await gate.claim(job: id, now: 120, delay: 30)
        XCTAssertNil(duplicate)
    }
    func testSpacingClampsBothEnds() async throws {
        let gate = SubmissionGate(policy: try policy())
        let id = UUID()
        let token = await gate.claim(job: id, now: 0, delay: -1)
        await gate.finish(job: id, token: token!)
        let early = await gate.claim(job: UUID(), now: 29, delay: 999)
        XCTAssertNil(early)
        let nextID = UUID()
        let next = await gate.claim(job: nextID, now: 30, delay: 999)
        await gate.finish(job: nextID, token: next!)
        let earlyAgain = await gate.claim(job: UUID(), now: 149, delay: 30)
        let allowed = await gate.claim(job: UUID(), now: 150, delay: 30)
        XCTAssertNil(earlyAgain); XCTAssertNotNil(allowed)
    }
    func testBatchBounds() async throws {
        let gate = SubmissionGate(policy: try policy())
        try await gate.validateBatch(50)
        for count in [0, 51] {
            do { try await gate.validateBatch(count); XCTFail("accepted \(count)") }
            catch PolicyError.invalidBatch {} catch { XCTFail("wrong error") }
        }
    }
    func testSavedGateRestoresPacingAndRequiresReconciliation() async throws {
        let gate = SubmissionGate(policy: try policy())
        let id = UUID()
        let token = await gate.claim(job: id, now: 100, delay: 120)
        let data = try JSONEncoder().encode(await gate.snapshot())
        let restored = SubmissionGate(policy: try policy(), restoring: try JSONDecoder().decode(GateSnapshot.self, from: data))
        let blocked = await restored.claim(job: UUID(), now: 1000, delay: 30)
        XCTAssertNil(blocked)
        await restored.finish(job: id, token: token!)
        await restored.resumeExplicitly()
        let tooSoon = await restored.claim(job: UUID(), now: 219, delay: 30)
        XCTAssertNil(tooSoon)
        let next = await restored.claim(job: UUID(), now: 220, delay: 30)
        XCTAssertNotNil(next)
        let duplicate = await restored.claim(job: id, now: 250, delay: 30)
        XCTAssertNil(duplicate)
    }
    func testAtomicResultRecoveryAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try JobJournal(directory: directory)
        var entry = JournalEntry(id: UUID(), state: .collecting, conversationID: "fixture")
        try journal.stageResult(Data("original".utf8), entry: &entry)
        XCTAssertEqual(try journal.recover(entry.id), .useSaved)
        try Data("corrupted".utf8).write(to: journal.assetURL(entry.id))
        XCTAssertEqual(try journal.recover(entry.id), .collectExisting)
    }
    func testUncertainSubmissionNeverRequeues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try JobJournal(directory: directory)
        let entry = JournalEntry(id: UUID(), state: .submitting)
        try journal.write(entry)
        XCTAssertEqual(try journal.recover(entry.id), .needsReview)
    }
    @MainActor func testSwiftDataExplicitSaveAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = ModelConfiguration(url: directory.appendingPathComponent("metadata.store"))
        let id = UUID()
        do {
            let container = try ModelContainer(for: ProbeMetadata.self, configurations: config)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(ProbeMetadata(id: id, prompt: "참조 이미지 · fixture"))
            try context.save()
        }
        let reopened = try ModelContainer(for: ProbeMetadata.self, configurations: config)
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<ProbeMetadata>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, id)
        XCTAssertEqual(rows.first?.prompt, "참조 이미지 · fixture")
    }
}

@Model final class ProbeMetadata {
    @Attribute(.unique) var id: UUID
    var prompt: String
    init(id: UUID, prompt: String) { self.id = id; self.prompt = prompt }
}
