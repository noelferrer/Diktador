import AVFoundation

/// Captures microphone audio between `start()` and `stop(completion:)` calls
/// and writes the result as a 16 kHz mono PCM WAV file.
public final class Recorder {
    private enum State {
        case idle
        case recording(samples: [Float], startedAt: Date)
        case finalizing
    }

    private let permissionProvider: MicrophonePermissionProvider
    private let engineDriver: AudioEngineDriver
    private let recordingsDirectory: URL
    private let converter = SampleRateConverter()
    private let writer = WAVWriter()

    private var state: State = .idle

    public convenience init() {
        self.init(
            permissionProvider: AVPermissionProvider(),
            engineDriver: AVAudioEngineDriver(),
            recordingsDirectory: Self.defaultRecordingsDirectory()
        )
    }

    internal init(
        permissionProvider: MicrophonePermissionProvider,
        engineDriver: AudioEngineDriver,
        recordingsDirectory: URL
    ) {
        self.permissionProvider = permissionProvider
        self.engineDriver = engineDriver
        self.recordingsDirectory = recordingsDirectory
    }

    deinit {
        if case .recording = state {
            engineDriver.removeTap()
            engineDriver.stop()
        }
    }

    public var microphonePermission: MicrophonePermissionStatus {
        permissionProvider.currentStatus()
    }

    public func requestMicrophonePermission(
        completion: @escaping (MicrophonePermissionStatus) -> Void
    ) {
        permissionProvider.requestAccess(completion: completion)
    }

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    public func start() throws {
        guard case .idle = state else { throw RecorderError.alreadyRecording }
        guard permissionProvider.currentStatus() == .granted else {
            throw RecorderError.microphonePermissionDenied
        }

        let samples: [Float] = []
        let startedAt = Date()
        do {
            try engineDriver.installTap(
                bufferSize: 4096,
                onBuffer: { [weak self] buffer in
                    self?.handleBuffer(buffer)
                }
            )
            try engineDriver.start()
        } catch {
            engineDriver.removeTap()
            engineDriver.stop()
            NSLog("[recorder] engine start failed: \(error)")
            throw RecorderError.engineUnavailable
        }
        state = .recording(samples: samples, startedAt: startedAt)
    }

    public func stop(completion: @escaping (Result<RecordingResult, Error>) -> Void) {
        guard case .recording(let samples, let startedAt) = state else {
            completion(.failure(RecorderError.notRecording))
            return
        }

        engineDriver.removeTap()
        engineDriver.stop()
        state = .finalizing

        let fileURL = nextFileURL()
        let duration = Date().timeIntervalSince(startedAt)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.writer.write(samples: samples, to: fileURL)
                let result = RecordingResult(
                    fileURL: fileURL,
                    duration: duration,
                    sampleCount: samples.count
                )
                DispatchQueue.main.async {
                    self.state = .idle
                    completion(.success(result))
                }
            } catch {
                NSLog("[recorder] file write failed: \(error)")
                DispatchQueue.main.async {
                    self.state = .idle
                    completion(.failure(error))
                }
            }
        }
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard case .recording(var samples, let startedAt) = state else { return }
        // Drop the state's reference to the array storage so `samples` holds
        // the only strong ref; this lets `converter.append` mutate in place
        // instead of paying COW (full reallocation + copy) on every callback.
        state = .finalizing
        defer { state = .recording(samples: samples, startedAt: startedAt) }
        do {
            _ = try converter.append(buffer, into: &samples)
        } catch {
            NSLog("[recorder] format conversion failed: \(error)")
        }
    }

    private func nextFileURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return recordingsDirectory.appendingPathComponent("\(stamp).wav")
    }

    private static func defaultRecordingsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Diktador", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }
}
