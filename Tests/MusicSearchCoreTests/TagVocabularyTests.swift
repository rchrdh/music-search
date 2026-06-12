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

    func testSpecificityFavorsRareTags() {
        // 40 albums: "pop" on all of them, "tuareg" on one.
        var lists = Array(repeating: ["pop"], count: 39)
        lists.append(["pop", "tuareg"])
        let weights = TagVocabulary.specificity(in: lists)
        XCTAssertEqual(weights["tuareg"], 1.0)
        XCTAssertEqual(weights["pop"], 0.0)
    }

    func testSpecificityDecaysSmoothlyWithFrequency() {
        // df 1 of 20 → full weight; the weight strictly decreases as the
        // tag gets more common — no knee where rare and common collapse.
        var lists = Array(repeating: ["common"], count: 19)
        lists.append(["common", "rare"])
        for i in 0 ..< 4 { lists[i].append("niche") }
        for i in 0 ..< 10 { lists[i].append("half") }
        let weights = TagVocabulary.specificity(in: lists)
        XCTAssertEqual(weights["rare"], 1.0)
        let niche = weights["niche"]!
        let half = weights["half"]!
        XCTAssertGreaterThan(niche, half)
        XCTAssertGreaterThan(half, 0.1)
        XCTAssertLessThan(half, 0.5)
    }

    func testSpecificityCountsAlbumsNotOccurrences() {
        // Duplicate tags within one album must not inflate its frequency.
        let weights = TagVocabulary.specificity(in: [["jazz", "jazz"], ["rock"]])
        XCTAssertEqual(weights["jazz"], weights["rock"])
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
