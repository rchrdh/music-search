import XCTest
@testable import MusicSearchCore

final class SearchScorerTests: XCTestCase {

    func testTagMatchScores() {
        let score = SearchScorer.score(
            artist: "Enya",
            albumTags: ["new age", "celtic"],
            albumLanguage: nil,
            wantedTags: ["new age"],
            targetLanguages: [],
            similarArtists: []
        )
        XCTAssertNotNil(score)
        XCTAssertEqual(score?.value, 2)
    }

    func testConfirmedLanguageMatchesStrongly() {
        let score = SearchScorer.score(
            artist: "Françoise Hardy",
            albumTags: [],
            albumLanguage: "fra",
            wantedTags: ["french"],
            targetLanguages: ["fra"],
            similarArtists: []
        )
        XCTAssertEqual(score?.value, 4)
    }

    func testConfirmedWrongLanguageIsExcluded() {
        // English album in a French search must be dropped even if it has tags.
        let score = SearchScorer.score(
            artist: "Radiohead",
            albumTags: ["french"], // mistagged
            albumLanguage: "eng",
            wantedTags: ["french"],
            targetLanguages: ["fra"],
            similarArtists: []
        )
        XCTAssertNil(score)
    }

    func testUnknownLanguageFallsBackToTags() {
        let score = SearchScorer.score(
            artist: "Air",
            albumTags: ["french", "electronic"],
            albumLanguage: "", // looked up, unknown
            wantedTags: ["french"],
            targetLanguages: ["fra"],
            similarArtists: []
        )
        XCTAssertEqual(score?.value, 2)
    }

    func testSimilarArtistScores() {
        let score = SearchScorer.score(
            artist: "Harold Budd",
            albumTags: [],
            albumLanguage: nil,
            wantedTags: [],
            targetLanguages: [],
            similarArtists: ["harold budd", "cluster"]
        )
        XCTAssertEqual(score?.value, 3)
    }

    func testReferenceArtistOwnAlbumsAreExcluded() {
        // "Albums like Brian Eno" must not return Brian Eno's own albums,
        // even though the artist is (self-)present in the similar set.
        let score = SearchScorer.score(
            artist: "Brian Eno",
            albumTags: ["ambient"],
            albumLanguage: nil,
            wantedTags: [],
            targetLanguages: [],
            similarArtists: ["brian eno", "cluster"],
            referenceArtists: ["brian eno"]
        )
        XCTAssertNil(score)
    }

    func testReferenceArtistCollaborationCreditsAreExcluded() {
        // A collaboration album is still the referenced artist: "like Brian
        // Eno" must not recommend "Brian Eno & Harold Budd — The Pearl".
        let score = SearchScorer.score(
            artist: "Brian Eno & Harold Budd",
            albumTags: ["ambient"],
            albumLanguage: nil,
            wantedTags: [],
            targetLanguages: [],
            similarArtists: ["harold budd"],
            referenceArtists: ["brian eno"]
        )
        XCTAssertNil(score)
    }

    func testNoSignalReturnsNil() {
        let score = SearchScorer.score(
            artist: "Death",
            albumTags: ["death metal"],
            albumLanguage: nil,
            wantedTags: ["new age"],
            targetLanguages: [],
            similarArtists: []
        )
        XCTAssertNil(score)
    }

    func testNonLanguageSignalDetectsTagAndSimilar() {
        // Tag match counts as a candidate worth a language lookup.
        XCTAssertTrue(SearchScorer.hasNonLanguageSignal(
            artist: "Air", albumTags: ["french", "electronic"],
            wantedTags: ["french"], similarArtists: []
        ))
        // Similar-artist match counts too, even with no tag overlap.
        XCTAssertTrue(SearchScorer.hasNonLanguageSignal(
            artist: "Cluster", albumTags: ["krautrock"],
            wantedTags: ["french"], similarArtists: ["cluster"]
        ))
    }

    func testNonLanguageSignalRejectsBareAndReferenceArtist() {
        // No tag, not similar → not worth a lookup.
        XCTAssertFalse(SearchScorer.hasNonLanguageSignal(
            artist: "Metallica", albumTags: ["metal"],
            wantedTags: ["french"], similarArtists: []
        ))
        // The referenced artist itself is never a candidate (it's excluded).
        XCTAssertFalse(SearchScorer.hasNonLanguageSignal(
            artist: "Brian Eno", albumTags: ["ambient"],
            wantedTags: ["ambient"], similarArtists: ["brian eno"],
            referenceArtists: ["brian eno"]
        ))
    }

    func testExactMatchingRequiresEquality() {
        // Under .exact, "french" must NOT match "french pop" — grounding has
        // already expanded the query into the precise vocabulary tags it wants.
        let score = SearchScorer.score(
            artist: "Stromae",
            albumTags: ["french pop", "electronic"],
            albumLanguage: nil,
            wantedTags: ["french"],
            targetLanguages: [],
            similarArtists: [],
            tagMatching: .exact
        )
        XCTAssertNil(score)
    }

    func testExactMatchingScoresGroundedTags() {
        // The grounded query carries both vocabulary tags; each exact hit scores.
        let score = SearchScorer.score(
            artist: "Stromae",
            albumTags: ["french pop", "french", "electronic"],
            albumLanguage: nil,
            wantedTags: ["french", "french pop"],
            targetLanguages: [],
            similarArtists: [],
            tagMatching: .exact
        )
        XCTAssertEqual(score?.value, 4)
    }

    func testTargetLanguageCodesFromTags() {
        let codes = SearchScorer.targetLanguageCodes(from: ["french pop", "ambient"])
        XCTAssertEqual(codes, ["fra"])
    }
}
