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
    private let musicBrainz = MusicBrainzClient()
    /// MusicBrainz asks anonymous clients to stay under one request per second.
    private let musicBrainzInterval: Duration = .seconds(1.1)

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

                let tagsByID = await store.tagsSnapshot()
                let wantedTags = intent.descriptiveTags
                let targetLanguages = SearchScorer.targetLanguageCodes(from: wantedTags)

                // Language is the expensive signal (MusicBrainz, ~1/sec). Resolve
                // it lazily and only for the albums *this* query shortlists — those
                // with a cheap tag/similar signal — instead of pre-enriching the
                // whole library. Results are cached, so later queries are instant.
                if !targetLanguages.isEmpty {
                    var candidates: [LibraryAlbum] = []
                    for album in albums {
                        let id = album.id.rawValue
                        if await store.hasLanguage(forAlbumID: id) { continue }
                        if SearchScorer.hasNonLanguageSignal(
                            artist: album.artistName,
                            albumTags: tagsByID[id] ?? [],
                            wantedTags: wantedTags,
                            similarArtists: similar,
                            referenceArtists: referenceArtists
                        ) {
                            candidates.append(album)
                        }
                    }
                    for (index, album) in candidates.enumerated() {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        let language = await musicBrainz.language(artist: album.artistName, album: album.title)
                        await store.setLanguage(language ?? "", forAlbumID: album.id.rawValue)
                        continuation.yield(SearchUpdate(newResults: [], progress: Double(index + 1) / Double(candidates.count)))
                        if index < candidates.count - 1 {
                            try? await Task.sleep(for: musicBrainzInterval)
                        }
                    }
                }

                if Task.isCancelled {
                    continuation.finish()
                    return
                }

                let languageByID = await store.languageSnapshot()

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
                        referenceArtists: referenceArtists
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
