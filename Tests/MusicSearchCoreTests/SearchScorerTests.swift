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

    func testWeightScalesTagMatchesBySpecificity() {
        // Same flat value, different weights: the rare-tag match must carry
        // the heavier ranking key.
        let rare = SearchScorer.score(
            artist: "Mdou Moctar", albumTags: ["tuareg"], albumLanguage: nil,
            wantedTags: ["tuareg", "blues"], targetLanguages: [], similarArtists: [],
            tagMatching: .exact, tagWeights: ["tuareg": 1.0, "blues": 0.1]
        )
        let common = SearchScorer.score(
            artist: "Generic Blues Band", albumTags: ["blues"], albumLanguage: nil,
            wantedTags: ["tuareg", "blues"], targetLanguages: [], similarArtists: [],
            tagMatching: .exact, tagWeights: ["tuareg": 1.0, "blues": 0.1]
        )
        XCTAssertEqual(rare?.value, common?.value)
        XCTAssertEqual(rare?.weight ?? 0, 2.0, accuracy: 1e-9)
        XCTAssertEqual(common?.weight ?? 0, 0.2, accuracy: 1e-9)
    }

    func testGroupedWeightCountsEachConceptOnce() {
        // Six variants of "blues" are one matched concept: the album with
        // the rare "tuareg" match must outweigh the six-variant blues album.
        let groups = [["desert blues", "tuareg"], ["blues", "chicago blues", "jump blues", "piano blues"]]
        let wanted = groups.flatMap { $0 }
        let weights = ["desert blues": 0.9, "tuareg": 0.8, "blues": 0.4,
                       "chicago blues": 0.6, "jump blues": 0.6, "piano blues": 0.6]
        let bluesFlood = SearchScorer.score(
            artist: "Howlin' Wolf",
            albumTags: ["blues", "chicago blues", "jump blues", "piano blues"],
            albumLanguage: nil, wantedTags: wanted, targetLanguages: [], similarArtists: [],
            tagMatching: .exact, tagWeights: weights, wantedTagGroups: groups
        )
        let desert = SearchScorer.score(
            artist: "Mdou Moctar",
            albumTags: ["tuareg", "desert blues", "blues"],
            albumLanguage: nil, wantedTags: wanted, targetLanguages: [], similarArtists: [],
            tagMatching: .exact, tagWeights: weights, wantedTagGroups: groups
        )
        // Blues album: one group matched, best 0.6 → 1.2.
        XCTAssertEqual(bluesFlood?.weight ?? 0, 1.2, accuracy: 1e-9)
        // Desert album: both groups matched, best 0.9 and 0.4 → 2.6.
        XCTAssertEqual(desert?.weight ?? 0, 2.6, accuracy: 1e-9)
    }

    func testEmptyWeightsReproduceFlatScoring() {
        let score = SearchScorer.score(
            artist: "Artist", albumTags: ["jazz", "cool jazz"], albumLanguage: nil,
            wantedTags: ["jazz", "cool jazz"], targetLanguages: [], similarArtists: ["artist"],
            tagMatching: .exact
        )
        // 2 + 2 (tags) + 3 (similar): value capped at 5, weight uncapped.
        XCTAssertEqual(score?.value, 5)
        XCTAssertEqual(score?.weight ?? 0, 7.0, accuracy: 1e-9)
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
