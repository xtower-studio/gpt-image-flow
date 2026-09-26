import XCTest
@testable import FlowCore

final class StudioConvenienceTests: XCTestCase {
    func testInstantDoesNotAppendCountButAutomaticDoes() throws {
        var p = Project(name: "Instant"); p.prompt = "A blue teapot"; p.generationMode = .instant
        p.copies = 3
        let jobs = try JobRules.makeBatch(project: p)
        XCTAssertEqual(jobs.count, 3)
        XCTAssertTrue(jobs.allSatisfy { $0.prompt == p.prompt && $0.expectedImageCount == 1 })
        p.generationMode = .automatic
        XCTAssertTrue(try JobRules.makeBatch(project: p).allSatisfy { $0.prompt.hasSuffix("n=4") })
    }
    func testCostCalculatorMatchesOfficialExamplesAndQuantities() {
        var o = ImageAPIOptions(); o.quality = "low"; o.size = "1024x1024"; o.count = 1
        XCTAssertEqual(ImageCostEstimate.calculate(o)!.lowerUSD, 0.00588, accuracy: 0.000001)
        o.quality = "high"
        XCTAssertEqual(ImageCostEstimate.calculate(o)!.lowerUSD, 0.05268, accuracy: 0.000001)
        o.count = 2
        XCTAssertEqual(ImageCostEstimate.calculate(o, requests: 3)!.lowerUSD, 0.31608, accuracy: 0.000001)
        o.size = "auto"; o.quality = "auto"
        let auto = ImageCostEstimate.calculate(o)!
        XCTAssertTrue(auto.usesExampleSize); XCTAssertGreaterThan(auto.upperUSD, auto.lowerUSD)
        o.model = "gpt-image-1-mini"; o.size = "1536x1024"; o.quality = "high"; o.count = 1
        XCTAssertEqual(ImageCostEstimate.calculate(o)!.lowerUSD, 0.052, accuracy: 0.000001)
        o.model = "unknown"; XCTAssertNil(ImageCostEstimate.calculate(o))
    }
    func testRecipeFieldsAreUniqueAndValuesAreLiteral() {
        let text = "{{ 제품 }} beside {{배경}}, again {{제품}}."
        XCTAssertEqual(RecipeTemplates.fields(in: text), ["제품", "배경"])
        XCTAssertEqual(RecipeTemplates.render(text, values: ["제품":"찻잔 $1", "배경":"<blue>"]), "찻잔 $1 beside <blue>, again 찻잔 $1.")
        XCTAssertEqual(RecipeTemplates.render("{{제품}}", values: [:]), "{{제품}}")
    }
}
