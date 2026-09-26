import XCTest
@testable import FlowCore

final class ImageOptionsTests: XCTestCase {
    func testAutomaticOptionsOmitSizeAndBackgroundButRequestFourImages() throws {
        var project = Project(name: "Test"); project.prompt = "A ceramic teapot"
        for background in [nil, BackgroundOption.automatic] {
            project.background = background
            let job = try JobRules.makeBatch(project: project)[0]
            XCTAssertEqual(job.prompt, project.prompt + "\nn=4")
            XCTAssertEqual(job.generationMode, .automatic)
            XCTAssertEqual(job.expectedImageCount, 4)
            XCTAssertEqual(job.reasoning, .extended)
        }
    }
    func testEnglishOptionsAndRequestModeAreFrozen() throws {
        var project = Project(name: "Test"); project.prompt = "주전자"
        project.aspect = "1:1"; project.background = .transparent; project.generationMode = .instant
        let job = try JobRules.makeBatch(project: project)[0]
        XCTAssertEqual(job.prompt, "주전자\nsize:1:1\ntransparent_background: true")
        XCTAssertEqual(job.reasoning, .instant)
        project.generationMode = .sunburstExperimental; project.aspect = "자유"; project.background = .opaque
        XCTAssertEqual(try JobRules.makeBatch(project: project)[0].prompt, "주전자\ntransparent_background: false\nn=2")
        XCTAssertEqual(job.generationMode, .instant)
        XCTAssertEqual(job.inputPrompt, "주전자")
        project.aspect = "16:9"; project.background = .automatic
        XCTAssertEqual(try JobRules.makeBatch(project: project)[0].prompt, "주전자\nsize:16:9\nn=2")
    }
    func testRequestAndVariationCountsMultiplyByMode() throws {
        var project = Project(name: "Batch"); project.prompt = "teapot"; project.copies = 3
        for (mode, total) in [(GenerationMode.automatic,12),(.sunburstExperimental,6),(.instant,3)] {
            project.generationMode = mode
            let jobs = try JobRules.makeBatch(project: project)
            XCTAssertEqual(jobs.count, 3); XCTAssertEqual(jobs.reduce(0) { $0 + $1.expectedImageCount }, total)
        }
        project.generationMode = .automatic; project.variations = "blue\n\nred\n"
        let jobs = try JobRules.makeBatch(project: project)
        XCTAssertEqual(jobs.count, 2); XCTAssertEqual(jobs.reduce(0) { $0 + $1.expectedImageCount }, 8)
        XCTAssertEqual(jobs[1].inputPrompt, "teapot\nred")
    }
    func testPreferencesRecipesAndLegacyRequestsSurviveRestart() throws {
        var library = Library(); library.preferredGenerationMode = .instant
        var project = Project(name: "Options"); project.background = .transparent; project.generationMode = .sunburstExperimental
        library.projects = [project]; library.recipes = [Recipe(name: "Recipe", settings: project)]
        let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.preferredGenerationMode, .instant)
        XCTAssertEqual(restored.recipes?.first?.settings.generationMode, .sunburstExperimental)
        XCTAssertNil(try JSONDecoder().decode(Library.self, from: Data(#"{"schemaVersion":1,"projects":[],"assets":[]}"#.utf8)).preferredGenerationMode)
        var old = Job(batchID: UUID(), projectID: UUID(), prompt: "original", label: "old", referenceIDs: [])
        old.imageModel = .sunburst; old.reasoning = .standard
        let legacy = try JSONDecoder().decode(Job.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(legacy.expectedImageCount, 1); XCTAssertEqual(legacy.prompt, "original")
        XCTAssertEqual(legacy.executionReasoning, .standard)
        XCTAssertEqual(GenerationMode.migrated(from: .sunburst), .automatic)
        XCTAssertEqual(GenerationMode.migrated(from: .flare), .instant)
    }
    func testPartialBatchKeepsResultsAndRequiresReviewWithoutRequeue() throws {
        var project = Project(name: "Batch"); project.prompt = "teapot"; project.generationMode = .automatic
        var job = try JobRules.makeBatch(project: project)[0]
        let result = Asset(projectID: project.id, filename: "one.png", title: "one", width: 1254, height: 1254, digest: "hash", isReference: false)
        job.results = [result]
        let partial = JobRules.finishing(job)
        XCTAssertEqual(partial.state, .needsReview); XCTAssertEqual(partial.results, [result])
        XCTAssertTrue(partial.error?.contains("4장 중 1장") == true)
        XCTAssertEqual(JobRules.recovered(partial).state, .needsReview)
        job.results = (0..<4).map { _ in var copy = result; copy.id = UUID(); return copy }
        XCTAssertEqual(JobRules.finishing(job).state, .saved)
        XCTAssertNil(JobRules.finishing(job).error)
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
    func testWebMetadataNeverIdentifiesModel() throws {
        func evidence(_ size: String?, _ v2: String?) -> ImageGenerationMetadata {
            ImageGenerationMetadata(fileID: "file_test", messageID: "response", genSize: size, genSizeV2: v2)
        }
        for v2 in [nil, "24", "32", "48", "conflict", "future"] as [String?] {
            XCTAssertNil(evidence("smimage",v2).model)
            XCTAssertNil(evidence("image",v2).model)
            XCTAssertNil(evidence(nil,v2).model)
            XCTAssertNil(evidence("unknown",v2).model)
            XCTAssertNil(evidence("conflict",v2).model)
        }
        var asset = Asset(projectID: UUID(), filename: "image.png", title: "Sunburst", width: 1254, height: 1254, digest: "hash", isReference: false)
        XCTAssertNil(asset.actualModelLabel)
        asset.generationMetadata = evidence("smimage", "24")
        let restored = try JSONDecoder().decode(Asset.self, from: JSONEncoder().encode(asset))
        XCTAssertNil(restored.actualModelLabel)
    }
}
