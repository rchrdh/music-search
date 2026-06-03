import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal Last.fm API client for the metadata we need: descriptive tags for an
/// album (or its artist), and a list of artists similar to a given one.
///
/// Last.fm's JSON is famously loosely typed (a tag list can be an array, a
/// single object, or an empty string), so responses are parsed defensively with
/// `JSONSerialization` rather than `Codable`.
public struct LastFMClient: Sendable {
    public let apiKey: String
    private let base = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Up to `limit` lowercased tags describing an album. Falls back to the
    /// artist's top tags when the album isn't found.
    public func tags(artist: String, album: String, limit: Int = 8) async -> [String] {
        let albumTags = await names(
            method: "album.getinfo",
            extra: ["artist": artist, "album": album],
            path: ["album", "tags", "tag"]
        )
        if !albumTags.isEmpty {
            return clean(albumTags, limit: limit)
        }
        let artistTags = await names(
            method: "artist.gettoptags",
            extra: ["artist": artist],
            path: ["toptags", "tag"]
        )
        return clean(artistTags, limit: limit)
    }

    /// Lowercased names of artists Last.fm considers similar to `artist`.
    public func similarArtists(to artist: String, limit: Int = 50) async -> [String] {
        let names = await names(
            method: "artist.getsimilar",
            extra: ["artist": artist, "limit": String(limit)],
            path: ["similarartists", "artist"]
        )
        return names.map { $0.lowercased() }
    }

    // MARK: - Request / parsing

    private func names(method: String, extra: [String: String], path: [String]) async -> [String] {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return [] }
        var items = [
            URLQueryItem(name: "method", value: method),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "autocorrect", value: "1"),
        ]
        items += extra.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        guard let url = components.url else { return [] }

        // Last.fm throttles bursts with HTTP 429 / `error: 29`. Without backoff a
        // throttled response looks identical to "no data" and silently drops the
        // album's tags — so retry a few times with exponential backoff before
        // giving up. A genuine empty (non-throttled) result returns immediately.
        for attempt in 0 ..< maxAttempts {
            guard let (data, response) = try? await URLSession.shared.data(from: url) else {
                await backoff(attempt)
                continue
            }
            if Self.isRateLimited(statusCode: (response as? HTTPURLResponse)?.statusCode, body: data) {
                await backoff(attempt)
                continue
            }
            return extractNames(from: data, path: path)
        }
        return []
    }

    private let maxAttempts = 5

    /// True when the response is a Last.fm rate-limit signal (HTTP 429 or the
    /// API's `error: 29`), as opposed to a normal — possibly empty — payload.
    static func isRateLimited(statusCode: Int?, body: Data) -> Bool {
        if statusCode == 429 { return true }
        if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           (root["error"] as? Int) == 29 {
            return true
        }
        return false
    }

    /// Exponential backoff: ~0.5s, 1s, 2s, 4s … with a little jitter so the five
    /// concurrent fetchers don't retry in lockstep.
    private func backoff(_ attempt: Int) async {
        let base = 0.5 * pow(2.0, Double(attempt))
        let seconds = base + Double.random(in: 0 ... 0.25)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }


    private func extractNames(from data: Data, path: [String], leaf: String = "name") -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var node: Any? = root
        for key in path {
            node = (node as? [String: Any])?[key]
        }
        if let array = node as? [[String: Any]] {
            return array.compactMap { $0[leaf] as? String }
        }
        if let single = node as? [String: Any], let name = single[leaf] as? String {
            return [name]
        }
        return []
    }

    private func clean(_ tags: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let lower = tag.lowercased().trimmingCharacters(in: .whitespaces)
            guard !lower.isEmpty, seen.insert(lower).inserted else { continue }
            result.append(lower)
            if result.count >= limit { break }
        }
        return result
    }
}
