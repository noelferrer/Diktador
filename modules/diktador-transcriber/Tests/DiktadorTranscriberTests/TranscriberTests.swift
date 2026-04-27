import XCTest
@testable import DiktadorTranscriber

final class TranscriberTests: XCTestCase {
    func test_transcriberState_isEquatable() {
        XCTAssertEqual(TranscriberState.uninitialized, .uninitialized)
        XCTAssertEqual(TranscriberState.loading, .loading)
        XCTAssertEqual(TranscriberState.ready, .ready)
        XCTAssertEqual(TranscriberState.transcribing, .transcribing)
        XCTAssertEqual(
            TranscriberState.failed(.modelLoadFailed(message: "x")),
            TranscriberState.failed(.modelLoadFailed(message: "x"))
        )
        XCTAssertNotEqual(TranscriberState.ready, .loading)
    }

    func test_transcriberError_isEquatable() {
        XCTAssertEqual(
            TranscriberError.modelLoadFailed(message: "boom"),
            TranscriberError.modelLoadFailed(message: "boom")
        )
        XCTAssertEqual(
            TranscriberError.transcriptionFailed(message: "x"),
            TranscriberError.transcriptionFailed(message: "x")
        )
        XCTAssertEqual(
            TranscriberError.audioFileUnreadable(URL(fileURLWithPath: "/a")),
            TranscriberError.audioFileUnreadable(URL(fileURLWithPath: "/a"))
        )
        XCTAssertEqual(TranscriberError.emptyTranscript, .emptyTranscript)
    }
}
