import Foundation

/// Searches the library by matching the query's intent against real metadata
/// (Last.fm tags and similar-artist relationships) rather than asking a model
/// to recall facts. This is both more accurate and far faster: the heavy
/// lifting happened once during enrichment, so a search is just query parsing
/// plus local scoring.
struct MetadataSearchService: AISearchService {
    let client: LastFMClient
    let store: MetadataStore
    private let parser = QueryParser()

    /// Minimum score for an album to be returned.
    private let threshold = 2

    init(client: LastFMClient, store: MetadataStore = .shared) {
        self.client = client
        self.store = store
    }

    func searchStream(
        query: String,
        in albums: [LibraryAlbum]
    ) -> AsyncThrowingStream<SearchUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let intent = await parser.parse(query)

                // Resolve the set of artists that count as "similar" for any
                // referenced artist, caching the lookups.
                var similar = Set<String>()
                for artist in intent.referenceArtists {
                    let key = artist.lowercased()
                    similar.insert(key)
                    if let cached = await store.similarArtists(for: key) {
                        similar.formUnion(cached)
                    } else {
                        let fetched = await client.similarArtists(to: artist)
                        await store.setSimilarArtists(fetched, for: key)
                        similar.formUnion(fetched)
                    }
                }

                if Task.isCancelled {
                    continuation.finish()
                    return
                }

                let tagsByID = await store.tagsSnapshot()
                let languageByID = await store.languageSnapshot()
                let wantedTags = intent.descriptiveTags
                let targetLanguages = targetLanguageCodes(from: wantedTags)

                var results: [SearchResult] = []
                for album in albums {
                    let albumTags = tagsByID[album.id.rawValue] ?? []
                    if let result = score(
                        album: album,
                        albumTags: albumTags,
                        albumLanguage: languageByID[album.id.rawValue],
                        wantedTags: wantedTags,
                        targetLanguages: targetLanguages,
                        similarArtists: similar
                    ) {
                        results.append(result)
                    }
                }
                results.sort { $0.relevance > $1.relevance }

                continuation.yield(SearchUpdate(newResults: results, progress: 1))
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Maps language names to the ISO 639-3 codes MusicBrainz uses.
    private static let languageCodes: [String: String] = [
        "french": "fra", "spanish": "spa", "italian": "ita", "german": "deu",
        "portuguese": "por", "japanese": "jpn", "english": "eng", "korean": "kor",
        "chinese": "zho", "mandarin": "zho", "russian": "rus", "dutch": "nld",
        "swedish": "swe", "norwegian": "nor", "danish": "dan", "polish": "pol",
        "arabic": "ara", "hindi": "hin", "turkish": "tur", "greek": "ell",
    ]

    /// The ISO codes implied by any language words among the wanted tags.
    private func targetLanguageCodes(from wantedTags: [String]) -> Set<String> {
        var codes = Set<String>()
        for tag in wantedTags {
            for (name, code) in Self.languageCodes where tag.contains(name) {
                codes.insert(code)
            }
        }
        return codes
    }

    /// Scores a single album against the intent. Returns nil below threshold.
    private func score(
        album: LibraryAlbum,
        albumTags: [String],
        albumLanguage: String?,
        wantedTags: [String],
        targetLanguages: Set<String>,
        similarArtists: Set<String>
    ) -> SearchResult? {
        var score = 0
        var reasons: [String] = []

        // Language: if the user asked for a language and MusicBrainz has told us
        // this album's language, trust it — match strongly, or exclude outright
        // when it's a confirmed mismatch (the key precision win).
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
        if !similarArtists.isEmpty, similarArtists.contains(album.artistName.lowercased()) {
            score += 3
            reasons.append("Similar artist")
        }

        guard score >= threshold else { return nil }

        return SearchResult(
            album: album,
            relevance: Swift.min(5, score),
            reason: reasons.joined(separator: " · ")
        )
    }
}
