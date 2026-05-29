import Foundation
import FoundationModels

/// Structured interpretation of a natural-language query. The model (or a
/// heuristic fallback) turns "albums like Brian Eno" into reference artists,
/// and "music in French" / "new age" / "no vocals" into descriptive tags.
@Generable
struct QueryIntent {
    @Guide(description: "Descriptive tags the user is asking for — genres, moods, styles, languages, or qualities such as 'french', 'new age', 'ambient', or 'instrumental'. Lowercase. Empty if the request is purely about similarity to an artist.")
    var descriptiveTags: [String]

    @Guide(description: "Artists explicitly named as a reference, e.g. for 'albums like Brian Eno' this is ['Brian Eno']. Empty if no artist is referenced.")
    var referenceArtists: [String]
}
