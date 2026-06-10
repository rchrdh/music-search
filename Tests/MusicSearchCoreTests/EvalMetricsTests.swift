import XCTest
@testable import MusicSearchCore

final class EvalMetricsTests: XCTestCase {

    func testPerfectRetrieval() {
        let m = EvalMetrics.compute(retrieved: ["a", "b"], expected: ["a", "b"])
        XCTAssertEqual(m.precision, 1)
        XCTAssertEqual(m.recall, 1)
        XCTAssertEqual(m.f1, 1)
        XCTAssertEqual(m.ndcg, 1)
        XCTAssertEqual(m.forbiddenHits, 0)
    }

    func testPartialRetrieval() {
        // One of two expected found, alongside one stray.
        let m = EvalMetrics.compute(retrieved: ["a", "c"], expected: ["a", "b"])
        XCTAssertEqual(m.precision, 0.5)
        XCTAssertEqual(m.recall, 0.5)
        XCTAssertEqual(m.f1, 0.5)
        // DCG = 1/log2(2) = 1; IDCG = 1/log2(2) + 1/log2(3) ≈ 1.6309
        XCTAssertEqual(m.ndcg, 1 / (1 + 1 / log2(3)), accuracy: 1e-9)
    }

    func testRankingAffectsNDCG() {
        let goodOrder = EvalMetrics.compute(retrieved: ["a", "x"], expected: ["a"])
        let badOrder = EvalMetrics.compute(retrieved: ["x", "a"], expected: ["a"])
        XCTAssertEqual(goodOrder.ndcg, 1)
        XCTAssertLessThan(badOrder.ndcg, goodOrder.ndcg)
        // Precision/recall ignore order.
        XCTAssertEqual(goodOrder.precision, badOrder.precision)
        XCTAssertEqual(goodOrder.recall, badOrder.recall)
    }

    func testForbiddenHitsAreCounted() {
        let m = EvalMetrics.compute(retrieved: ["a", "z"], expected: ["a"], forbidden: ["z"])
        XCTAssertEqual(m.forbiddenHits, 1)
    }

    func testEmptyRetrievalAgainstExpectations() {
        let m = EvalMetrics.compute(retrieved: [], expected: ["a"])
        XCTAssertEqual(m.precision, 0)
        XCTAssertEqual(m.recall, 0)
        XCTAssertEqual(m.f1, 0)
        XCTAssertEqual(m.ndcg, 0)
    }

    func testEmptyExpectationIsSatisfiedByEmptyRetrieval() {
        let m = EvalMetrics.compute(retrieved: [], expected: [])
        XCTAssertEqual(m.precision, 1)
        XCTAssertEqual(m.recall, 1)
        XCTAssertEqual(m.ndcg, 1)
    }

    func testAggregateAveragesAndSumsForbidden() {
        let a = EvalMetrics(precision: 1, recall: 0.5, f1: 2.0 / 3, ndcg: 1, forbiddenHits: 1)
        let b = EvalMetrics(precision: 0.5, recall: 1, f1: 2.0 / 3, ndcg: 0.5, forbiddenHits: 2)
        let agg = EvalMetrics.aggregate([a, b])
        XCTAssertEqual(agg.precision, 0.75)
        XCTAssertEqual(agg.recall, 0.75)
        XCTAssertEqual(agg.ndcg, 0.75)
        XCTAssertEqual(agg.forbiddenHits, 3)
    }
}
