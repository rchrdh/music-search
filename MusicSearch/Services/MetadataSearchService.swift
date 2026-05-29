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
                let wantedTags = intent.descriptiveTags

                var results: [SearchResult] = []
                for album in albums {
                    let albumTags = tagsByID[album.id.rawValue] ?? []
                    if let result = score(
                        album: album,
                        albumTags: albumTags,
                        wantedTags: wantedTags,
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

    /// Scores a single album against the intent. Returns nil below threshold.
    private func score(
        album: LibraryAlbum,
        albumTags: [String],
        wantedTags: [String],
        similarArtists: Set<String>
    ) -> SearchResult? {
        var score = 0
        var reasons: [String] = []

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
