import Foundation
import MusicKit

/// A lightweight, `Sendable` wrapper around a MusicKit `Album` from the user's
/// library. It exposes just the metadata we show in the UI and feed to the
/// on-device language model, while keeping the underlying `Album` around so we
/// can play it or add it to a playlist.
struct LibraryAlbum: Identifiable, Hashable, Sendable {
    let album: Album

    var id: MusicItemID { album.id }
    var title: String { album.title }
    var artistName: String { album.artistName }
    var genreNames: [String] { album.genreNames }
    var artwork: Artwork? { album.artwork }

    /// A compact one-line description used when prompting the language model.
    var promptDescription: String {
        let genres = genreNames.isEmpty ? "" : " [\(genreNames.joined(separator: ", "))]"
        return "\"\(title)\" by \(artistName)\(genres)"
    }
}

extension LibraryAlbum {
    init(_ album: Album) {
        self.album = album
    }
}
