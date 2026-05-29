import Foundation
import MusicKit

/// Thin wrapper over MusicKit playback and playlist creation.
@MainActor
enum PlaybackService {

    /// Plays an album from the start using the system music player.
    static func play(_ album: LibraryAlbum) async throws {
        let player = ApplicationMusicPlayer.shared
        player.queue = [album.album]
        try await player.play()
    }

    /// Creates a new library playlist from the given albums' tracks.
    ///
    /// Note: this is a basic implementation kept intentionally simple for the
    /// core flow; richer playlist editing is a follow-up.
    @discardableResult
    static func createPlaylist(named name: String, from albums: [LibraryAlbum]) async throws -> Playlist {
        var tracks: [Track] = []
        for album in albums {
            let detailed = try await album.album.with([.tracks])
            if let albumTracks = detailed.tracks {
                tracks.append(contentsOf: albumTracks)
            }
        }
        return try await MusicLibrary.shared.createPlaylist(name: name, items: tracks)
    }
}
