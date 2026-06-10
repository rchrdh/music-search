import Foundation

/// A precomputed embedding table: one vector per album and per known query,
/// loaded from the JSON that `scripts/generate-embeddings.py` writes.
///
/// The format is model-agnostic — any encoder that yields L2-normalized
/// vectors of one consistent dimension works, and nothing here depends on
/// which one produced them. The eval harness uses this to A/B an embedding
/// ranker against the metadata scorer. (In the app, query vectors would have
/// to come from an on-device encoder rather than a precomputed table; the
/// album side of the index could ship as-is.)
public struct EmbeddingIndex: Sendable {

    public let model: String
    /// Album ID → vector.
    public let albums: [String: [Double]]
    /// Normalized query text → vector.
    private let queries: [String: [Double]]

    private struct File: Decodable {
        var model: String
        var albums: [String: [Double]]
        var queries: [String: [Double]]
    }

    public init(model: String, albums: [String: [Double]], queries: [String: [Double]]) {
        self.model = model
        self.albums = albums
        self.queries = Dictionary(
            queries.map { (Self.normalize($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public init(contentsOf url: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        self.init(model: file.model, albums: file.albums, queries: file.queries)
    }

    /// The precomputed vector for a query, keyed case- and
    /// whitespace-insensitively so judgments files and command lines match.
    public func queryVector(for query: String) -> [Double]? {
        queries[Self.normalize(query)]
    }

    /// Cosine similarity. Vectors in the index are already L2-normalized, but
    /// this divides by the norms anyway so it is correct for any input; zero
    /// or mismatched-length vectors yield 0.
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / ((normA * normB).squareRoot())
    }

    /// Every album ranked by similarity to the query vector, descending; ties
    /// broken by ID so runs are deterministic.
    public func ranked(against queryVector: [Double]) -> [(id: String, similarity: Double)] {
        albums
            .map { (id: $0.key, similarity: Self.cosine(queryVector, $0.value)) }
            .sorted { $0.similarity != $1.similarity ? $0.similarity > $1.similarity : $0.id < $1.id }
    }

    private static func normalize(_ query: String) -> String {
        query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
