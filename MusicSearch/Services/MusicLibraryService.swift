import Foundation
import MusicKit

/// Reads the signed-in user's Apple Music library.
enum MusicLibraryService {

    /// Fetches the user's saved albums, paging through the library up to `max`
    /// albums. Genres and artwork come back populated on library albums.
    static func fetchAlbums(max: Int = 1_000) async throws -> [LibraryAlbum] {
        var collected: [Album] = []
        var request = MusicLibraryRequest<Album>()
        let pageSize = 100
        request.limit = pageSize
        var offset = 0

        while collected.count < max {
            request.offset = offset
            let response = try await request.response()
            let items = Array(response.items)
            if items.isEmpty { break }
            collected.append(contentsOf: items)
            if items.count < pageSize { break }
            offset += items.count
        }

        return collected.prefix(max).map(LibraryAlbum.init)
    }
}
