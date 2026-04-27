import AVFoundation
import Foundation

/// Internal seam over the AVAudioEngine surface used by `Recorder`. Real
/// implementation wires up an engine + input-node tap; tests substitute a stub
/// that records lifecycle calls and lets the test feed synthetic buffers.
internal protocol AudioEngineDriver: AnyObject {
    var inputFormat: AVAudioFormat { get }
    func installTap(
        bufferSize: AVAudioFrameCount,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws
    func removeTap()
    func start() throws
    func stop()
}

internal final class AVAudioEngineDriver: AudioEngineDriver {
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    var inputFormat: AVAudioFormat {
        engine.inputNode.inputFormat(forBus: 0)
    }

    func installTap(
        bufferSize: AVAudioFrameCount,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws {
        guard !tapInstalled else { return }
        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: engine.inputNode.inputFormat(forBus: 0)
        ) { buffer, _ in
            onBuffer(buffer)
        }
        tapInstalled = true
    }

    func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}
