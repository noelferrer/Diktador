import AVFoundation

/// Writes a `[Float]` accumulator to a WAV file at 16 kHz mono 16-bit PCM.
internal struct WAVWriter {
    func write(samples: [Float], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // 16-bit PCM mono at 16 kHz. AVAudioFile takes a settings dict for the
        // file format; the in-memory buffer stays Float32 and AVAudioFile
        // converts on write.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: SampleRateConverter.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            throw RecorderError.fileWriteFailed
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: SampleRateConverter.targetFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw RecorderError.fileWriteFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channelData.update(from: src.baseAddress!, count: samples.count)
            }
        }

        do {
            try audioFile.write(from: buffer)
        } catch {
            throw RecorderError.fileWriteFailed
        }
    }
}
