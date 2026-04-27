import Foundation

/// Transcribes audio files via WhisperKit. Holds the loaded model in
/// memory across calls; main-actor-isolated state.
@MainActor
public final class WhisperKitTranscriber: Transcriber {
    public static let defaultModelName = "openai_whisper-base"

    /// `nonisolated` because Swift 6 strict concurrency disallows calling a
    /// MainActor-isolated static func from a default-argument expression in a
    /// nonisolated context (the internal init's `modelStorage:` default).
    /// The body uses only Sendable Foundation APIs, so dropping isolation is safe.
    public nonisolated static func defaultModelStorage() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Diktador", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    private let driver: WhisperKitDriver
    private let modelName: String
    private let modelStorage: URL

    private var inFlightLoad: Task<Void, Error>?

    public private(set) var state: TranscriberState = .uninitialized

    /// Production initializer.
    public convenience init(modelName: String = defaultModelName) {
        self.init(
            driver: LiveWhisperKitDriver(),
            modelName: modelName,
            modelStorage: Self.defaultModelStorage()
        )
    }

    /// Test seam.
    internal init(
        driver: WhisperKitDriver,
        modelName: String = defaultModelName,
        modelStorage: URL = WhisperKitTranscriber.defaultModelStorage()
    ) {
        self.driver = driver
        self.modelName = modelName
        self.modelStorage = modelStorage
    }

    public func loadModel() async throws {
        if case .ready = state { return }
        if case .failed(let error) = state { throw error }
        if let task = inFlightLoad {
            try await task.value
            return
        }
        state = .loading
        // The task body handles state transitions and error mapping itself,
        // so concurrent waiters on `task.value` see identical throw semantics
        // (same .modelLoadFailed wrapping, same observed state after the throw).
        let task = Task<Void, Error> { @MainActor in
            do {
                try await self.driver.loadModel(name: self.modelName, modelStorage: self.modelStorage)
                self.state = .ready
            } catch {
                let mapped = TranscriberError.modelLoadFailed(message: String(describing: error))
                self.state = .failed(mapped)
                throw mapped
            }
        }
        inFlightLoad = task
        defer { inFlightLoad = nil }
        try await task.value
    }

    public func transcribe(audioFileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriberError.audioFileUnreadable(audioFileURL)
        }
        try await loadModel()
        if case .failed(let error) = state { throw error }

        state = .transcribing
        do {
            let raw = try await driver.transcribe(audioFileURL: audioFileURL)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            state = .ready
            if trimmed.isEmpty { throw TranscriberError.emptyTranscript }
            return trimmed
        } catch let error as TranscriberError {
            if case .emptyTranscript = error {
                // .ready state was already restored before throwing emptyTranscript.
                throw error
            }
            state = .ready
            throw error
        } catch {
            state = .ready
            throw TranscriberError.transcriptionFailed(message: String(describing: error))
        }
    }
}
