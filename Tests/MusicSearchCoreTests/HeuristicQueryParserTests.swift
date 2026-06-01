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

    func testLanguageAndGenreTogether() {
        let parsed = HeuristicQueryParser().parse("spanish rock like Santana")
        XCTAssertEqual(parsed.referenceArtists, ["Santana"])
        XCTAssertEqual(parsed.descriptiveTags, ["spanish", "rock"])
    }
}
