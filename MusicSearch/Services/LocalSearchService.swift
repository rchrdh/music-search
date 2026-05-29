import Foundation

/// A simple keyword fallback used when the on-device language model isn't
/// available (older devices, Apple Intelligence disabled, etc.). It matches
/// query terms against album title, artist, and genres so the app still works.
struct LocalSearchService: AISearchService {
    func searchStream(
        query: String,
        in albums: [LibraryAlbum]
    ) -> AsyncThrowingStream<SearchUpdate, Error> {
        AsyncThrowingStream { continuation in
            let terms = query
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 }

            guard !terms.isEmpty else {
                continuation.yield(SearchUpdate(newResults: [], progress: 1))
                continuation.finish()
                return
            }

            var results: [SearchResult] = []
            for album in albums {
                let haystack = ([album.title, album.artistName] + album.genreNames)
                    .joined(separator: " ")
                    .lowercased()
                let hits = terms.filter { haystack.contains($0) }.count
                guard hits > 0 else { continue }
                let relevance = Swift.min(5, Swift.max(1, hits + 1))
                results.append(
                    SearchResult(
                        album: album,
                        relevance: relevance,
                        reason: "Matched \(hits) of \(terms.count) search terms."
                    )
                )
            }
            results.sort { $0.relevance > $1.relevance }
            continuation.yield(SearchUpdate(newResults: results, progress: 1))
            continuation.finish()
        }
    }
}
