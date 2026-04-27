import Foundation
import WhisperKit

/// Internal seam that hides the WhisperKit dependency from the
/// transcriber's state machine. Real impl: `LiveWhisperKitDriver`.
internal protocol WhisperKitDriver: Sendable {
    func loadModel(name: String, modelStorage: URL) async throws
    func transcribe(audioFileURL: URL) async throws -> String
}

/// Real WhisperKit-backed driver. Loads `openai_whisper-base` (or whatever
/// `WhisperKitTranscriber` was configured with) into a held `WhisperKit`
/// pipeline and routes `transcribe(audioFileURL:)` to it.
internal final class LiveWhisperKitDriver: WhisperKitDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var pipeline: WhisperKit?

    func loadModel(name: String, modelStorage: URL) async throws {
        try FileManager.default.createDirectory(
            at: modelStorage,
            withIntermediateDirectories: true
        )
        let config = WhisperKitConfig(
            model: name,
            downloadBase: modelStorage,
            modelRepo: "argmaxinc/whisperkit-coreml",
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        )
        let pipeline = try await WhisperKit(config)
        lock.lock(); self.pipeline = pipeline; lock.unlock()
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        lock.lock()
        let pipeline = self.pipeline
        lock.unlock()
        guard let pipeline else {
            throw TranscriberError.transcriptionFailed(message: "pipeline not loaded")
        }
        let results = try await pipeline.transcribe(audioPath: audioFileURL.path)
        return results.map(\.text).joined(separator: " ")
    }
}
