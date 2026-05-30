import Foundation
import MusicSearchCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Command-line harness for refining search quality off-device.
///
///   LASTFM_API_KEY=... swift run musicsearch-eval "Music in French" \
///       --albums eval/sample-albums.json
///
/// Flags:
///   --albums <path>   JSON array of albums (defaults to the sample set)
///   --limit <n>       only process the first n albums (handy with --language)
///   --language        also fetch MusicBrainz language (slow: ~1 req/sec)
///   --verbose         also print albums that did NOT match, with their tags
@main
struct EvalTool {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())

        let albumsPath = takeValue("--albums", from: &args) ?? "eval/sample-albums.json"
        let limit = takeValue("--limit", from: &args).flatMap { Int($0) }
        let useLanguage = takeFlag("--language", from: &args)
        let verbose = takeFlag("--verbose", from: &args)
        let query = args.first(where: { !$0.hasPrefix("--") }) ?? ""

        guard !query.isEmpty else {
            print(usage)
            return
        }
        guard let apiKey = ProcessInfo.processInfo.environment["LASTFM_API_KEY"], !apiKey.isEmpty else {
            print("error: set LASTFM_API_KEY in the environment.")
            return
        }
        guard
            let data = FileManager.default.contents(atPath: albumsPath),
            var albums = try? JSONDecoder().decode([AlbumInput].self, from: data)
        else {
            print("error: could not load albums from \(albumsPath)")
            return
        }
        if let limit { albums = Array(albums.prefix(limit)) }

        let lastFM = LastFMClient(apiKey: apiKey)
        let musicBrainz = MusicBrainzClient()

        let parsed = HeuristicQueryParser().parse(query)
        let targetLanguages = SearchScorer.targetLanguageCodes(from: parsed.descriptiveTags)

        print("Query: \"\(query)\"")
        print("  tags: \(parsed.descriptiveTags)")
        print("  reference artists: \(parsed.referenceArtists)")
        if !targetLanguages.isEmpty { print("  target languages: \(targetLanguages.sorted())") }
        print("Albums: \(albums.count)\n")

        // Similar artists for "like X" requests.
        var similar = Set<String>()
        for artist in parsed.referenceArtists {
            similar.insert(artist.lowercased())
            similar.formUnion(await lastFM.similarArtists(to: artist))
        }

        // Tags for every album (concurrently).
        let tagsByID = await fetchTags(for: albums, using: lastFM)

        // Language, only when needed and requested (serialized for MusicBrainz).
        var languageByID: [String: String] = [:]
        if useLanguage && !targetLanguages.isEmpty {
            print("Fetching languages from MusicBrainz (~1/sec)…\n")
            for album in albums {
                languageByID[album.id] = await musicBrainz.language(artist: album.artist, album: album.title) ?? ""
                try? await Task.sleep(for: .seconds(1.1))
            }
        }

        // Score and rank.
        var matches: [(album: AlbumInput, score: SearchScorer.Score)] = []
        var misses: [AlbumInput] = []
        for album in albums {
            let score = SearchScorer.score(
                artist: album.artist,
                albumTags: tagsByID[album.id] ?? [],
                albumLanguage: languageByID[album.id],
                wantedTags: parsed.descriptiveTags,
                targetLanguages: targetLanguages,
                similarArtists: similar
            )
            if let score {
                matches.append((album, score))
            } else {
                misses.append(album)
            }
        }
        matches.sort { $0.score.value > $1.score.value }

        print("=== \(matches.count) match(es) ===")
        for (album, score) in matches {
            let language = languageByID[album.id].flatMap { $0.isEmpty ? nil : $0 }
            print("[\(score.value)] \(album.title) — \(album.artist)")
            print("     \(score.reason)")
            print("     tags: \((tagsByID[album.id] ?? []).joined(separator: ", "))\(language.map { " | lang: \($0)" } ?? "")")
        }

        if verbose && !misses.isEmpty {
            print("\n=== \(misses.count) non-match(es) ===")
            for album in misses {
                print("- \(album.title) — \(album.artist)")
                print("     tags: \((tagsByID[album.id] ?? []).joined(separator: ", "))")
            }
        }
    }

    /// Fetches tags for all albums with bounded concurrency.
    private static func fetchTags(for albums: [AlbumInput], using client: LastFMClient) async -> [String: [String]] {
        await withTaskGroup(of: (String, [String]).self) { group in
            let maxConcurrent = 5
            var next = 0
            for _ in 0 ..< Swift.min(maxConcurrent, albums.count) {
                let album = albums[next]; next += 1
                group.addTask { (album.id, await client.tags(artist: album.artist, album: album.title)) }
            }
            var result: [String: [String]] = [:]
            for await (id, tags) in group {
                result[id] = tags
                if next < albums.count {
                    let album = albums[next]; next += 1
                    group.addTask { (album.id, await client.tags(artist: album.artist, album: album.title)) }
                }
            }
            return result
        }
    }

    // MARK: - Tiny arg helpers

    private static func takeValue(_ flag: String, from args: inout [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let value = args[i + 1]
        args.removeSubrange(i ... (i + 1))
        return value
    }

    private static func takeFlag(_ flag: String, from args: inout [String]) -> Bool {
        guard let i = args.firstIndex(of: flag) else { return false }
        args.remove(at: i)
        return true
    }

    private static let usage = """
    usage: LASTFM_API_KEY=<key> swift run musicsearch-eval "<query>" [options]

    options:
      --albums <path>   JSON array of {id,title,artist,genres} (default: eval/sample-albums.json)
      --limit <n>       only process the first n albums
      --language        also fetch MusicBrainz language (slow: ~1 req/sec)
      --verbose         also list albums that did not match
    """
}
