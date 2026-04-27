import AVFoundation

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
        engine.inputNode.outputFormat(forBus: 0)
    }

    func installTap(
        bufferSize: AVAudioFrameCount,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws {
        guard !tapInstalled else { return }
        // Apple's input-node tap pattern uses outputFormat (what the node emits),
        // not inputFormat. Some hardware paths only deliver one tap callback when
        // installTap is given inputFormat.
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: format
        ) { buffer, _ in
            // The engine recycles its tap buffer for subsequent callbacks, so the
            // contents must be copied synchronously on the audio thread before
            // handing the data off to main; otherwise main only sees the most
            // recent buffer's data on every queued dispatch.
            guard let copy = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: buffer.frameCapacity
            ) else { return }
            copy.frameLength = buffer.frameLength
            let channels = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)
            if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                for ch in 0..<channels {
                    memcpy(dst[ch], src[ch], frameCount * MemoryLayout<Float>.size)
                }
            }
            DispatchQueue.main.async {
                onBuffer(copy)
            }
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
