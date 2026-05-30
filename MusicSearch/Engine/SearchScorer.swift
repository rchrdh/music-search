import Foundation

/// The platform-agnostic heart of the recommender: given an album's metadata
/// and a parsed query, decide whether it matches and how strongly. Pure and
/// offline — unit-testable and shared by both the app and the eval harness.
public enum SearchScorer {

    public struct Score: Sendable {
        public let value: Int
        public let reason: String
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
    /// computed once per query and passed in.
    public static func score(
        artist: String,
        albumTags: [String],
        albumLanguage: String?,
        wantedTags: [String],
        targetLanguages: Set<String>,
        similarArtists: Set<String>,
        threshold: Int = defaultThreshold
    ) -> Score? {
        var score = 0
        var reasons: [String] = []

        // Language: when the user asked for a language and MusicBrainz knows
        // this album's language, trust it — match strongly, or exclude outright
        // on a confirmed mismatch (the key precision win).
        if !targetLanguages.isEmpty, let language = albumLanguage, !language.isEmpty {
            if targetLanguages.contains(language) {
                score += 4
                reasons.append("Confirmed language")
            } else {
                return nil
            }
        }

        // Tag matches (substring either direction, so "french" matches
        // "french pop" and vice versa).
        var matchedTags: [String] = []
        for wanted in wantedTags {
            if albumTags.contains(where: { $0.contains(wanted) || wanted.contains($0) }) {
                score += 2
                matchedTags.append(wanted)
            }
        }
        if !matchedTags.isEmpty {
            reasons.append("Tagged \(matchedTags.joined(separator: ", "))")
        }

        // Artist similarity for "like X" requests.
        if !similarArtists.isEmpty, similarArtists.contains(artist.lowercased()) {
            score += 3
            reasons.append("Similar artist")
        }

        guard score >= threshold else { return nil }
        return Score(value: Swift.min(5, score), reason: reasons.joined(separator: " · "))
    }
}
