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

        // Fall back to meaningful words when nothing specific was found.
        if tags.isEmpty && referenceArtists.isEmpty {
            let stopWords: Set<String> = ["album", "albums", "music", "song", "songs", "that", "with", "the"]
            tags = lower
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        }

        return ParsedQuery(descriptiveTags: tags, referenceArtists: referenceArtists)
    }
}
