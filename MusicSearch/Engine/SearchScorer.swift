import Foundation

/// The platform-agnostic heart of the recommender: given an album's metadata
/// and a parsed query, decide whether it matches and how strongly. Pure and
/// offline — unit-testable and shared by both the app and the eval harness.
public enum SearchScorer {

    public struct Score: Sendable {
        /// Coarse 0–5 strength, used for the retrieval threshold and display.
        public let value: Int
        /// Continuous ranking key: like `value`, but each tag match is scaled
        /// by its specificity weight, so an album matching "tuareg" sorts
        /// above one matching only "blues". Without weights it equals the
        /// uncapped flat score.
        public let weight: Double
        public let reason: String
    }

    /// How wanted tags are compared against an album's tags.
    public enum TagMatching: Sendable {
        /// Substring overlap in either direction ("french" matches "french pop").
        /// For raw, ungrounded query words.
        case substring
        /// Exact equality — for wanted tags already grounded into the library's
        /// vocabulary via `TagVocabulary.ground`, where the fuzziness has
        /// already happened on the query side.
        case exact
    }

    /// Minimum score for an album to be considered a match.
    public static let defaultThreshold = 2

    /// Maps language names to the ISO 639-3 codes MusicBrainz uses.
    public static let languageCodes: [String: String] = [
        "french": "fra", "spanish": "spa", "italian": "ita", "german": "deu",
        "portuguese": "por", "japanese": "jpn", "english": "eng", "korean": "kor",
        "chinese": "zho", "mandarin": "zho", "russian": "rus", "dutch": "nld",
        "swedish": "swe", "norwegian": "nor", "danish": "dan", "polish": "pol",
        "arabic": "ara", "hindi": "hin", "turkish": "tur", "greek": "ell",
    ]

    /// The ISO codes implied by any language words among the wanted tags.
    public static func targetLanguageCodes(from wantedTags: [String]) -> Set<String> {
        var codes = Set<String>()
        for tag in wantedTags {
            for (name, code) in languageCodes where tag.contains(name) {
                codes.insert(code)
            }
        }
        return codes
    }

    /// Scores one album. `similarArtists` and `targetLanguages` should be
    /// computed once per query and passed in. `tagWeights` (from
    /// `TagVocabulary.specificity`) scales each tag match's contribution to
    /// the ranking weight by how rare the tag is; tags missing from the map
    /// count at full weight, so an empty map reproduces flat scoring.
    /// `wantedTagGroups` (from `TagVocabulary.groundedGroups`) makes the
    /// ranking weight count each query concept once, at its best-matching
    /// tag — without it, an album tagged with six variants of "blues" earns
    /// six times the weight for one query word.
    public static func score(
        artist: String,
        albumTags: [String],
        albumLanguage: String?,
        wantedTags: [String],
        targetLanguages: Set<String>,
        similarArtists: Set<String>,
        referenceArtists: Set<String> = [],
        threshold: Int = defaultThreshold,
        tagMatching: TagMatching = .substring,
        tagWeights: [String: Double] = [:],
        wantedTagGroups: [[String]]? = nil
    ) -> Score? {
        var score = 0
        var weight = 0.0
        var reasons: [String] = []

        // "Albums like X" means *other* artists: an album by a referenced
        // artist isn't a recommendation, it's the artist itself. Exclude it
        // outright so it never crowds out genuine similar-artist results.
        // Substring, not equality: collaboration credits ("Brian Eno &
        // Harold Budd", "Robert Fripp & Brian Eno") are still the artist.
        if isByReferencedArtist(artist: artist, referenceArtists: referenceArtists) {
            return nil
        }

        // Language: when the user asked for a language and MusicBrainz knows
        // this album's language, trust it — match strongly, or exclude outright
        // on a confirmed mismatch (the key precision win).
        if !targetLanguages.isEmpty, let language = albumLanguage, !language.isEmpty {
            if targetLanguages.contains(language) {
                score += 4
                weight += 4
                reasons.append("Confirmed language")
            } else {
                return nil
            }
        }

        // Tag matches (substring either direction, so "french" matches
        // "french pop" and vice versa). The coarse score counts every match;
        // the ranking weight counts each query concept (group) once, at its
        // most specific matching tag.
        var matchedTags: [String] = []
        for wanted in wantedTags where tagMatches(wanted, in: albumTags, mode: tagMatching) {
            score += 2
            matchedTags.append(wanted)
        }
        if !matchedTags.isEmpty {
            reasons.append("Tagged \(matchedTags.joined(separator: ", "))")
        }
        if let groups = wantedTagGroups {
            for group in groups {
                let best = group
                    .filter { tagMatches($0, in: albumTags, mode: tagMatching) }
                    .map { tagWeights[$0] ?? 1.0 }
                    .max()
                if let best { weight += 2 * best }
            }
        } else {
            for matched in matchedTags {
                weight += 2 * (tagWeights[matched] ?? 1.0)
            }
        }

        // Artist similarity for "like X" requests.
        if !similarArtists.isEmpty, similarArtists.contains(artist.lowercased()) {
            score += 3
            weight += 3
            reasons.append("Similar artist")
        }

        guard score >= threshold else { return nil }
        return Score(value: Swift.min(5, score), weight: weight, reason: reasons.joined(separator: " · "))
    }

    /// Whether an album has any signal *other than* a confirmed language — i.e. a
    /// descriptive-tag match or a similar-artist match (and isn't the referenced
    /// artist itself). Lets a caller cheaply decide which albums are worth an
    /// expensive language lookup before paying for one, instead of resolving
    /// language across an entire library.
    public static func hasNonLanguageSignal(
        artist: String,
        albumTags: [String],
        wantedTags: [String],
        similarArtists: Set<String>,
        referenceArtists: Set<String> = [],
        tagMatching: TagMatching = .substring
    ) -> Bool {
        let key = artist.lowercased()
        if isByReferencedArtist(artist: artist, referenceArtists: referenceArtists) { return false }
        if similarArtists.contains(key) { return true }
        return wantedTags.contains { tagMatches($0, in: albumTags, mode: tagMatching) }
    }

    /// Whether the album's artist credit includes a referenced artist —
    /// exactly, or as part of a collaboration credit.
    public static func isByReferencedArtist(artist: String, referenceArtists: Set<String>) -> Bool {
        let credit = artist.lowercased()
        return referenceArtists.contains { credit.contains($0) }
    }

    private static func tagMatches(_ wanted: String, in albumTags: [String], mode: TagMatching) -> Bool {
        switch mode {
        case .substring:
            return albumTags.contains { $0.contains(wanted) || wanted.contains($0) }
        case .exact:
            return albumTags.contains(wanted)
        }
    }
}
