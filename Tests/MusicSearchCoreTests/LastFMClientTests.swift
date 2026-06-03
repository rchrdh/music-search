import XCTest
@testable import MusicSearchCore

final class LastFMClientTests: XCTestCase {

    func testHTTP429IsRateLimited() {
        XCTAssertTrue(LastFMClient.isRateLimited(statusCode: 429, body: Data()))
    }

    func testErrorCode29BodyIsRateLimited() {
        let body = #"{"error":29,"message":"Rate Limit Exceeded"}"#.data(using: .utf8)!
        XCTAssertTrue(LastFMClient.isRateLimited(statusCode: 200, body: body))
    }

    func testNormalEmptyResponseIsNotRateLimited() {
        let body = #"{"toptags":{"tag":[]}}"#.data(using: .utf8)!
        XCTAssertFalse(LastFMClient.isRateLimited(statusCode: 200, body: body))
    }

    func testOtherApiErrorIsNotTreatedAsRateLimit() {
        // error 6 = "no artist found" — a real empty result, must not retry.
        let body = #"{"error":6,"message":"The artist you supplied could not be found"}"#.data(using: .utf8)!
        XCTAssertFalse(LastFMClient.isRateLimited(statusCode: 200, body: body))
    }
}
