import XCTest
@testable import FlowCore

final class ImageOptionsTests: XCTestCase {
    func testAutomaticOptionsLeaveUserPromptUnchangedAndDefaultToSunburst() throws {
        var project = Project(name: "Test"); project.prompt = "A ceramic teapot"
        for background in [nil, BackgroundOption.automatic] {
            project.background = background
            let job = try JobRules.makeBatch(project: project)[0]
            XCTAssertEqual(job.prompt, project.prompt)
            XCTAssertEqual(job.requestedModel, .sunburst)
            XCTAssertEqual(job.reasoning?.rawValue, 2)
        }
    }
    func testEnglishOptionsAreIndependentAndModelSnapshotIsFrozen() throws {
        var project = Project(name: "Test"); project.prompt = "주전자"
        project.aspect = "1:1"; project.background = .transparent; project.imageModel = .flare
        let job = try JobRules.makeBatch(project: project)[0]
        XCTAssertEqual(job.prompt, "주전자\nsize:1:1\ntransparent_background: true")
        XCTAssertEqual(job.reasoning?.rawValue, 0)
        project.imageModel = .sunburst; project.aspect = "자유"; project.background = .opaque
        XCTAssertEqual(try JobRules.makeBatch(project: project)[0].prompt, "주전자\ntransparent_background: false")
        XCTAssertEqual(job.requestedModel, .flare)
        project.aspect = "16:9"; project.background = .automatic
        XCTAssertEqual(try JobRules.makeBatch(project: project)[0].prompt, "주전자\nsize:16:9")
    }
    func testPreferencesAndRecipeOptionsSurviveRestart() throws {
        var library = Library(); library.preferredModel = .flare
        var project = Project(name: "Options"); project.background = .transparent; project.imageModel = .flare
        library.projects = [project]; library.recipes = [Recipe(name: "Recipe", settings: project)]
        let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.preferredModel, .flare)
        XCTAssertEqual(restored.projects.first?.background, .transparent)
        XCTAssertEqual(restored.recipes?.first?.settings.imageModel, .flare)
        XCTAssertNil(try JSONDecoder().decode(Library.self, from: Data(#"{"schemaVersion":1,"projects":[],"assets":[]}"#.utf8)).preferredModel)
    }
    func testDismissedAttentionPreservesErrorAndReappearsForNewState() throws {
        var job = Job(batchID: UUID(), projectID: UUID(), prompt: "test", label: "test", referenceIDs: [])
        job.state = .failed; job.error = "Attachment missing"
        XCTAssertTrue(job.showsAttention)
        job.dismissedAttentionState = job.state
        var restored = try JSONDecoder().decode(Job.self, from: JSONEncoder().encode(job))
        XCTAssertFalse(restored.showsAttention)
        XCTAssertEqual(restored.state, .failed); XCTAssertEqual(restored.error, job.error)
        restored.state = .responded; restored.responseText = "Follow up"
        XCTAssertTrue(restored.showsAttention)
    }
}
