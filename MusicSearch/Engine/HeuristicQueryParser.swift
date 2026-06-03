import Foundation

/// A dependency-free query parser. Produces the same `ParsedQuery` the app's
/// on-device parser does, and is the parser used by the evaluation harness
/// (which can't run the on-device model).
public struct HeuristicQueryParser: Sendable {
    public init() {}

    public func parse(_ query: String) -> ParsedQuery {
        let lower = query.lowercased()

        // "like X" / "similar to X" / "sounds like X" → reference artist.
        var referenceArtists: [String] = []
        for marker in ["like ", "similar to ", "sounds like "] {
            if let range = lower.range(of: marker) {
                let artist = String(query[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " .\"'"))
                if !artist.isEmpty { referenceArtists.append(artist) }
            }
        }

        var tags: [String] = []
        if lower.contains("no vocal") || lower.contains("without vocal") || lower.contains("instrumental") {
            tags.append("instrumental")
        }
        for language in ["french", "spanish", "italian", "german", "portuguese", "japanese", "english"] {
            if lower.contains(language) { tags.append(language) }
        }

        // Pull descriptive genre/style words out of the query too. When there's
        // a "like X" clause, only scan the text *before* it, so the referenced
        // artist's name isn't mistaken for a tag ("funk albums like Funkadelic"
        // → tag "funk", reference "Funkadelic"). This runs alongside any
        // reference artist, not just when nothing else was found.
        let descriptivePart: Substring
        if let markerStart = ["like ", "similar to ", "sounds like "]
            .compactMap({ lower.range(of: $0)?.lowerBound })
            .min() {
            descriptivePart = lower[..<markerStart]
        } else {
            descriptivePart = lower[...]
        }
        let stopWords: Set<String> = ["album", "albums", "music", "song", "songs", "that", "with", "the"]
        for word in descriptivePart.split(whereSeparator: { !$0.isLetter }).map(String.init)
        where word.count > 2 && !stopWords.contains(word) && !tags.contains(word) {
            tags.append(word)
        }

        return ParsedQuery(descriptiveTags: tags, referenceArtists: referenceArtists)
    }
}
