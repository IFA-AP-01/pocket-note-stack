import AVFoundation

final class AudioBufferConverter: @unchecked Sendable {
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
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            return status == .error ? nil : output
        }
    }
}

final class PCM16StreamEncoder: @unchecked Sendable {
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private lazy var converter = AudioBufferConverter(targetFormat: format)
    private let lock = NSLock()
    private var pending = Data()
    private let chunkBytes = 3_200

    func encode(_ buffer: AVAudioPCMBuffer) -> [Data] {
        guard let converted = converter.convert(buffer), let channel = converted.floatChannelData?[0] else { return [] }
        var data = Data(capacity: Int(converted.frameLength) * 2)
        for index in 0..<Int(converted.frameLength) {
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
