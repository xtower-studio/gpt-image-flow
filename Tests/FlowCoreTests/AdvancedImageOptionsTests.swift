import XCTest
@testable import FlowCore

final class AdvancedImageOptionsTests: XCTestCase {
    func testFreshDefaultsAndExistingSettingsAreDistinct() throws {
        let defaults = ImageAPIOptions()
        XCTAssertEqual(defaults.model, "gpt-image-2.5-sunburst")
        XCTAssertEqual(defaults.quality, "high"); XCTAssertEqual(defaults.size, "auto"); XCTAssertEqual(defaults.count, 2)
        var old = defaults; old.quality = "low"; old.count = 1; old.size = "1024x1024"
        let restored = try JSONDecoder().decode(ImageAPIOptions.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(restored, old)
        var project = Project(name: "Advanced"); project.prompt = "teapot"; project.generationMode = .sunburstAPI; project.copies = 3
        let jobs = try JobRules.makeBatch(project: project)
        XCTAssertEqual(jobs.reduce(0) { $0 + $1.expectedImageCount }, 6)
        XCTAssertEqual(jobs[0].apiOptions, defaults); XCTAssertNil(jobs[0].reasoning)
    }
    func testCatalogModelsAndSnapshotsBuildTheSpecifiedModel() throws {
        XCTAssertEqual(ImageAPIModel.all.map(\.id), ["gpt-image-2.5-sunburst", "gpt-image-2.5-flare", "gpt-image-2", "gpt-image-1.5", "gpt-image-1", "gpt-image-1-mini", "chatgpt-image-latest"])
        XCTAssertNil(ImageAPIModel.resolve("dall-e-3"))
        for info in ImageAPIModel.all where !info.hasRetired {
            for id in info.versions {
                var options = ImageAPIOptions(); options.selectModel(id)
                try options.validate(prompt: "teapot", referenceCount: 1)
                XCTAssertEqual(options.parameters(prompt: "teapot", editing: true)["model"] as? String, id)
                for size in info.sizes { options.size = size; XCTAssertNoThrow(try options.validate(prompt: "teapot", referenceCount: 0), id + size) }
            }
        }
    }
    func testModelSwitchNormalizesUnsupportedOptionsWithoutChangingCount() throws {
        var options = ImageAPIOptions(); options.quality = "max"; options.size = "3840x2160"; options.inputFidelity = "low"; options.count = 4
        options.selectModel("gpt-image-2")
        XCTAssertEqual(options.quality, "high"); XCTAssertEqual(options.inputFidelity, "auto"); XCTAssertEqual(options.size, "3840x2160")
        XCTAssertNil(options.parameters(prompt: "edit", editing: true)["input_fidelity"])
        options.selectModel("gpt-image-1.5")
        XCTAssertEqual(options.size, "auto"); XCTAssertEqual(options.count, 4)
        options.quality = "max"; XCTAssertThrowsError(try options.validate(prompt: "image", referenceCount: 0))
        options.quality = "high"; options.size = "3840x2160"; XCTAssertThrowsError(try options.validate(prompt: "image", referenceCount: 0))
        options.selectModel("gpt-image-2.5-flare")
        XCTAssertNoThrow(try options.validate(prompt: "image", referenceCount: 0))
    }
    func testSizeLabelsUseAspectAndResolution() {
        for (size, label) in [("auto", "자동"), ("1024x1024", "1:1 · 1K"), ("1536x1024", "3:2 · 1.5K"), ("2048x1152", "16:9 · 2K"), ("3840x2160", "16:9 · 4K"), ("2160x3840", "9:16 · 4K")] {
            XCTAssertEqual(ImageAPISize.label(size), label)
        }
        XCTAssertEqual(ImageAPISize.label("9223372036854775807x1"), "사용자 지정")
    }
    func testUnknownModelsAreOmittedFromDetails() {
        var asset = Asset(projectID: UUID(), filename: "result.png", title: "Test", width: 1024, height: 1024, digest: "test", isReference: false)
        XCTAssertNil(asset.actualModelLabel); XCTAssertFalse(asset.displayDetails.contains(" · "))
        asset.apiModel = "gpt-image-2.5-flare-2026-09-08"
        XCTAssertEqual(asset.actualModelLabel, "Flare · API"); XCTAssertTrue(asset.displayDetails.hasSuffix(" · Flare · API"))
        XCTAssertEqual(GenerationMode.automatic.label, "자동"); XCTAssertEqual(GenerationMode.sunburstAPI.label, "고급"); XCTAssertEqual(GenerationMode.instant.label, "빠르게")
        XCTAssertFalse(GenerationMode.automatic.explanation.contains("추론"))
        XCTAssertEqual(GenerationMode.automatic.reasoning, .extended)
    }
}
