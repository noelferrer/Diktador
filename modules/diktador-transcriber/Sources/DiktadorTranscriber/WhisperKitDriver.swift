import Foundation

/// Internal seam that hides the WhisperKit dependency from the
/// transcriber's state machine. Real impl: `LiveWhisperKitDriver`.
internal protocol WhisperKitDriver: Sendable {
    func loadModel(name: String, modelStorage: URL) async throws
    func transcribe(audioFileURL: URL) async throws -> String
}
