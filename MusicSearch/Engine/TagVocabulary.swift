import Foundation

/// The library's tag vocabulary: the distinct Last.fm tags that actually occur
/// across the user's enriched albums. Query words are *grounded* into this
/// vocabulary once, up front, so the scorer can match tags exactly instead of
/// fuzzily — the query side absorbs all the fuzziness, in one place.
public enum TagVocabulary {

    /// The most frequent distinct tags across a set of per-album tag lists, for
    /// prompting a model with the vocabulary it may choose from. Ordered by
    /// frequency (ties alphabetical) so truncation keeps the best-known tags.
    public static func topTags(in tagLists: some Sequence<[String]>, limit: Int = 200) -> [String] {
        var counts: [String: Int] = [:]
        for tags in tagLists {
            for tag in tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    /// Specificity weight (0...1) for every tag in the corpus, IDF-style:
    /// log(N/df) / log(N) — 1.0 for a tag on a single album, decaying
    /// smoothly to 0 as the tag approaches ubiquity. This is what lets
    /// "tuareg" (5 albums, ~0.8) outrank "blues" (200 albums, ~0.4) when
    /// both match: rare tags carry information, ubiquitous ones barely do.
    /// Deliberately knee-free: any cutoff ("full weight under 5%") makes
    /// genuinely common tags indistinguishable from genuinely rare ones the
    /// moment the library is large.
    public static func specificity(in tagLists: some Sequence<[String]>) -> [String: Double] {
        var documentFrequency: [String: Int] = [:]
        var albumCount = 0
        for tags in tagLists {
            albumCount += 1
            for tag in Set(tags) {
                documentFrequency[tag, default: 0] += 1
            }
        }
        guard albumCount > 1 else { return documentFrequency.mapValues { _ in 1.0 } }
        let scale = log(Double(albumCount))
        return documentFrequency.mapValues { df in
            log(Double(albumCount) / Double(df)) / scale
        }
    }

    /// Maps raw query words onto the vocabulary tags they should match: every
    /// vocabulary tag that substring-overlaps a raw tag in either direction, so
    /// "french" grounds to ["french", "french pop"], and the split bigram
    /// "new" + "age" grounds (deduplicated) to ["new age"]. Raw words with no
    /// counterpart in the library are dropped — they could never match an
    /// album anyway. Output order is deterministic.
    public static func ground(_ rawTags: [String], in vocabulary: Set<String>) -> [String] {
        groundedGroups(rawTags, in: vocabulary).flatMap { $0 }
    }

    /// Like `ground`, but keeps the vocabulary tags grouped by the raw query
    /// word they came from: "desert blues" → [["desert blues"], ["blues",
    /// "chicago blues", …]]. The scorer counts each group once (at its
    /// best-matching tag), because an album tagged with six variants of
    /// "blues" matched one concept, not six. A tag that grounds from two raw
    /// words (the "new" + "age" bigram) lands only in the first group.
    public static func groundedGroups(_ rawTags: [String], in vocabulary: Set<String>) -> [[String]] {
        let sortedVocabulary = vocabulary.sorted()
        var seen = Set<String>()
        var groups: [[String]] = []
        for raw in rawTags {
            var group: [String] = []
            for tag in sortedVocabulary where matches(raw: raw, tag: tag) {
                if seen.insert(tag).inserted {
                    group.append(tag)
                }
            }
            if !group.isEmpty {
                groups.append(group)
            }
        }
        return groups
    }

    /// Real libraries contain junk one- and two-character Last.fm tags ("t",
    /// "uk") that substring-match almost any query word — so containment only
    /// counts when the contained side is at least 3 characters. Exact equality
    /// always matches, which is what keeps legitimately short tags reachable
    /// (query "uk" still grounds to tag "uk").
    private static func matches(raw: String, tag: String) -> Bool {
        if tag == raw { return true }
        if raw.count >= 3, tag.contains(raw) { return true }
        if tag.count >= 3, raw.contains(tag) { return true }
        return false
    }
}
