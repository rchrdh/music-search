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

    func testGroundIgnoresJunkFragmentTags() {
        // Real libraries contain one-letter Last.fm tags; "t" must not ground
        // for "ambient" just because it's a substring of it.
        let grounded = TagVocabulary.ground(["ambient"], in: ["ambient", "t", "uk"])
        XCTAssertEqual(grounded, ["ambient"])
    }

    func testGroundStillMatchesShortTagsExactly() {
        let grounded = TagVocabulary.ground(["uk"], in: ["uk", "funk", "t"])
        XCTAssertEqual(grounded, ["uk"])
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
