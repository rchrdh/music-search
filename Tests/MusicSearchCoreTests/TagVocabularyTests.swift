import XCTest
@testable import MusicSearchCore

final class TagVocabularyTests: XCTestCase {

    func testGroundPassesThroughExactVocabularyMembers() {
        let grounded = TagVocabulary.ground(["ambient"], in: ["ambient", "jazz"])
        XCTAssertEqual(grounded, ["ambient"])
    }

    func testGroundExpandsToOverlappingVocabularyTags() {
        let grounded = TagVocabulary.ground(
            ["french"],
            in: ["french", "french pop", "jazz"]
        )
        XCTAssertEqual(grounded, ["french", "french pop"])
    }

    func testGroundRejoinsSplitBigrams() {
        // The heuristic parser splits "new age" into "new" + "age"; both ground
        // to the single vocabulary tag "new age", deduplicated.
        let grounded = TagVocabulary.ground(["new", "age"], in: ["new age", "metal"])
        XCTAssertEqual(grounded, ["new age"])
    }

    func testGroundDropsWordsAbsentFromLibrary() {
        let grounded = TagVocabulary.ground(["zydeco"], in: ["ambient", "jazz"])
        XCTAssertTrue(grounded.isEmpty)
    }

    func testTopTagsOrdersByFrequencyThenName() {
        let tags = TagVocabulary.topTags(in: [
            ["ambient", "electronic"],
            ["ambient", "jazz"],
            ["ambient", "electronic"],
        ])
        XCTAssertEqual(tags, ["ambient", "electronic", "jazz"])
    }

    func testTopTagsHonorsLimit() {
        let tags = TagVocabulary.topTags(in: [["a", "b", "c"]], limit: 2)
        XCTAssertEqual(tags.count, 2)
    }
}
