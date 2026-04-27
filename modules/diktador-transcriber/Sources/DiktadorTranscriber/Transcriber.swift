import Foundation

/// State of a transcriber's lifecycle.
public enum TranscriberState: Sendable, Equatable {
    case uninitialized
    case loading
    case ready
    case transcribing
    case failed(TranscriberError)
}

/// Errors a transcriber can throw.
public enum TranscriberError: Error, Sendable, Equatable {
    case modelLoadFailed(message: String)
    case transcriptionFailed(message: String)
    case audioFileUnreadable(URL)
    case emptyTranscript
}

/// Public surface a Diktador transcription backend exposes.
public protocol Transcriber: Sendable {
    @MainActor var state: TranscriberState { get }
    func loadModel() async throws
    func transcribe(audioFileURL: URL) async throws -> String
}
