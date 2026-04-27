import XCTest
import AVFoundation
@testable import DiktadorRecorder

final class RecorderTests: XCTestCase {
    func test_microphonePermission_reflectsProviderStatus() {
        let perms = StubPermissionProvider()
        perms.statusToReturn = .granted
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )
        XCTAssertEqual(recorder.microphonePermission, .granted)

        perms.statusToReturn = .denied
        XCTAssertEqual(recorder.microphonePermission, .denied)
    }

    func test_requestMicrophonePermission_callsProviderAndReturnsResult() {
        let perms = StubPermissionProvider()
        perms.requestResultToReturn = .granted
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        let exp = expectation(description: "completion")
        var observed: MicrophonePermissionStatus?
        recorder.requestMicrophonePermission { status in
            observed = status
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(observed, .granted)
        XCTAssertEqual(perms.requestCallCount, 1)
    }

    func test_start_throwsWhenPermissionDenied() {
        let perms = StubPermissionProvider()
        perms.statusToReturn = .denied
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )
        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? RecorderError, .microphonePermissionDenied)
        }
        XCTAssertFalse(recorder.isRecording)
    }

    func test_start_installsTapAndStartsEngine() throws {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        try recorder.start()

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(driver.calls, [
            .installTap(bufferSize: 4096),
            .start,
        ])
    }

    func test_start_throws_alreadyRecording_onSecondCall() throws {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: Self.tempRecordingsDirectory()
        )
        try recorder.start()

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? RecorderError, .alreadyRecording)
        }
    }

    func test_stop_returnsNotRecording_whenIdle() {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        let exp = expectation(description: "completion")
        var observed: Result<RecordingResult, Error>?
        recorder.stop { result in
            observed = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        if case .failure(let error) = observed {
            XCTAssertEqual(error as? RecorderError, .notRecording)
        } else {
            XCTFail("expected .failure(.notRecording), got \(String(describing: observed))")
        }
    }

    func test_stopAfterStart_writesWAVAndReturnsResult() throws {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        let dir = Self.tempRecordingsDirectory()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: dir
        )

        try recorder.start()
        // Feed three native-rate buffers (~85 ms each at 48 kHz).
        driver.feedZeroBuffer(frameCount: 4096)
        driver.feedZeroBuffer(frameCount: 4096)
        driver.feedZeroBuffer(frameCount: 4096)

        let exp = expectation(description: "completion")
        var observed: Result<RecordingResult, Error>?
        recorder.stop { result in
            observed = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        guard case .success(let result) = observed else {
            XCTFail("expected .success, got \(String(describing: observed))")
            return
        }
        XCTAssertGreaterThan(result.sampleCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(result.fileURL.pathExtension, "wav")
        XCTAssertFalse(recorder.isRecording)

        // Driver lifecycle calls in expected order: installTap, start, removeTap, stop.
        XCTAssertEqual(driver.calls, [
            .installTap(bufferSize: 4096),
            .start,
            .removeTap,
            .stop,
        ])

        try? FileManager.default.removeItem(at: dir)
    }

    func test_start_engineFailure_throwsEngineUnavailable() {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        struct DummyError: Error {}
        driver.startError = DummyError()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? RecorderError, .engineUnavailable)
        }
        XCTAssertFalse(recorder.isRecording)
        // Tap was installed then removed during the unwind.
        XCTAssertEqual(driver.calls, [
            .installTap(bufferSize: 4096),
            .start,
            .removeTap,
            .stop,
        ])
    }

    func test_stopAfterStart_failsFileWrite_whenDirectoryIsUnwritable() throws {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        // Point at a path under /dev/null which can never be written to.
        let unwritableDir = URL(fileURLWithPath: "/dev/null/Diktador-recordings")
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: unwritableDir
        )

        try recorder.start()
        driver.feedZeroBuffer(frameCount: 4096)

        let exp = expectation(description: "completion")
        var observed: Result<RecordingResult, Error>?
        recorder.stop { result in
            observed = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        guard case .failure(let error) = observed else {
            XCTFail("expected .failure, got \(String(describing: observed))")
            return
        }
        XCTAssertEqual(error as? RecorderError, .fileWriteFailed)
        // Recorder should be back to idle so a subsequent start() can succeed.
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: - Helpers

    private static func tempRecordingsDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiktadorRecorderTests-\(UUID().uuidString)")
        return dir
    }
}

private final class StubPermissionProvider: MicrophonePermissionProvider, @unchecked Sendable {
    var statusToReturn: MicrophonePermissionStatus = .undetermined
    var requestResultToReturn: MicrophonePermissionStatus = .granted
    private(set) var requestCallCount = 0

    func currentStatus() -> MicrophonePermissionStatus { statusToReturn }

    func requestAccess(completion: @escaping (MicrophonePermissionStatus) -> Void) {
        requestCallCount += 1
        let result = requestResultToReturn
        DispatchQueue.main.async { completion(result) }
    }
}

private final class StubAudioEngineDriver: AudioEngineDriver, @unchecked Sendable {
    enum Call: Equatable {
        case installTap(bufferSize: AVAudioFrameCount)
        case removeTap
        case start
        case stop
    }

    private(set) var calls: [Call] = []
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    var startError: Error?
    var fakeInputFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!

    var inputFormat: AVAudioFormat { fakeInputFormat }

    func installTap(
        bufferSize: AVAudioFrameCount,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws {
        calls.append(.installTap(bufferSize: bufferSize))
        self.onBuffer = onBuffer
    }

    func removeTap() {
        calls.append(.removeTap)
        onBuffer = nil
    }

    func start() throws {
        calls.append(.start)
        if let startError = startError { throw startError }
    }

    func stop() {
        calls.append(.stop)
    }

    /// Test helper: synthesize a buffer of `frameCount` zero samples in the
    /// fake input format and feed it through the installed tap.
    func feedZeroBuffer(frameCount: AVAudioFrameCount) {
        guard let onBuffer = onBuffer else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: fakeInputFormat,
            frameCapacity: frameCount
        ) else { return }
        buffer.frameLength = frameCount
        onBuffer(buffer)
    }
}
