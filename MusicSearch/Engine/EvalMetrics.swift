import Foundation

/// Retrieval-quality metrics for one evaluated query, computed from the ranked
/// list the engine returned versus a labeled judgment (expected and forbidden
/// album IDs). Pure math — no I/O — so changes to scoring or parsing can be
/// measured instead of eyeballed.
public struct EvalMetrics: Sendable {
    /// Fraction of retrieved albums that were expected.
    public let precision: Double
    /// Fraction of expected albums that were retrieved.
    public let recall: Double
    /// Harmonic mean of precision and recall.
    public let f1: Double
    /// Normalized discounted cumulative gain over the full ranked list, with
    /// binary relevance: 1.0 means every expected album was retrieved and
    /// ranked above every unexpected one.
    public let ndcg: Double
    /// How many explicitly forbidden albums were retrieved (should be 0).
    public let forbiddenHits: Int

    public init(precision: Double, recall: Double, f1: Double, ndcg: Double, forbiddenHits: Int) {
        self.precision = precision
        self.recall = recall
        self.f1 = f1
        self.ndcg = ndcg
        self.forbiddenHits = forbiddenHits
    }

    /// Scores a ranked retrieval against a judgment. `retrieved` must be in
    /// rank order (best first) — NDCG depends on it.
    public static func compute(
        retrieved: [String],
        expected: Set<String>,
        forbidden: Set<String> = []
    ) -> EvalMetrics {
        let hits = retrieved.filter { expected.contains($0) }.count

        let precision: Double
        if retrieved.isEmpty {
            precision = expected.isEmpty ? 1 : 0
        } else {
            precision = Double(hits) / Double(retrieved.count)
        }
        let recall = expected.isEmpty ? 1 : Double(hits) / Double(expected.count)
        let f1 = (precision + recall) == 0 ? 0 : 2 * precision * recall / (precision + recall)

        let ndcg: Double
        if expected.isEmpty {
            ndcg = 1
        } else {
            var dcg = 0.0
            for (index, id) in retrieved.enumerated() where expected.contains(id) {
                dcg += 1 / log2(Double(index) + 2)
            }
            var idcg = 0.0
            for index in 0 ..< expected.count {
                idcg += 1 / log2(Double(index) + 2)
            }
            ndcg = dcg / idcg
        }

        return EvalMetrics(
            precision: precision,
            recall: recall,
            f1: f1,
            ndcg: ndcg,
            forbiddenHits: retrieved.filter { forbidden.contains($0) }.count
        )
    }

    /// Macro-average across queries (forbidden hits are summed, not averaged).
    public static func aggregate(_ metrics: [EvalMetrics]) -> EvalMetrics {
        guard !metrics.isEmpty else {
            return EvalMetrics(precision: 0, recall: 0, f1: 0, ndcg: 0, forbiddenHits: 0)
        }
        let n = Double(metrics.count)
        return EvalMetrics(
            precision: metrics.map(\.precision).reduce(0, +) / n,
            recall: metrics.map(\.recall).reduce(0, +) / n,
            f1: metrics.map(\.f1).reduce(0, +) / n,
            ndcg: metrics.map(\.ndcg).reduce(0, +) / n,
            forbiddenHits: metrics.map(\.forbiddenHits).reduce(0, +)
        )
    }
}
