import XCTest
@testable import FlowCore

final class GalleryIdentityTests: XCTestCase {
    func testRecoveryMatchesRepeatedGalleryMessageIDsWithoutMergingDifferentImages() {
        let id = UUID().uuidString
        let evidence = ImageGenerationMetadata(fileID: "generated-\(id) \(id)-0", messageID: "\(id) \(id)", genSize: nil, genSizeV2: nil)
        XCTAssertTrue(evidence.matches(fileID: "generated-\(id)-0"))
        XCTAssertFalse(evidence.matches(fileID: "generated-\(id)-1"))
        XCTAssertFalse(evidence.matches(fileID: "generated-\(UUID().uuidString)-0"))
        let file = ImageGenerationMetadata(fileID: "file_original", messageID: id, genSize: nil, genSizeV2: nil)
        XCTAssertTrue(file.matches(fileID: "file_original"))
        XCTAssertFalse(file.matches(fileID: "generated-\(id)-0"))
    }
}
