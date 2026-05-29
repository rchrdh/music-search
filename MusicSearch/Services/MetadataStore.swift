import Foundation

/// On-disk cache of the metadata we fetch from Last.fm, so enrichment is a
/// one-time cost and searches are instant on later launches.
///
/// Keyed by `MusicItemID.rawValue` for album tags, and by lowercased artist
/// name for similar-artist lists. An album present with an empty tag list is
/// treated as "already processed" so we don't refetch it every launch.
actor MetadataStore {
    static let shared = MetadataStore()

    private struct CacheData: Codable {
        var tagsByAlbumID: [String: [String]] = [:]
        var similarByArtist: [String: [String]] = [:]
    }

    private var data = CacheData()
    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("MusicSearchMetadata.json")
        if let stored = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(CacheData.self, from: stored) {
            data = decoded
        }
    }

    func tags(forAlbumID id: String) -> [String]? {
        data.tagsByAlbumID[id]
    }

    func hasTags(forAlbumID id: String) -> Bool {
        data.tagsByAlbumID[id] != nil
    }

    func setTags(_ tags: [String], forAlbumID id: String) {
        data.tagsByAlbumID[id] = tags
        persist()
    }

    /// A snapshot of all album tags for fast, synchronous scoring during search.
    func tagsSnapshot() -> [String: [String]] {
        data.tagsByAlbumID
    }

    func similarArtists(for artist: String) -> [String]? {
        data.similarByArtist[artist]
    }

    func setSimilarArtists(_ artists: [String], for artist: String) {
        data.similarByArtist[artist] = artists
        persist()
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }
}
