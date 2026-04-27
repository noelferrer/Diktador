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
