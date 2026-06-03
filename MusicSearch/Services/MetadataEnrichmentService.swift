import Foundation

/// Fetches Last.fm tags for every album not already cached, with bounded
/// concurrency, and stores them. Safe to call on every library load — it only
/// does network work for albums it hasn't seen before.
///
/// Language is deliberately *not* enriched here. MusicBrainz serves languages at
/// ~1 request/sec, so resolving a whole library up front would take many minutes
/// (and most albums are never the subject of a language query). Instead
/// `MetadataSearchService` resolves language lazily at query time — only for the
/// albums a language query actually shortlists — and caches the result.
struct MetadataEnrichmentService: Sendable {
    let client: LastFMClient
    let store: MetadataStore

    private let maxConcurrent = 4

    /// Enriches `albums` with Last.fm tags (fast, concurrent), reporting progress
    /// (0...1) over the albums that still need fetching.
    func enrich(
        _ albums: [LibraryAlbum],
        progress: @escaping @Sendable (Double) -> Void
    ) async {
        var pending: [LibraryAlbum] = []
        for album in albums {
            if await store.hasTags(forAlbumID: album.id.rawValue) { continue }
            pending.append(album)
        }

        let total = pending.count
        guard total > 0 else {
            progress(1)
            return
        }

        var done = 0
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            for _ in 0 ..< Swift.min(maxConcurrent, pending.count) {
                let album = pending[next]
                next += 1
                group.addTask { await fetchTags(album) }
            }
            for await _ in group {
                done += 1
                progress(Double(done) / Double(total))
                if next < pending.count {
                    let album = pending[next]
                    next += 1
                    group.addTask { await fetchTags(album) }
                }
            }
        }

        progress(1)
    }

    private func fetchTags(_ album: LibraryAlbum) async {
        let tags = await client.tags(artist: album.artistName, album: album.title)
        // Store even an empty result so the album is marked as processed.
        await store.setTags(tags, forAlbumID: album.id.rawValue)
    }
}
