import Foundation

/// Internal seam that hides the WhisperKit dependency from the
/// transcriber's state machine. Real impl: `LiveWhisperKitDriver`.
internal protocol WhisperKitDriver: Sendable {
    func loadModel(name: String, modelStorage: URL) async throws
    func transcribe(audioFileURL: URL) async throws -> String
}

/// Temporary placeholder so the production initializer compiles.
/// Replaced with the real WhisperKit-backed implementation in Phase E.
internal final class LiveWhisperKitDriver: WhisperKitDriver, @unchecked Sendable {
    func loadModel(name: String, modelStorage: URL) async throws {
        throw TranscriberError.modelLoadFailed(message: "LiveWhisperKitDriver not yet implemented")
    }
    func transcribe(audioFileURL: URL) async throws -> String {
        throw TranscriberError.transcriptionFailed(message: "LiveWhisperKitDriver not yet implemented")
    }
}
