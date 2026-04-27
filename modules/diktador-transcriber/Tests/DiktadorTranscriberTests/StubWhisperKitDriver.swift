import Foundation
@testable import DiktadorTranscriber

/// Test stub — records calls and returns canned results / errors.
final class StubWhisperKitDriver: WhisperKitDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var _loadModelCalls: [(name: String, modelStorage: URL)] = []
    private var _transcribeCalls: [URL] = []

    var loadModelCalls: [(name: String, modelStorage: URL)] {
        lock.lock(); defer { lock.unlock() }
        return _loadModelCalls
    }
    var transcribeCalls: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _transcribeCalls
    }

    /// Optional delay (in nanoseconds) before loadModel resumes.
    var loadModelDelay: UInt64 = 0
    /// Error to throw from loadModel; nil = succeed.
    var loadModelError: Error?
    /// String to return from transcribe; ignored if transcribeError is set.
    var transcribeResult: String = "stub transcript"
    /// Error to throw from transcribe; nil = return transcribeResult.
    var transcribeError: Error?

    func loadModel(name: String, modelStorage: URL) async throws {
        lock.lock(); _loadModelCalls.append((name: name, modelStorage: modelStorage)); lock.unlock()
        if loadModelDelay > 0 {
            try await Task.sleep(nanoseconds: loadModelDelay)
        }
        if let error = loadModelError { throw error }
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        lock.lock(); _transcribeCalls.append(audioFileURL); lock.unlock()
        if let error = transcribeError { throw error }
        return transcribeResult
    }
}
