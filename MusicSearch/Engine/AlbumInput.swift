import Foundation

/// A platform-agnostic album, used by the search engine and the evaluation
/// harness. The iOS app maps its MusicKit albums into this, and the CLI loads
/// them from a JSON export of a library.
public struct AlbumInput: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var artist: String
    public var genres: [String]
    /// Pre-fetched Last.fm tags. When present, the eval harness uses them
    /// instead of hitting the network, making runs offline and deterministic.
    public var tags: [String]?
    /// Pre-fetched ISO 639-3 language code ("" = looked up, unknown).
    public var language: String?

    public init(
        id: String,
        title: String,
        artist: String,
        genres: [String] = [],
        tags: [String]? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.genres = genres
        self.tags = tags
        self.language = language
    }
}
