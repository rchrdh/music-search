import Foundation
import FoundationModels

/// Turns a natural-language query into a structured `QueryIntent`. Uses the
/// on-device model for understanding (a single, fast call — the one thing it's
/// reliably good at), and falls back to a simple heuristic when the model isn't
/// available.
struct QueryParser: Sendable {

    func parse(_ query: String) async -> QueryIntent {
        if FoundationModelSearchService.isAvailable, let intent = await modelParse(query) {
            return normalize(intent)
        }
        return heuristicParse(query)
    }

    // MARK: - Model parsing

    private func modelParse(_ query: String) async -> QueryIntent? {
        let instructions = """
        You convert a user's music-search request into structured search terms. \
        Extract two things: (1) descriptive tags — genres, moods, styles, \
        languages, or qualities the user wants (e.g. "french", "new age", \
        "ambient", "instrumental"); and (2) reference artists explicitly named \
        in a similarity request such as "albums like Brian Eno". Use lowercase \
        tags. Do not invent reference artists that the user did not name.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Request: \"\(query)\"",
                generating: QueryIntent.self,
                options: GenerationOptions(temperature: 0)
            )
            return response.content
        } catch {
            return nil
        }
    }

    private func normalize(_ intent: QueryIntent) -> QueryIntent {
        QueryIntent(
            descriptiveTags: intent.descriptiveTags
                .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            referenceArtists: intent.referenceArtists
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    // MARK: - Heuristic fallback

    private func heuristicParse(_ query: String) -> QueryIntent {
        // Share the engine's parser so the app and the eval harness behave
        // identically when the on-device model isn't used.
        let parsed = HeuristicQueryParser().parse(query)
        return QueryIntent(
            descriptiveTags: parsed.descriptiveTags,
            referenceArtists: parsed.referenceArtists
        )
    }
}
