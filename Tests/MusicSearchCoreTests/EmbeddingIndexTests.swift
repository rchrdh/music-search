import XCTest
@testable import MusicSearchCore

final class EmbeddingIndexTests: XCTestCase {

    func testCosineIdenticalVectorsIsOne() {
        XCTAssertEqual(EmbeddingIndex.cosine([1, 2, 3], [1, 2, 3]), 1.0, accuracy: 1e-9)
    }

    func testCosineOrthogonalVectorsIsZero() {
        XCTAssertEqual(EmbeddingIndex.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-9)
    }

    func testCosineOppositeVectorsIsMinusOne() {
        XCTAssertEqual(EmbeddingIndex.cosine([1, 0], [-1, 0]), -1.0, accuracy: 1e-9)
    }

    func testCosineIgnoresMagnitude() {
        XCTAssertEqual(EmbeddingIndex.cosine([1, 1], [10, 10]), 1.0, accuracy: 1e-9)
    }

    func testCosineDegenerateInputsAreZero() {
        XCTAssertEqual(EmbeddingIndex.cosine([], []), 0.0)
        XCTAssertEqual(EmbeddingIndex.cosine([1, 2], [1, 2, 3]), 0.0)
        XCTAssertEqual(EmbeddingIndex.cosine([0, 0], [1, 2]), 0.0)
    }

    func testRankedOrdersBySimilarityDescending() {
        let index = EmbeddingIndex(
            model: "test",
            albums: [
                "far": [0, 1],
                "near": [1, 0.1],
                "exact": [1, 0],
            ],
            queries: [:]
        )
        let ranked = index.ranked(against: [1, 0])
        XCTAssertEqual(ranked.map(\.id), ["exact", "near", "far"])
        XCTAssertEqual(ranked[0].similarity, 1.0, accuracy: 1e-9)
    }

    func testRankedBreaksTiesByID() {
        let index = EmbeddingIndex(
            model: "test",
            albums: ["b": [1, 0], "a": [1, 0], "c": [1, 0]],
            queries: [:]
        )
        XCTAssertEqual(index.ranked(against: [1, 0]).map(\.id), ["a", "b", "c"])
    }

    func testQueryVectorLookupIsCaseAndWhitespaceInsensitive() {
        let index = EmbeddingIndex(
            model: "test",
            albums: [:],
            queries: ["Jazz albums": [1, 0]]
        )
        XCTAssertNotNil(index.queryVector(for: "  jazz albums "))
        XCTAssertNil(index.queryVector(for: "blues albums"))
    }

    func testDecodesGeneratorFormat() throws {
        let json = """
        {"model": "spacy/en_core_web_md",
         "albums": {"1": [0.5, 0.5]},
         "queries": {"Jazz albums": [1.0, 0.0]}}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("embeddings-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let index = try EmbeddingIndex(contentsOf: url)
        XCTAssertEqual(index.model, "spacy/en_core_web_md")
        XCTAssertEqual(index.albums["1"], [0.5, 0.5])
        XCTAssertNotNil(index.queryVector(for: "jazz albums"))
    }
}
