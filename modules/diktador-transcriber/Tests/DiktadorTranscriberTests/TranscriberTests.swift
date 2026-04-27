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

    @MainActor
    func test_loadModel_happyPath_transitionsToReady() async throws {
        let driver = StubWhisperKitDriver()
        let modelStorage = Self.tempModelStorage()
        let transcriber = WhisperKitTranscriber(
            driver: driver,
            modelName: "openai_whisper-base",
            modelStorage: modelStorage
        )
        XCTAssertEqual(transcriber.state, .uninitialized)

        try await transcriber.loadModel()

        XCTAssertEqual(transcriber.state, .ready)
        XCTAssertEqual(driver.loadModelCalls.count, 1)
        XCTAssertEqual(driver.loadModelCalls.first?.name, "openai_whisper-base")
        XCTAssertEqual(driver.loadModelCalls.first?.modelStorage, modelStorage)
    }

    @MainActor
    func test_loadModel_failure_transitionsToFailed_andRethrows() async throws {
        struct DriverFailure: Error { let detail: String }
        let driver = StubWhisperKitDriver()
        driver.loadModelError = DriverFailure(detail: "no network")
        let transcriber = WhisperKitTranscriber(driver: driver)

        do {
            try await transcriber.loadModel()
            XCTFail("expected loadModel to throw")
        } catch let error as TranscriberError {
            if case .modelLoadFailed(let message) = error {
                XCTAssertTrue(message.contains("no network"), "got: \(message)")
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }

        if case .failed(let inner) = transcriber.state {
            if case .modelLoadFailed = inner { /* ok */ } else { XCTFail() }
        } else {
            XCTFail("expected .failed state, got \(transcriber.state)")
        }
    }

    @MainActor
    func test_loadModel_idempotent_secondCallIsNoOp() async throws {
        let driver = StubWhisperKitDriver()
        let transcriber = WhisperKitTranscriber(driver: driver)
        try await transcriber.loadModel()
        try await transcriber.loadModel()
        XCTAssertEqual(driver.loadModelCalls.count, 1, "loadModel must not re-invoke driver once .ready")
        XCTAssertEqual(transcriber.state, .ready)
    }

    static func tempModelStorage() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "diktador-test-models-\(UUID().uuidString)"
        )
        return url
    }
}
