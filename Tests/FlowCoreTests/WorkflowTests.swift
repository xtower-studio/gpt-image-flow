import XCTest
@testable import FlowCore

final class WorkflowTests: XCTestCase {
    func testLegacyLibraryAndJournalStillDecode() throws {
        var project = Project(name: "Existing"); project.prompt = "keep"
        var library = Library(); library.projects = [project]
        let data = try JSONEncoder().encode(library)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "recipes"); json.removeValue(forKey: "hiddenAssetIDs")
        var projects = json["projects"] as! [[String: Any]]
        for key in ["layout", "viewport", "reasoning"] { projects[0].removeValue(forKey: key) }
        json["projects"] = projects
        let restored = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.projects[0].prompt, "keep")
        XCTAssertNil(restored.projects[0].reasoning)
        XCTAssertNil(restored.projects[0].layout)
        var journal = QueueJournal(); journal.jobs = try JobRules.makeBatch(project: project)
        let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as! [String: Any]
        let recovered = try JSONDecoder().decode(QueueJournal.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(recovered.jobs.count, 1)
        XCTAssertNil(recovered.workerAvailableAt)
    }
    func testThreeWorkersAdmitTogetherAndCoolDownIndependently() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(QueueAdmission.slots(limit: 3, occupied: [], availableAt: [:], now: now), [0,1,2])
        XCTAssertEqual(QueueAdmission.slots(limit: 3, occupied: [1], availableAt: ["0": now.addingTimeInterval(60)], now: now), [2])
        XCTAssertEqual(QueueAdmission.slots(limit: 1, occupied: [], availableAt: [:], now: now), [0])
        XCTAssertEqual(QueueAdmission.slots(limit: 1, occupied: [1,2], availableAt: [:], now: now), [])
        XCTAssertEqual(QueueAdmission.slots(limit: 3, occupied: [0,1,2], availableAt: [:], now: now), [])
    }
    func testSameConversationCannotRaceButUnrelatedWorkCanProceed() {
        var a = Job(batchID: UUID(), projectID: UUID(), prompt: "first", label: "first", referenceIDs: [])
        a.conversationID = UUID().uuidString; a.state = .generating
        var next = a; next.id = UUID(); next.state = .queued; next.continuationOf = a.id
        XCTAssertFalse(QueueAdmission.canStart(next, alongside: [a]))
        next.conversationID = UUID().uuidString
        XCTAssertTrue(QueueAdmission.canStart(next, alongside: [a]))
    }
    func testBatchFreezesReasoningAndCanvasCoordinatesRoundTrip() throws {
        var project = Project(name: "Canvas"); project.prompt = "vase"; project.generationMode = .sunburstExperimental
        project.layout = ["node": CanvasPoint(x: -300, y: 250)]
        project.viewport = CanvasViewport(x: 70, y: -90, scale: 0.5)
        let jobs = try JobRules.makeBatch(project: project); project.generationMode = .instant
        XCTAssertEqual(jobs.first?.generationMode, .sunburstExperimental)
        XCTAssertEqual(jobs.first?.reasoning?.rawValue, 1)
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(restored.layout, project.layout)
        XCTAssertEqual(restored.viewport?.world(x: 120, y: -40), CanvasPoint(x: 100, y: 100))
    }
    func testTextResponseAndFollowupSurviveRestartWithoutRequeue() throws {
        var job = Job(batchID: UUID(), projectID: UUID(), prompt: "question", label: "question", referenceIDs: [])
        job.state = .responded; job.responseText = "어떤 색상을 원하시나요?"; job.conversationID = UUID().uuidString
        let restored = try JSONDecoder().decode(Job.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(JobRules.recovered(restored).state, .responded)
        XCTAssertEqual(restored.responseText, job.responseText)
        var followup = job; followup.id = UUID(); followup.continuationOf = job.id; followup.state = .submitting
        followup.excludedFileIDs = ["file_old"]; followup.baselineAssistantCount = 1
        XCTAssertEqual(JobRules.recovered(followup).state, .needsReview)
        XCTAssertEqual(JobRules.recovered(followup).excludedFileIDs, ["file_old"])
    }
}
