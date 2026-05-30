import Foundation

/// Exports the loaded library as a JSON array of `AlbumInput`, for use with the
/// `musicsearch-eval` command-line harness (so search quality can be refined
/// off-device).
enum LibraryExporter {
    static func writeJSON(_ albums: [LibraryAlbum]) throws -> URL {
        let inputs = albums.map {
            AlbumInput(
                id: $0.id.rawValue,
                title: $0.title,
                artist: $0.artistName,
                genres: $0.genreNames
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(inputs)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-export.json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
