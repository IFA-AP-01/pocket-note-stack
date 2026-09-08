import AVFoundation

enum AudioLevelMeter {
    static func normalizedRMS(of buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        let step = max(1, frameCount / 256)
        if let channel = buffer.floatChannelData?[0] {
            var sum: Float = 0
            var count = 0
            for index in stride(from: 0, to: frameCount, by: step) {
                sum += channel[index] * channel[index]
                count += 1
            }
            return min(1, max(0, sqrt(sum / Float(max(1, count))) * 4))
        }

        if let channel = buffer.int16ChannelData?[0] {
            var sum: Double = 0
            var count = 0
            for index in stride(from: 0, to: frameCount, by: step) {
                let sample = Double(channel[index]) / 32_768
                sum += sample * sample
                count += 1
            }
            return min(1, max(0, Float(sqrt(sum / Double(max(1, count)))) * 4))
        }

        return 0
    }
}
