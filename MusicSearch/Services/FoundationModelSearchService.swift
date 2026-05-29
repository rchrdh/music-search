import Foundation
import FoundationModels

/// Natural-language album search powered by Apple's on-device language model.
///
/// The library is evaluated in numbered batches so it fits the model's context
/// window. Batches run with bounded concurrency and stream their matches back
/// as they complete, so the UI fills in progressively. The model judges fuzzy
/// requests ("albums like Brian Eno", "music in French") using its own
/// knowledge of artists, genres, languages, and moods — and is instructed to
/// favour precision so unrelated albums aren't returned.
struct FoundationModelSearchService: AISearchService {

    /// How many albums to include per request. Smaller batches let the model
    /// focus on fewer items at once, which improves accuracy.
    private let batchSize = 25

    /// How many batches to evaluate at the same time.
    private let maxConcurrentBatches = 3

    /// Minimum relevance (1...5) for a match to be surfaced. Higher is stricter.
    private let minimumRelevance = 4

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func searchStream(
        query: String,
        in albums: [LibraryAlbum]
    ) -> AsyncThrowingStream<SearchUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let batches = albums.chunked(into: batchSize)
                guard !batches.isEmpty else {
                    continuation.finish()
                    return
                }
                let total = batches.count

                await withTaskGroup(of: [SearchResult].self) { group in
                    var nextIndex = 0

                    // Prime the group up to the concurrency limit.
                    for _ in 0 ..< Swift.min(maxConcurrentBatches, total) {
                        let batch = batches[nextIndex]
                        nextIndex += 1
                        group.addTask { await self.matches(query: query, batch: batch) }
                    }

                    // As each batch finishes, stream its matches and start the next.
                    var completed = 0
                    for await batchResults in group {
                        completed += 1
                        continuation.yield(
                            SearchUpdate(
                                newResults: batchResults,
                                progress: Double(completed) / Double(total)
                            )
                        )
                        if nextIndex < total {
                            let batch = batches[nextIndex]
                            nextIndex += 1
                            group.addTask { await self.matches(query: query, batch: batch) }
                        }
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Evaluates a single batch. Returns an empty array on failure so one bad
    /// batch never sinks the whole search.
    private func matches(query: String, batch: [LibraryAlbum]) async -> [SearchResult] {
        let list = batch.enumerated()
            .map { "\($0.offset). \($0.element.promptDescription)" }
            .joined(separator: "\n")

        let instructions = """
        You are a meticulous music librarian with deep knowledge of artists, \
        genres, and the languages artists record in. The user is searching \
        their personal music library with a natural-language request. You are \
        given a numbered list of albums (title, artist, and any genres).

        Return ONLY albums that clearly and confidently match the request. Be \
        strict — precision matters far more than completeness:
        - When in doubt, leave it out. Do not include albums that are merely \
          related, adjacent, or "sort of" similar.
        - For a language request (e.g. "music in French"), include an album \
          only if its lyrics are predominantly in that exact language. Albums \
          in any other language — Spanish, Italian, Portuguese, English, etc. \
          — do NOT match and must be excluded. Exclude instrumental albums for \
          language requests.
        - Base your judgement on real knowledge of the specific artist and \
          album. If you do not recognise the artist, or cannot be confident, \
          do not include it.
        - Rate relevance honestly: reserve 5 for certain matches and do not \
          pad the list to seem helpful.

        If nothing clearly matches, return an empty list. Never invent albums \
        that are not in the list.
        """

        let prompt = """
        Request: "\(query)"

        Albums:
        \(list)

        Return only the albums that clearly match, by their number.
        """

        let candidates: [SearchResult]
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: BatchMatches.self,
                options: GenerationOptions(temperature: 0)
            )
            candidates = response.content.matches.compactMap { match in
                guard match.number >= 0, match.number < batch.count else { return nil }
                let relevance = Swift.max(1, Swift.min(5, match.relevance))
                guard relevance >= minimumRelevance else { return nil }
                return SearchResult(
                    album: batch[match.number],
                    relevance: relevance,
                    reason: match.reason
                )
            }
        } catch {
            return []
        }

        // Verification pass: re-check the (usually short) candidate list with a
        // ruthless prompt. The model is far more reliable judging a focused list
        // than items buried in a full batch, so this catches confident-but-wrong
        // matches (e.g. an English album returned for a French query).
        return await verify(query: query, candidates: candidates)
    }

    /// Second-opinion pass that keeps only candidates the model is certain about.
    /// On failure it returns the candidates unchanged so we don't lose matches.
    private func verify(query: String, candidates: [SearchResult]) async -> [SearchResult] {
        guard !candidates.isEmpty else { return [] }

        let list = candidates.enumerated()
            .map { "\($0.offset). \"\($0.element.album.title)\" by \($0.element.album.artistName)" }
            .joined(separator: "\n")

        let instructions = """
        You are rigorously double-checking music search results for accuracy. \
        Keep an album ONLY if you are certain it genuinely satisfies the user's \
        request; remove anything that does not clearly match. For a language \
        request, remove every album that is not predominantly in that exact \
        language — English, Spanish, Italian, or instrumental albums do NOT \
        satisfy a request for French, and so on. When in doubt, remove it.
        """

        let prompt = """
        User request: "\(query)"

        Candidate albums:
        \(list)

        Reply with the numbers of only the albums that should be kept.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: Verification.self,
                options: GenerationOptions(temperature: 0)
            )
            let keep = Set(response.content.keep)
            let verified = candidates.enumerated()
                .filter { keep.contains($0.offset) }
                .map(\.element)
            return verified
        } catch {
            return candidates
        }
    }
}

/// Structured output the model returns for a single batch.
@Generable
struct BatchMatches {
    @Guide(description: "The albums from the list that clearly match the user's request.")
    let matches: [Match]

    @Generable
    struct Match {
        @Guide(description: "The number of the matching album, exactly as shown in the list.")
        let number: Int

        @Guide(description: "How strongly it matches, from 1 (weak) to 5 (certain).")
        let relevance: Int

        @Guide(description: "A short, one-sentence reason this album clearly matches the request.")
        let reason: String
    }
}

/// Structured output for the verification pass: the numbers to keep.
@Generable
struct Verification {
    @Guide(description: "The numbers of the candidate albums that certainly satisfy the request and should be kept.")
    let keep: [Int]
}
