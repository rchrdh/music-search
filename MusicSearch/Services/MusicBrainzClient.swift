import Foundation

/// Looks up a release's primary language from MusicBrainz, which records an
/// explicit language per release (ISO 639-3, e.g. "fra", "spa", "eng"). This is
/// far more reliable for "music in French" than tags or a model's guess.
///
/// MusicBrainz asks anonymous clients to send a descriptive User-Agent and to
/// stay under one request per second — the enrichment service serializes these
/// calls to respect that.
struct MusicBrainzClient: Sendable {
    private let userAgent = "MusicSearch/1.0 ( https://github.com/rchrdh/music-search )"

    /// The release language as an ISO 639-3 code, or nil if not found.
    func language(artist: String, album: String) async -> String? {
        guard var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/") else {
            return nil
        }
        let query = "artist:\"\(artist)\" AND release:\"\(album)\""
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard
            let data = try? await URLSession.shared.data(for: request).0,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let releases = root["releases"] as? [[String: Any]],
            let first = releases.first,
            let textRepresentation = first["text-representation"] as? [String: Any],
            let language = textRepresentation["language"] as? String
        else {
            return nil
        }
        return language.lowercased()
    }
}
