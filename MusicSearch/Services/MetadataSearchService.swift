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
                // Rank by specificity-weighted score — a match on a rare tag
                // ("tuareg") sorts above one on a ubiquitous tag ("pop") —
                // counting each query concept once at its best-matching tag.
                let wantedTagGroups = TagVocabulary.groundedGroups(intent.descriptiveTags, in: vocabulary)
                let wantedTags = wantedTagGroups.flatMap { $0 }
                let tagWeights = TagVocabulary.specificity(in: tagsByID.values)

                var scored: [(result: SearchResult, weight: Double)] = []
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
                        tagMatching: .exact,
                        tagWeights: tagWeights,
                        wantedTagGroups: wantedTagGroups
                    ) {
                        scored.append(
                            (SearchResult(album: album, relevance: score.value, reason: score.reason), score.weight)
                        )
                    }
                }
                scored.sort { $0.weight > $1.weight }
                let results = scored.map(\.result)

                continuation.yield(SearchUpdate(newResults: results, progress: 1))
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
