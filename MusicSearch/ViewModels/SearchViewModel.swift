import Foundation
import Observation

/// Drives the search screen: holds the query, runs the AI search, and exposes
/// progress and results to the view. Results stream in progressively, repeated
/// queries are served from an in-memory cache, and starting a new search
/// cancels any search already in flight.
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

    /// Which engine is backing search, for display.
    let engine: SearchEngine

    private let service: AISearchService
    private var searchTask: Task<Void, Never>?
    /// Cached results keyed by library size + normalized query.
    private var cache: [String: [SearchResult]] = [:]

    init(service: AISearchService = SearchServiceFactory.make()) {
        self.service = service
        self.engine = SearchServiceFactory.engine(for: service)
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSearch: Bool { !trimmedQuery.isEmpty && phase != .searching }

    /// Starts a search, cancelling any search already running.
    func search(in albums: [LibraryAlbum]) {
        searchTask?.cancel()
        searchTask = Task { await run(in: albums) }
    }

    private func run(in albums: [LibraryAlbum]) async {
        let q = trimmedQuery
        guard !q.isEmpty else { return }

        // Serve identical repeat searches instantly.
        let key = cacheKey(for: q, albums: albums)
        if let cached = cache[key] {
            results = cached
            progress = 1
            phase = .results
            return
        }

        phase = .searching
        progress = 0
        results = []

        var accumulated: [SearchResult] = []
        do {
            for try await update in service.searchStream(query: q, in: albums) {
                if Task.isCancelled { return }
                if !update.newResults.isEmpty {
                    accumulated.append(contentsOf: update.newResults)
                    accumulated.sort { $0.relevance > $1.relevance }
                    results = accumulated
                }
                progress = update.progress
            }
            if Task.isCancelled { return }
            cache[key] = accumulated
            phase = .results
        } catch is CancellationError {
            // Superseded by a newer search; leave state for that search to own.
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func reset() {
        searchTask?.cancel()
        query = ""
        results = []
        phase = .idle
        progress = 0
    }

    private func cacheKey(for query: String, albums: [LibraryAlbum]) -> String {
        "\(albums.count)|\(query.lowercased())"
    }
}
