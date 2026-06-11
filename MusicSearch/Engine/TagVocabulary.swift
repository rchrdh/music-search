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

    /// Maps raw query words onto the vocabulary tags they should match: every
    /// vocabulary tag that substring-overlaps a raw tag in either direction, so
    /// "french" grounds to ["french", "french pop"], and the split bigram
    /// "new" + "age" grounds (deduplicated) to ["new age"]. Raw words with no
    /// counterpart in the library are dropped — they could never match an
    /// album anyway. Output order is deterministic.
    public static func ground(_ rawTags: [String], in vocabulary: Set<String>) -> [String] {
        let sortedVocabulary = vocabulary.sorted()
        var seen = Set<String>()
        var grounded: [String] = []
        for raw in rawTags {
            for tag in sortedVocabulary where matches(raw: raw, tag: tag) {
                if seen.insert(tag).inserted {
                    grounded.append(tag)
                }
            }
        }
        return grounded
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
