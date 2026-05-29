import Foundation

/// An incremental update emitted while a search is running, so the UI can show
/// matches as they're found instead of waiting for the whole library.
struct SearchUpdate: Sendable {
    /// New matches discovered by the batch that just completed.
    let newResults: [SearchResult]
    /// Overall progress so far, in the range 0...1.
    let progress: Double
}

/// Abstracts the natural-language search so the matching engine can be swapped
/// (on-device Foundation Models today, something else later).
protocol AISearchService: Sendable {
    /// Streams matches as batches of the library are evaluated. Results arrive
    /// progressively; the stream finishes when the whole library is searched.
    func searchStream(
        query: String,
        in albums: [LibraryAlbum]
    ) -> AsyncThrowingStream<SearchUpdate, Error>
}

/// Which engine backs the active search service, for display purposes.
enum SearchEngine {
    case metadata
    case onDevice
    case keyword
}

/// Chooses the best available search implementation. Prefers metadata-based
/// search (most accurate) when a Last.fm key is configured, then the on-device
/// model, then a keyword fallback.
enum SearchServiceFactory {
    static func make() -> AISearchService {
        if let key = Secrets.lastFMAPIKey {
            return MetadataSearchService(client: LastFMClient(apiKey: key))
        }
        if FoundationModelSearchService.isAvailable {
            return FoundationModelSearchService()
        }
        return LocalSearchService()
    }

    static func engine(for service: AISearchService) -> SearchEngine {
        if service is MetadataSearchService { return .metadata }
        if service is FoundationModelSearchService { return .onDevice }
        return .keyword
    }
}
