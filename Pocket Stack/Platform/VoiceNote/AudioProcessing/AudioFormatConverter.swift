import AVFoundation

final class AudioFormatConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) { self.targetFormat = targetFormat }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.withLock { () -> AVAudioPCMBuffer? in
            if sourceFormat != input.format {
                sourceFormat = input.format
                converter = AVAudioConverter(from: input.format, to: targetFormat)
            }
            guard let converter else { return nil }
            let ratio = targetFormat.sampleRate / input.format.sampleRate
            let estimated = ceil(Double(input.frameLength) * ratio) + 8
            let capacity = AVAudioFrameCount(max(estimated, 1))
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            guard status != .error, output.frameLength > 0 else { return nil }
            return output
        }
    }
}

final class PCM16StreamEncoder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let chunkBytes: Int

    init(sampleRate: Double, chunkDuration: TimeInterval = 0.1) {
        self.chunkBytes = max(2, Int(sampleRate * chunkDuration) * MemoryLayout<Int16>.size)
    }

    func encode(_ buffer: AVAudioPCMBuffer) -> [Data] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        var data = Data(capacity: Int(buffer.frameLength) * 2)
        for index in 0..<Int(buffer.frameLength) {
            var sample = Int16(max(-1, min(1, channel[index])) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        return lock.withLock {
            pending.append(data)
            var chunks: [Data] = []
            while pending.count >= chunkBytes {
                chunks.append(Data(pending.prefix(chunkBytes)))
                pending.removeFirst(chunkBytes)
            }
            return chunks
        }
    }

    func flush() -> Data? {
        lock.withLock {
            guard !pending.isEmpty else { return nil }
            defer { pending.removeAll(keepingCapacity: true) }
            return pending
        }
    }
}
