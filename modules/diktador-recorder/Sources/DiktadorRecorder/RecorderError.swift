import Foundation

public enum RecorderError: Error, Equatable {
    /// `start()` was called but Microphone permission is not granted.
    case microphonePermissionDenied
    /// `start()` was called while a recording is already in progress.
    case alreadyRecording
    /// `stop()` was called while no recording is in progress.
    case notRecording
    /// `AVAudioEngine` failed to start (no input device, hardware busy, etc.).
    case engineUnavailable
    /// `AVAudioConverter` setup or per-buffer conversion failed.
    case formatConversionFailed
    /// The recordings directory could not be created or the WAV file could not be written.
    case fileWriteFailed
}
