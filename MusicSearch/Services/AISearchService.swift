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

/// Errors surfaced when metadata search can't run. Search is metadata-only, so
/// rather than silently degrading we report these to the user.
enum SearchError: LocalizedError {
    case noAPIKey
    case lastFMUnreachable

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Last.fm API key configured. Add one in Secrets.plist (or the Run scheme) to enable search."
        case .lastFMUnreachable:
            return "Can't reach Last.fm. Check your connection and try again."
        }
    }
}

/// Builds the search service. Search is **metadata-only** (Last.fm): the
/// on-device model is intentionally not used to *generate* results — it only
/// powers query understanding in `QueryParser`. When no key is configured or
/// Last.fm can't be reached, search surfaces a `SearchError` rather than
/// silently falling back to a weaker engine.
enum SearchServiceFactory {
    static func make() -> AISearchService {
        MetadataSearchService(client: LastFMClient(apiKey: Secrets.lastFMAPIKey ?? ""))
    }

    static func engine(for service: AISearchService) -> SearchEngine {
        .metadata
    }
}
