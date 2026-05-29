import Foundation

/// Abstracts the natural-language search so the matching engine can be swapped
/// (on-device Foundation Models today, something else later).
protocol AISearchService: Sendable {
    /// Returns the albums in `albums` that match the natural-language `query`.
    /// `progress` is called with a value in 0...1 as batches complete.
    func search(
        query: String,
        in albums: [LibraryAlbum],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SearchResult]
}

extension AISearchService {
    func search(query: String, in albums: [LibraryAlbum]) async throws -> [SearchResult] {
        try await search(query: query, in: albums, progress: { _ in })
    }
}

/// Chooses the best available search implementation for this device.
enum SearchServiceFactory {
    static func make() -> AISearchService {
        if FoundationModelSearchService.isAvailable {
            return FoundationModelSearchService()
        }
        return LocalSearchService()
    }
}
