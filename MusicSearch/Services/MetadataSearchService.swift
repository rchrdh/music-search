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
                // Parse with the library's tag vocabulary in hand, so the model
                // can translate the request into tags that actually occur in
                // this library instead of echoing the user's words.
                let tagsByID = await store.tagsSnapshot()
                let vocabulary = Set(tagsByID.values.joined())
                let promptVocabulary = TagVocabulary.topTags(in: tagsByID.values)
                let intent = await parser.parse(query, tagVocabulary: promptVocabulary)

                // Resolve the set of artists that count as "similar" for any
                // referenced artist, caching the lookups.
                let referenceArtists = Set(intent.referenceArtists.map { $0.lowercased() })
                var similar = Set<String>()
                for artist in intent.referenceArtists {
                    let key = artist.lowercased()
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

                let languageByID = await store.languageSnapshot()
                // Language codes come from the raw intent (a language word like
                // "french" may not exist as a library tag); tag matching uses
                // the grounded vocabulary tags, exactly.
                let targetLanguages = SearchScorer.targetLanguageCodes(from: intent.descriptiveTags)
                let wantedTags = TagVocabulary.ground(intent.descriptiveTags, in: vocabulary)

                var results: [SearchResult] = []
                for album in albums {
                    let albumTags = tagsByID[album.id.rawValue] ?? []
                    if let score = SearchScorer.score(
                        artist: album.artistName,
                        albumTags: albumTags,
                        albumLanguage: languageByID[album.id.rawValue],
                        wantedTags: wantedTags,
                        targetLanguages: targetLanguages,
                        similarArtists: similar,
                        referenceArtists: referenceArtists,
                        tagMatching: .exact
                    ) {
                        results.append(
                            SearchResult(album: album, relevance: score.value, reason: score.reason)
                        )
                    }
                }
                results.sort { $0.relevance > $1.relevance }

                continuation.yield(SearchUpdate(newResults: results, progress: 1))
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
