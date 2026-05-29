import Foundation
import FoundationModels

/// Natural-language album search powered by Apple's on-device language model.
///
/// The on-device model has a modest context window, so we present the library
/// to it in numbered batches and ask it to pick the albums that match the
/// user's request. The model uses its own knowledge of artists, genres,
/// languages, and moods to judge fuzzy queries like "albums like Brian Eno"
/// or "music in French".
struct FoundationModelSearchService: AISearchService {

    /// How many albums to include per request to the model.
    private let batchSize = 40

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func search(
        query: String,
        in albums: [LibraryAlbum],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SearchResult] {
        let batches = albums.chunked(into: batchSize)
        guard !batches.isEmpty else { return [] }

        var results: [SearchResult] = []
        for (index, batch) in batches.enumerated() {
            // A failure on one batch shouldn't lose the whole search.
            if let matches = try? await searchBatch(query: query, batch: batch) {
                results.append(contentsOf: matches)
            }
            progress(Double(index + 1) / Double(batches.count))
        }

        return results.sorted { $0.relevance > $1.relevance }
    }

    private func searchBatch(query: String, batch: [LibraryAlbum]) async throws -> [SearchResult] {
        let list = batch.enumerated()
            .map { "\($0.offset). \($0.element.promptDescription)" }
            .joined(separator: "\n")

        let instructions = """
        You are a knowledgeable music librarian. The user is searching their \
        personal music library with a natural-language request. You will be \
        given a numbered list of albums (title, artist, and any genres) and \
        the request. Choose only the albums that genuinely match. Use what you \
        know about each artist and genre to judge style, mood, language, and \
        similarity — for example a request like "albums like Brian Eno" should \
        match ambient or art-rock records, and "music in French" should match \
        French-language artists. If nothing matches, return an empty list. \
        Never invent albums that are not in the list.
        """

        let prompt = """
        Request: "\(query)"

        Albums:
        \(list)

        Return the matching albums by their number.
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: BatchMatches.self)

        return response.content.matches.compactMap { match in
            guard match.number >= 0, match.number < batch.count else { return nil }
            let relevance = Swift.max(1, Swift.min(5, match.relevance))
            return SearchResult(
                album: batch[match.number],
                relevance: relevance,
                reason: match.reason
            )
        }
    }
}

/// Structured output the model returns for a single batch.
@Generable
struct BatchMatches {
    @Guide(description: "The albums from the list that match the user's request.")
    let matches: [Match]

    @Generable
    struct Match {
        @Guide(description: "The number of the matching album, exactly as shown in the list.")
        let number: Int

        @Guide(description: "How strongly it matches, from 1 (weak) to 5 (strong).")
        let relevance: Int

        @Guide(description: "A short, one-sentence reason this album matches the request.")
        let reason: String
    }
}
