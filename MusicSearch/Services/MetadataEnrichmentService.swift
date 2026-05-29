import Foundation

/// Fetches Last.fm tags for every album not already cached, with bounded
/// concurrency, and stores them. Safe to call on every library load — it only
/// does network work for albums it hasn't seen before.
struct MetadataEnrichmentService: Sendable {
    let client: LastFMClient
    let store: MetadataStore

    private let maxConcurrent = 4

    /// Enriches `albums`, reporting progress (0...1) over the albums that
    /// actually needed fetching.
    func enrich(
        _ albums: [LibraryAlbum],
        progress: @escaping @Sendable (Double) -> Void
    ) async {
        var pending: [LibraryAlbum] = []
        for album in albums {
            let alreadyCached = await store.hasTags(forAlbumID: album.id.rawValue)
            if !alreadyCached { pending.append(album) }
        }

        guard !pending.isEmpty else {
            progress(1)
            return
        }

        await withTaskGroup(of: Void.self) { group in
            var next = 0
            for _ in 0 ..< Swift.min(maxConcurrent, pending.count) {
                let album = pending[next]
                next += 1
                group.addTask { await enrichOne(album) }
            }

            var done = 0
            for await _ in group {
                done += 1
                progress(Double(done) / Double(pending.count))
                if next < pending.count {
                    let album = pending[next]
                    next += 1
                    group.addTask { await enrichOne(album) }
                }
            }
        }
    }

    private func enrichOne(_ album: LibraryAlbum) async {
        let tags = await client.tags(artist: album.artistName, album: album.title)
        // Store even an empty result so the album is marked as processed.
        await store.setTags(tags, forAlbumID: album.id.rawValue)
    }
}
