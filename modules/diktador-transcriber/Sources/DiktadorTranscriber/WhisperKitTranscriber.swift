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
        if let task = inFlightLoad {
            try await task.value
            return
        }
        state = .loading
        let task = Task<Void, Error> { [self, modelName, modelStorage] in
            try await driver.loadModel(name: modelName, modelStorage: modelStorage)
        }
        inFlightLoad = task
        defer { inFlightLoad = nil }
        do {
            try await task.value
            state = .ready
        } catch {
            let mapped = TranscriberError.modelLoadFailed(message: String(describing: error))
            state = .failed(mapped)
            throw mapped
        }
    }

    public func transcribe(audioFileURL: URL) async throws -> String {
        // Stub for D3+. Initial body just to make the type compile.
        throw TranscriberError.transcriptionFailed(message: "not yet implemented")
    }
}
