import Foundation
import MusicKit

/// A single album that matched the user's natural-language query, along with
/// the model's confidence and a short human-readable rationale.
struct SearchResult: Identifiable, Hashable, Sendable {
    let album: LibraryAlbum
    /// Relevance from 1 (weak match) to 5 (strong match).
    let relevance: Int
    /// One-sentence explanation of why this album matches.
    let reason: String

    var id: MusicItemID { album.id }
}
