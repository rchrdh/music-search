import XCTest
@testable import MusicSearchCore

final class HeuristicQueryParserTests: XCTestCase {

    func testPureTagQuery() {
        let parsed = HeuristicQueryParser().parse("psychedelic soul")
        XCTAssertEqual(parsed.descriptiveTags, ["psychedelic", "soul"])
        XCTAssertTrue(parsed.referenceArtists.isEmpty)
    }

    func testReferenceOnlyQuery() {
        let parsed = HeuristicQueryParser().parse("music like Funkadelic")
        XCTAssertEqual(parsed.referenceArtists, ["Funkadelic"])
        XCTAssertTrue(parsed.descriptiveTags.isEmpty, "stop-words only before the marker → no tags")
    }

    func testGenreCombinedWithReference() {
        // The fix: a genre word survives alongside a "like X" clause, and the
        // artist name is NOT swept up as a tag.
        let parsed = HeuristicQueryParser().parse("funk albums like Funkadelic")
        XCTAssertEqual(parsed.descriptiveTags, ["funk"])
        XCTAssertEqual(parsed.referenceArtists, ["Funkadelic"])
    }

    func testFunctionWordsAreNotTags() {
        // "are" must not survive as a descriptive tag: against a real
        // library's vocabulary it substring-grounds into "rare groove",
        // "cabaret", "tuareg" — and those tag matches outscore genuine
        // similar-artist results.
        let parsed = HeuristicQueryParser().parse("Albums that are like Brian Eno")
        XCTAssertTrue(parsed.descriptiveTags.isEmpty)
        XCTAssertEqual(parsed.referenceArtists, ["Brian Eno"])
    }

    func testContractionStemsAreNotTags() {
        // Splitting "don't" on non-letters leaves "don", which would ground
        // into "london". The negation itself is still unhandled (a known
        // suite gap) — but the junk tags must not be.
        let parsed = HeuristicQueryParser().parse("Albums that don't have vocals")
        XCTAssertEqual(parsed.descriptiveTags, ["vocals"])
    }

    func testLanguageAndGenreTogether() {
        let parsed = HeuristicQueryParser().parse("spanish rock like Santana")
        XCTAssertEqual(parsed.referenceArtists, ["Santana"])
        XCTAssertEqual(parsed.descriptiveTags, ["spanish", "rock"])
    }
}
