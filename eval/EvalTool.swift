import Foundation
import MusicSearchCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Command-line harness for refining search quality off-device.
///
/// Two modes:
///
/// **Single query** — run one query and inspect the ranked results:
///
///     LASTFM_API_KEY=... swift run musicsearch-eval "Music in French" \
///         --albums eval/sample-albums.json
///
/// **Judgments** — run a labeled suite and report precision/recall/F1/NDCG per
/// query and in aggregate, so scoring/parsing changes are measured instead of
/// eyeballed. Runs fully offline when the album file carries baked `tags`,
/// `language`, and the judgments file carries `similarArtists`:
///
///     swift run musicsearch-eval --judgments eval/judgments.json
///
/// Flags:
///   --judgments <path>  run the labeled suite at <path>
///   --albums <path>     JSON array of albums (default: sample set, or the
///                       `albums` path named inside the judgments file)
///   --limit <n>         only process the first n albums
///   --language          also fetch MusicBrainz language for candidates that
///                       lack a baked one (slow: ~1 req/sec)
///   --verbose           also print albums that did NOT match, with their tags
///
/// LASTFM_API_KEY is only required when something must actually be fetched —
/// albums without baked tags, or reference artists without provided similars.
@main
struct EvalTool {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())

        let judgmentsPath = takeValue("--judgments", from: &args)
        let albumsOverride = takeValue("--albums", from: &args)
        let limit = takeValue("--limit", from: &args).flatMap { Int($0) }
        let useLanguage = takeFlag("--language", from: &args)
        let verbose = takeFlag("--verbose", from: &args)
        let query = args.first(where: { !$0.hasPrefix("--") }) ?? ""

        let apiKey = ProcessInfo.processInfo.environment["LASTFM_API_KEY"]
        let lastFM = apiKey.flatMap { $0.isEmpty ? nil : LastFMClient(apiKey: $0) }

        if let judgmentsPath {
            await runJudgments(
                path: judgmentsPath,
                albumsOverride: albumsOverride,
                limit: limit,
                lastFM: lastFM
            )
            return
        }

        guard !query.isEmpty else {
            print(usage)
            return
        }
        await runSingleQuery(
            query: query,
            albumsPath: albumsOverride ?? "eval/sample-albums.json",
            limit: limit,
            useLanguage: useLanguage,
            verbose: verbose,
            lastFM: lastFM
        )
    }

    // MARK: - Judgments mode

    private struct JudgmentsFile: Decodable {
        var albums: String?
        var similarArtists: [String: [String]]?
        var cases: [Case]

        struct Case: Decodable {
            var query: String
            var expected: [String]
            var forbidden: [String]?
        }
    }

    private static func runJudgments(
        path: String,
        albumsOverride: String?,
        limit: Int?,
        lastFM: LastFMClient?
    ) async {
        guard
            let data = FileManager.default.contents(atPath: path),
            let judgments = try? JSONDecoder().decode(JudgmentsFile.self, from: data)
        else {
            print("error: could not load judgments from \(path)")
            return
        }
        let albumsPath = albumsOverride ?? judgments.albums ?? "eval/sample-albums.json"
        guard var albums = loadAlbums(at: albumsPath) else { return }
        if let limit { albums = Array(albums.prefix(limit)) }

        guard let tagsByID = await resolveTags(for: albums, using: lastFM) else { return }
        let vocabulary = Set(tagsByID.values.joined())
        let languageByID = Dictionary(
            uniqueKeysWithValues: albums.compactMap { album in
                album.language.map { (album.id, $0) }
            }
        )
        let providedSimilar = (judgments.similarArtists ?? [:]).reduce(into: [String: [String]]()) {
            $0[$1.key.lowercased()] = $1.value.map { $0.lowercased() }
        }
        let titleByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, "\($0.title) — \($0.artist)") })

        print("Judgments: \(path) (\(judgments.cases.count) cases) — albums: \(albumsPath) (\(albums.count))\n")

        var allMetrics: [EvalMetrics] = []
        for testCase in judgments.cases {
            let parsed = HeuristicQueryParser().parse(testCase.query)
            let referenceArtists = Set(parsed.referenceArtists.map { $0.lowercased() })
            guard let similar = await resolveSimilar(
                for: parsed.referenceArtists, provided: providedSimilar, using: lastFM
            ) else { return }

            let ranked = rankedMatches(
                albums: albums,
                parsed: parsed,
                vocabulary: vocabulary,
                tagsByID: tagsByID,
                languageByID: languageByID,
                similar: similar,
                referenceArtists: referenceArtists
            )
            let retrievedIDs = ranked.map(\.album.id)
            let expected = Set(testCase.expected)
            let forbidden = Set(testCase.forbidden ?? [])
            let metrics = EvalMetrics.compute(
                retrieved: retrievedIDs, expected: expected, forbidden: forbidden
            )
            allMetrics.append(metrics)

            print("\"\(testCase.query)\"")
            print("  \(format(metrics))  (retrieved \(retrievedIDs.count), expected \(expected.count))")
            let missed = testCase.expected.filter { !retrievedIDs.contains($0) }
            let strays = retrievedIDs.filter { !expected.contains($0) }
            printAlbumList("missed", ids: missed, titles: titleByID, forbidden: [])
            printAlbumList("strays", ids: strays, titles: titleByID, forbidden: forbidden)
            print("")
        }

        let aggregate = EvalMetrics.aggregate(allMetrics)
        print("=== aggregate (\(allMetrics.count) cases) ===")
        print("  \(format(aggregate))")
    }

    private static func format(_ m: EvalMetrics) -> String {
        String(
            format: "precision %.2f  recall %.2f  f1 %.2f  ndcg %.2f  forbidden hits %d",
            m.precision, m.recall, m.f1, m.ndcg, m.forbiddenHits
        )
    }

    private static func printAlbumList(
        _ label: String,
        ids: [String],
        titles: [String: String],
        forbidden: Set<String>,
        cap: Int = 8
    ) {
        guard !ids.isEmpty else { return }
        for id in ids.prefix(cap) {
            let marker = forbidden.contains(id) ? "  ✗ FORBIDDEN" : ""
            print("  \(label): \(titles[id] ?? id)\(marker)")
        }
        if ids.count > cap {
            print("  \(label): … +\(ids.count - cap) more")
        }
    }

    // MARK: - Single-query mode

    private static func runSingleQuery(
        query: String,
        albumsPath: String,
        limit: Int?,
        useLanguage: Bool,
        verbose: Bool,
        lastFM: LastFMClient?
    ) async {
        guard var albums = loadAlbums(at: albumsPath) else { return }
        if let limit { albums = Array(albums.prefix(limit)) }

        let musicBrainz = MusicBrainzClient()
        let parsed = HeuristicQueryParser().parse(query)
        let targetLanguages = SearchScorer.targetLanguageCodes(from: parsed.descriptiveTags)
        let referenceArtists = Set(parsed.referenceArtists.map { $0.lowercased() })

        guard let similar = await resolveSimilar(
            for: parsed.referenceArtists, provided: [:], using: lastFM
        ) else { return }
        guard let tagsByID = await resolveTags(for: albums, using: lastFM) else { return }

        // Ground the raw query words into the library's actual tag vocabulary
        // (the same step the app performs), so scoring is exact from here on.
        let vocabulary = Set(tagsByID.values.joined())
        let groundedTags = TagVocabulary.ground(parsed.descriptiveTags, in: vocabulary)

        print("Query: \"\(query)\"")
        print("  raw tags: \(parsed.descriptiveTags)")
        print("  grounded tags: \(groundedTags)")
        print("  reference artists: \(parsed.referenceArtists)")
        if !targetLanguages.isEmpty { print("  target languages: \(targetLanguages.sorted())") }
        print("Albums: \(albums.count)\n")

        // Language, only when needed and requested (serialized for MusicBrainz).
        // Candidate narrowing: language is the expensive signal (~1/sec), so
        // resolve it only for albums that already pass a cheap pre-filter — a
        // tag or similar-artist match — rather than the whole library. Albums
        // with a baked language never need a lookup.
        var languageByID = Dictionary(
            uniqueKeysWithValues: albums.compactMap { album in
                album.language.map { (album.id, $0) }
            }
        )
        if useLanguage && !targetLanguages.isEmpty {
            let candidates = albums.filter { album in
                languageByID[album.id] == nil && SearchScorer.hasNonLanguageSignal(
                    artist: album.artist,
                    albumTags: tagsByID[album.id] ?? [],
                    wantedTags: groundedTags,
                    similarArtists: similar,
                    referenceArtists: referenceArtists,
                    tagMatching: .exact
                )
            }
            print("Resolving language for \(candidates.count) candidate(s) of \(albums.count) via MusicBrainz (~1/sec)…\n")
            for album in candidates {
                languageByID[album.id] = await musicBrainz.language(artist: album.artist, album: album.title) ?? ""
                try? await Task.sleep(for: .seconds(1.1))
            }
        }

        let ranked = rankedMatches(
            albums: albums,
            parsed: parsed,
            vocabulary: vocabulary,
            tagsByID: tagsByID,
            languageByID: languageByID,
            similar: similar,
            referenceArtists: referenceArtists
        )

        print("=== \(ranked.count) match(es) ===")
        for (album, score) in ranked {
            let language = languageByID[album.id].flatMap { $0.isEmpty ? nil : $0 }
            print("[\(score.value)] \(album.title) — \(album.artist)")
            print("     \(score.reason)")
            print("     tags: \((tagsByID[album.id] ?? []).joined(separator: ", "))\(language.map { " | lang: \($0)" } ?? "")")
        }

        if verbose {
            let matchedIDs = Set(ranked.map(\.album.id))
            let misses = albums.filter { !matchedIDs.contains($0.id) }
            if !misses.isEmpty {
                print("\n=== \(misses.count) non-match(es) ===")
                for album in misses {
                    print("- \(album.title) — \(album.artist)")
                    print("     tags: \((tagsByID[album.id] ?? []).joined(separator: ", "))")
                }
            }
        }
    }

    // MARK: - Shared engine plumbing

    /// Grounds the parsed query into the vocabulary, scores every album with
    /// exact tag matching, and returns matches ranked by score (ties keep
    /// album order, so runs are deterministic).
    private static func rankedMatches(
        albums: [AlbumInput],
        parsed: ParsedQuery,
        vocabulary: Set<String>,
        tagsByID: [String: [String]],
        languageByID: [String: String],
        similar: Set<String>,
        referenceArtists: Set<String>
    ) -> [(album: AlbumInput, score: SearchScorer.Score)] {
        let targetLanguages = SearchScorer.targetLanguageCodes(from: parsed.descriptiveTags)
        let groundedTags = TagVocabulary.ground(parsed.descriptiveTags, in: vocabulary)

        var matches: [(album: AlbumInput, score: SearchScorer.Score, index: Int)] = []
        for (index, album) in albums.enumerated() {
            if let score = SearchScorer.score(
                artist: album.artist,
                albumTags: tagsByID[album.id] ?? [],
                albumLanguage: languageByID[album.id],
                wantedTags: groundedTags,
                targetLanguages: targetLanguages,
                similarArtists: similar,
                referenceArtists: referenceArtists,
                tagMatching: .exact
            ) {
                matches.append((album, score, index))
            }
        }
        matches.sort {
            $0.score.value != $1.score.value ? $0.score.value > $1.score.value : $0.index < $1.index
        }
        return matches.map { ($0.album, $0.score) }
    }

    private static func loadAlbums(at path: String) -> [AlbumInput]? {
        guard
            let data = FileManager.default.contents(atPath: path),
            let albums = try? JSONDecoder().decode([AlbumInput].self, from: data)
        else {
            print("error: could not load albums from \(path)")
            return nil
        }
        return albums
    }

    /// Tags for every album: baked ones as-is, the rest fetched from Last.fm
    /// with bounded concurrency. Fails (with a message) if a fetch is needed
    /// but no API key was provided.
    private static func resolveTags(
        for albums: [AlbumInput],
        using lastFM: LastFMClient?
    ) async -> [String: [String]]? {
        var result: [String: [String]] = [:]
        var pending: [AlbumInput] = []
        for album in albums {
            if let tags = album.tags {
                result[album.id] = tags
            } else {
                pending.append(album)
            }
        }
        guard !pending.isEmpty else { return result }
        guard let lastFM else {
            print("error: \(pending.count) album(s) have no baked tags — set LASTFM_API_KEY to fetch them.")
            return nil
        }
        let fetched = await fetchTags(for: pending, using: lastFM)
        result.merge(fetched) { _, new in new }
        return result
    }

    /// The similar-artist set for "like X" requests: provided lists when
    /// available (offline judgments), Last.fm otherwise.
    private static func resolveSimilar(
        for referenceArtists: [String],
        provided: [String: [String]],
        using lastFM: LastFMClient?
    ) async -> Set<String>? {
        var similar = Set<String>()
        for artist in referenceArtists {
            if let list = provided[artist.lowercased()] {
                similar.formUnion(list)
            } else if let lastFM {
                similar.formUnion(await lastFM.similarArtists(to: artist))
            } else {
                print("error: no similar-artist list for \"\(artist)\" — add it to the judgments file or set LASTFM_API_KEY.")
                return nil
            }
        }
        return similar
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
    usage: swift run musicsearch-eval "<query>" [options]
           swift run musicsearch-eval --judgments eval/judgments.json [options]

    options:
      --judgments <path>  run a labeled suite and report precision/recall/F1/NDCG
      --albums <path>     JSON array of {id,title,artist,genres[,tags,language]}
                          (default: eval/sample-albums.json, or the judgments file's)
      --limit <n>         only process the first n albums
      --language          fetch MusicBrainz language for candidates lacking a baked
                          one (slow: ~1 req/sec)
      --verbose           also list albums that did not match

    LASTFM_API_KEY is required only when tags or similar artists must be fetched.
    """
}
