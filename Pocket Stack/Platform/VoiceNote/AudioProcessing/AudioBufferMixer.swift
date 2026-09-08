import AVFoundation

final class AudioBufferMixer: @unchecked Sendable {
    private let lock = NSLock()
    private var screenSamplesInt16: [Int16] = []
    private var screenSamplesFloat: [Float] = []
    private let targetFormat: AVAudioFormat
    private let maxBufferedSamples: Int
    private let isFloat: Bool

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
        self.maxBufferedSamples = Int(targetFormat.sampleRate)
        self.isFloat = targetFormat.commonFormat == .pcmFormatFloat32
    }

    func pushScreen(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            if isFloat, let channel = buffer.floatChannelData?[0] {
                screenSamplesFloat.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
                trim(&screenSamplesFloat)
            } else if let channel = buffer.int16ChannelData?[0] {
                screenSamplesInt16.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
                trim(&screenSamplesInt16)
            }
        }
    }

    func mixMicrophone(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        lock.withLock {
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0,
                  let mixed = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity) else {
                return buffer
            }
            mixed.frameLength = buffer.frameLength

            if isFloat {
                let available = min(frameCount, screenSamplesFloat.count)
                for channelIndex in 0..<Int(targetFormat.channelCount) {
                    guard let microphone = buffer.floatChannelData?[channelIndex],
                          let output = mixed.floatChannelData?[channelIndex] else { continue }
                    for index in 0..<available {
                        output[index] = max(-1, min(1, microphone[index] + screenSamplesFloat[index]))
                    }
                    for index in available..<frameCount { output[index] = microphone[index] }
                }
                screenSamplesFloat.removeFirst(available)
            } else {
                let available = min(frameCount, screenSamplesInt16.count)
                for channelIndex in 0..<Int(targetFormat.channelCount) {
                    guard let microphone = buffer.int16ChannelData?[channelIndex],
                          let output = mixed.int16ChannelData?[channelIndex] else { continue }
                    for index in 0..<available {
                        output[index] = Int16(clamping: Int32(microphone[index]) + Int32(screenSamplesInt16[index]))
                    }
                    for index in available..<frameCount { output[index] = microphone[index] }
                }
                screenSamplesInt16.removeFirst(available)
            }
            return mixed
        }
    }

    private func trim<Sample>(_ samples: inout [Sample]) {
        if samples.count > maxBufferedSamples {
            samples.removeFirst(samples.count - maxBufferedSamples)
        }
    }
}
