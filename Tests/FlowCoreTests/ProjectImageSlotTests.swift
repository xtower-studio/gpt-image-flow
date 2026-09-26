import XCTest
@testable import FlowCore

final class ProjectImageSlotTests: XCTestCase {
    func testFourPlacesRemainStableAsResultsArrive() throws {
        var project = Project(name: "Board"); project.prompt = "teapot"; project.generationMode = .automatic
        var job = try JobRules.makeBatch(project: project)[0]
        let initial = ProjectImageSlot.make(assets: [], jobs: [job])
        XCTAssertEqual(initial.count, 4)
        let result = Asset(projectID: project.id, filename: "one.png", title: "One", width: 1, height: 1, digest: "", isReference: false, jobID: job.id)
        job.results = [result]; job.state = .collecting
        let partial = ProjectImageSlot.make(assets: [result], jobs: [job])
        XCTAssertEqual(initial.map(\.id), partial.map(\.id))
        XCTAssertEqual(partial.compactMap(\.asset).count, 1)
        XCTAssertEqual(partial.filter { $0.asset == nil }.count, 3)
        job.state = .failed
        XCTAssertEqual(ProjectImageSlot.make(assets: [result], jobs: [job]).count, 4)
        job.dismissedAttentionState = .failed
        XCTAssertEqual(ProjectImageSlot.make(assets: [result], jobs: [job]).count, 1)
    }
    func testReferencesShareBoardAndHiddenResultsDoNotBecomePlaceholders() throws {
        var project = Project(name: "Board"); project.prompt = "teapot"; project.generationMode = .instant
        var job = try JobRules.makeBatch(project: project)[0]
        let reference = Asset(projectID: project.id, filename: "ref.png", title: "Reference", width: 1, height: 1, digest: "", isReference: true)
        var slots = ProjectImageSlot.make(assets: [reference], jobs: [job])
        XCTAssertEqual(slots.count, 2); XCTAssertEqual(slots.first?.asset?.id, reference.id)
        let result = Asset(projectID: project.id, filename: "one.png", title: "One", width: 1, height: 1, digest: "", isReference: false, jobID: job.id)
        job.results = [result]; job.state = .saved
        slots = ProjectImageSlot.make(assets: [reference], jobs: [job])
        XCTAssertEqual(slots.count, 1)
    }
}
