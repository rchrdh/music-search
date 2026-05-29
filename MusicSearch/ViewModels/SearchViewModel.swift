import Foundation
import Observation

/// Drives the search screen: holds the query, runs the AI search, and exposes
/// progress and results to the view.
@MainActor
@Observable
final class SearchViewModel {

    enum Phase: Equatable {
        case idle
        case searching
        case results
        case error(String)
    }

    var query = ""
    var phase: Phase = .idle
    var results: [SearchResult] = []
    var progress: Double = 0

    /// Whether the device is using the on-device model or the keyword fallback.
    let usesOnDeviceModel: Bool

    private let service: AISearchService

    init(service: AISearchService = SearchServiceFactory.make()) {
        self.service = service
        self.usesOnDeviceModel = service is FoundationModelSearchService
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSearch: Bool { !trimmedQuery.isEmpty && phase != .searching }

    func run(in albums: [LibraryAlbum]) async {
        let q = trimmedQuery
        guard !q.isEmpty else { return }

        phase = .searching
        progress = 0
        results = []

        // Bridge the @Sendable progress callback back onto the main actor.
        let (stream, continuation) = AsyncStream<Double>.makeStream()
        let progressTask = Task { [weak self] in
            for await value in stream { self?.progress = value }
        }
        defer { progressTask.cancel() }

        do {
            let found = try await service.search(query: q, in: albums) { value in
                continuation.yield(value)
            }
            continuation.finish()
            results = found
            phase = .results
        } catch {
            continuation.finish()
            phase = .error(error.localizedDescription)
        }
    }

    func reset() {
        query = ""
        results = []
        phase = .idle
        progress = 0
    }
}
