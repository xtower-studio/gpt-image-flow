import XCTest
@testable import FlowCore

final class ImageSizeSelectionTests: XCTestCase {
    func testEveryOfferedCombinationProducesValidAPIParameters() throws {
        for model in ImageAPIModel.all where !model.hasRetired {
            var options = ImageAPIOptions(); options.selectModel(model.id)
            for aspect in ImageSizeSelection.aspects(for: options) {
                options.size = ImageSizeSelection.selectingAspect(aspect, in: options)
                for resolution in ImageSizeSelection.resolutions(for: options) {
                    options.size = ImageSizeSelection.selectingResolution(resolution, in: options)
                    XCTAssertEqual(ImageSizeSelection.aspect(options.size), aspect)
                    XCTAssertEqual(ImageSizeSelection.resolution(options.size), resolution)
                    try options.validate(prompt: "test", referenceCount: 0)
                    XCTAssertEqual(options.parameters(prompt: "test", editing: false)["size"] as? String, options.size)
                }
            }
        }
    }
    func testChangingAspectPreservesResolutionWhenSupported() {
        var options = ImageAPIOptions(); options.size = "2048x2048"
        options.size = ImageSizeSelection.selectingAspect("16:9", in: options)
        XCTAssertEqual(options.size, "2048x1152")
        options.size = ImageSizeSelection.selectingAspect("3:2", in: options)
        XCTAssertEqual(options.size, "2016x1344")
        options.size = ImageSizeSelection.selectingAspect("9:16", in: options)
        XCTAssertEqual(options.size, "1152x2048")
        options.size = ImageSizeSelection.selectingResolution("4K", in: options)
        XCTAssertEqual(options.size, "2160x3840")
        options.size = ImageSizeSelection.selectingAspect("1:1", in: options)
        XCTAssertFalse(ImageSizeSelection.resolutions(for: options).contains("4K"))
        XCTAssertEqual(ImageSizeSelection.selectingAspect("자동", in: options), "auto")
    }
    func testAutomaticAndCustomSizesSurviveReadingAndPersistence() throws {
        var options = ImageAPIOptions()
        XCTAssertEqual(ImageSizeSelection.aspect(options.size), "자동")
        XCTAssertEqual(ImageSizeSelection.resolution(options.size), "자동")
        options.size = ImageSizeSelection.selectingResolution("4K", in: options)
        XCTAssertEqual(options.size, "3840x2160")
        options.size = "1600x1280"
        XCTAssertEqual(ImageSizeSelection.aspect(options.size), "5:4")
        _ = ImageSizeSelection.resolutions(for: options)
        let restored = try JSONDecoder().decode(ImageAPIOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(restored.size, "1600x1280")
    }
}
