import Foundation

/// Fetches Last.fm tags for every album not already cached, with bounded
/// concurrency, and stores them. Safe to call on every library load — it only
/// does network work for albums it hasn't seen before.
struct MetadataEnrichmentService: Sendable {
    let client: LastFMClient
    let store: MetadataStore
    private let musicBrainz = MusicBrainzClient()

    private let maxConcurrent = 4
    /// Spacing between MusicBrainz requests (it asks for ≤ 1 req/sec).
    private let musicBrainzInterval: Duration = .seconds(1.1)

    /// Enriches `albums`, reporting progress (0...1) over the work that actually
    /// needs doing: Last.fm tags (fast, concurrent) then MusicBrainz languages
    /// (slow, serialized to respect the rate limit).
    func enrich(
        _ albums: [LibraryAlbum],
        progress: @escaping @Sendable (Double) -> Void
    ) async {
        var tagsPending: [LibraryAlbum] = []
        var languagePending: [LibraryAlbum] = []
        for album in albums {
            let hasTags = await store.hasTags(forAlbumID: album.id.rawValue)
            if !hasTags { tagsPending.append(album) }
            let hasLanguage = await store.hasLanguage(forAlbumID: album.id.rawValue)
            if !hasLanguage { languagePending.append(album) }
        }

        let total = tagsPending.count + languagePending.count
        guard total > 0 else {
            progress(1)
            return
        }

        var done = 0

        // Phase 1: Last.fm tags, concurrently.
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            for _ in 0 ..< Swift.min(maxConcurrent, tagsPending.count) {
                let album = tagsPending[next]
                next += 1
                group.addTask { await fetchTags(album) }
            }
            for await _ in group {
                done += 1
                progress(Double(done) / Double(total))
                if next < tagsPending.count {
                    let album = tagsPending[next]
                    next += 1
                    group.addTask { await fetchTags(album) }
                }
            }
        }

        // Phase 2: MusicBrainz languages, serialized and throttled.
        for album in languagePending {
            if Task.isCancelled { break }
            let language = await musicBrainz.language(artist: album.artistName, album: album.title)
            await store.setLanguage(language ?? "", forAlbumID: album.id.rawValue)
            done += 1
            progress(Double(done) / Double(total))
            try? await Task.sleep(for: musicBrainzInterval)
        }

        progress(1)
    }

    private func fetchTags(_ album: LibraryAlbum) async {
        let tags = await client.tags(artist: album.artistName, album: album.title)
        // Store even an empty result so the album is marked as processed.
        await store.setTags(tags, forAlbumID: album.id.rawValue)
    }
}
