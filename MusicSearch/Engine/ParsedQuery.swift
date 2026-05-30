import Foundation

/// A query reduced to the signals the engine matches on: descriptive tags
/// (genres, moods, styles, languages, qualities) and any referenced artists
/// from a "like X" request.
public struct ParsedQuery: Codable, Sendable, Equatable {
    public var descriptiveTags: [String]
    public var referenceArtists: [String]

    public init(descriptiveTags: [String], referenceArtists: [String]) {
        self.descriptiveTags = descriptiveTags
        self.referenceArtists = referenceArtists
    }
}
