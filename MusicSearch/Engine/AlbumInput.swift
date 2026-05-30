import Foundation

/// A platform-agnostic album, used by the search engine and the evaluation
/// harness. The iOS app maps its MusicKit albums into this, and the CLI loads
/// them from a JSON export of a library.
public struct AlbumInput: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var artist: String
    public var genres: [String]

    public init(id: String, title: String, artist: String, genres: [String] = []) {
        self.id = id
        self.title = title
        self.artist = artist
        self.genres = genres
    }
}
