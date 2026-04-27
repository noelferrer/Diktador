import AVFoundation

/// Lazily converts captured buffers from the input device's native format to
/// 16 kHz mono `Float32`. Initialized on the first buffer (when the source
/// format is known); reused thereafter.
internal final class SampleRateConverter {
    static let targetSampleRate: Double = 16_000

    static let targetFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?

    /// Converts `buffer` to 16 kHz mono Float32 and appends the resulting
    /// samples to `accumulator`. Returns the number of frames appended.
    /// Throws `RecorderError.formatConversionFailed` on setup or convert failure.
    func append(_ buffer: AVAudioPCMBuffer, into accumulator: inout [Float]) throws -> AVAudioFrameCount {
        if converter == nil {
            guard let c = AVAudioConverter(from: buffer.format, to: Self.targetFormat) else {
                throw RecorderError.formatConversionFailed
            }
            converter = c
        }
        guard let converter = converter else {
            throw RecorderError.formatConversionFailed
        }

        // Estimate output capacity: ratio = target / source rate; +256 for safety
        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: estimatedFrames
        ) else {
            throw RecorderError.formatConversionFailed
        }

        var consumed = false
        var error: NSError?
        // .noDataNow (not .endOfStream): we've fed the single tap buffer for
        // this conversion call and have nothing more *right now*; the converter
        // must keep its internal resampler state alive for the next tap buffer.
        // Signaling .endOfStream after the first buffer would terminate the
        // stream and silently produce zero output on every subsequent call.
        let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            throw RecorderError.formatConversionFailed
        }

        let frames = Int(outBuffer.frameLength)
        if frames > 0, let channelData = outBuffer.floatChannelData?[0] {
            accumulator.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
        }
        return outBuffer.frameLength
    }
}
