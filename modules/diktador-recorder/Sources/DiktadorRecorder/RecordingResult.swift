import Foundation

/// The artifact produced by a successful `Recorder.stop` call.
public struct RecordingResult: Sendable, Equatable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let sampleCount: Int

    public init(fileURL: URL, duration: TimeInterval, sampleCount: Int) {
        self.fileURL = fileURL
        self.duration = duration
        self.sampleCount = sampleCount
    }
}
