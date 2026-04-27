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

    @MainActor
    func test_loadModel_concurrent_callsCoalesceToSingleDriverCall() async throws {
        let driver = StubWhisperKitDriver()
        driver.loadModelDelay = 50_000_000  // 50 ms — long enough that both Tasks join the in-flight one
        let transcriber = WhisperKitTranscriber(driver: driver)

        async let a: Void = transcriber.loadModel()
        async let b: Void = transcriber.loadModel()
        _ = try await (a, b)

        XCTAssertEqual(driver.loadModelCalls.count, 1)
        XCTAssertEqual(transcriber.state, .ready)
    }

    @MainActor
    func test_transcribe_happyPath_returnsDriverResult_andStateReturnsToReady() async throws {
        let driver = StubWhisperKitDriver()
        driver.transcribeResult = "hello world"
        let transcriber = WhisperKitTranscriber(driver: driver)
        try await transcriber.loadModel()

        let url = Self.tempAudioFile()
        let text = try await transcriber.transcribe(audioFileURL: url)

        XCTAssertEqual(text, "hello world")
        XCTAssertEqual(driver.transcribeCalls, [url])
        XCTAssertEqual(transcriber.state, .ready)
    }

    @MainActor
    func test_transcribe_emptyResult_throwsEmptyTranscript_andStaysReady() async throws {
        let driver = StubWhisperKitDriver()
        driver.transcribeResult = ""
        let transcriber = WhisperKitTranscriber(driver: driver)
        try await transcriber.loadModel()

        do {
            _ = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
            XCTFail("expected emptyTranscript")
        } catch TranscriberError.emptyTranscript {
            // expected
        }
        XCTAssertEqual(transcriber.state, .ready)
    }

    @MainActor
    func test_transcribe_whitespaceOnlyResult_throwsEmptyTranscript() async throws {
        let driver = StubWhisperKitDriver()
        driver.transcribeResult = "   \n\t  "
        let transcriber = WhisperKitTranscriber(driver: driver)
        try await transcriber.loadModel()

        do {
            _ = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
            XCTFail("expected emptyTranscript")
        } catch TranscriberError.emptyTranscript { /* expected */ }
        XCTAssertEqual(transcriber.state, .ready)
    }

    static func tempModelStorage() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "diktador-test-models-\(UUID().uuidString)"
        )
        return url
    }

    static func tempAudioFile() -> URL {
        // Real bytes aren't required — the stub driver doesn't read the file.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "diktador-test-\(UUID().uuidString).wav"
        )
        let header = Data(repeating: 0, count: 44)  // minimal nonzero file
        try? header.write(to: url)
        return url
    }
}
