import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class ScreenAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let downsampler = PCM16Downsampler()
    private let chunker: PCM16Chunker?
    private let onAudioChunk: (@Sendable (Data) -> Void)?
    private let onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private let onStatus: (@Sendable (String) -> Void)?
    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "pocket-stack.screen.audio")
    private let videoQueue = DispatchQueue(label: "pocket-stack.screen.video")
    nonisolated(unsafe) private var lastFormatStatusAt = Date.distantPast

    init(
        onAudioChunk: (@Sendable (Data) -> Void)? = nil,
        onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) {
        self.onAudioChunk = onAudioChunk
        self.onBuffer = onBuffer
        self.onStatus = onStatus
        if let onAudioChunk {
            self.chunker = PCM16Chunker(onChunk: onAudioChunk)
        } else {
            self.chunker = nil
        }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScreenAudioCaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 16
        configuration.height = 16
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        chunker?.reset()
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio,
              sampleBuffer.isValid,
              let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        var neededSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard status == noErr, neededSize > 0 else {
            return
        }

        var blockBuffer: CMBlockBuffer?
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: neededSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }

        let audioBufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: neededSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            return
        }

        let channels = max(1, Int(asbd.pointee.mChannelsPerFrame))
        let sampleRate = asbd.pointee.mSampleRate
        let formatFlags = asbd.pointee.mFormatFlags
        let bytesPerSample = max(1, Int(asbd.pointee.mBitsPerChannel / 8))
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        if let onBuffer, numSamples > 0 {
            if let format = AVAudioFormat(streamDescription: asbd),
               let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) {
                pcmBuffer.frameLength = AVAudioFrameCount(numSamples)
                let destBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
                let srcBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for (dest, src) in zip(destBuffers, srcBuffers) {
                    if let destData = dest.mData, let srcData = src.mData {
                        memcpy(destData, srcData, min(Int(dest.mDataByteSize), Int(src.mDataByteSize)))
                    }
                }
                onBuffer(pcmBuffer)
            } else if formatFlags & kAudioFormatFlagIsFloat != 0 {
                // Fallback: unpack samples and create standard non-interleaved AVAudioPCMBuffer
                let samples = readFloat32Samples(from: audioBufferList, channels: channels)
                if let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false),
                   let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) {
                    pcmBuffer.frameLength = AVAudioFrameCount(numSamples)
                    if let channelData = pcmBuffer.floatChannelData {
                        for ch in 0..<channels {
                            for frame in 0..<numSamples {
                                channelData[ch][frame] = samples[frame * channels + ch]
                            }
                        }
                    }
                    onBuffer(pcmBuffer)
                }
            } else {
                reportFormatStatusIfNeeded(flags: formatFlags, bits: asbd.pointee.mBitsPerChannel)
            }
        }

        if let chunker {
            if formatFlags & kAudioFormatFlagIsFloat != 0, bytesPerSample == MemoryLayout<Float>.size {
                let samples = readFloat32Samples(from: audioBufferList, channels: channels)
                let pcm = downsampler.convertInterleavedFloat32(samples, sourceSampleRate: sampleRate, channels: channels)
                chunker.append(pcm)
            } else if formatFlags & kAudioFormatFlagIsSignedInteger != 0, bytesPerSample == MemoryLayout<Int16>.size {
                let samples = readInt16Samples(from: audioBufferList)
                chunker.append(downsampler.convertInt16PCM(samples, sourceSampleRate: sampleRate, channels: channels))
            } else {
                reportFormatStatusIfNeeded(flags: formatFlags, bits: asbd.pointee.mBitsPerChannel)
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStatus?("Screen audio stopped: \(error.localizedDescription)")
    }

    private nonisolated func reportFormatStatusIfNeeded(flags: AudioFormatFlags, bits: UInt32) {
        let now = Date()
        guard now.timeIntervalSince(lastFormatStatusAt) >= 2 else { return }
        lastFormatStatusAt = now
        onStatus?("Unsupported screen audio format: flags \(flags), bits \(bits)")
    }

    private nonisolated func readFloat32Samples(from audioBufferList: UnsafeMutablePointer<AudioBufferList>, channels: Int) -> [Float] {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var samples: [Float] = []

        if buffers.count == 1,
           let data = buffers[0].mData {
            let count = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
            let pointer = data.bindMemory(to: Float.self, capacity: count)
            samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
            return samples
        }

        let frameCount = buffers.map { Int($0.mDataByteSize) / MemoryLayout<Float>.size }.min() ?? 0
        samples.reserveCapacity(frameCount * channels)
        for frame in 0..<frameCount {
            for buffer in buffers {
                guard let data = buffer.mData else {
                    samples.append(0)
                    continue
                }
                let pointer = data.bindMemory(to: Float.self, capacity: frameCount)
                samples.append(pointer[frame])
            }
        }
        return samples
    }

    private nonisolated func readInt16Samples(from audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> [Int16] {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var samples: [Int16] = []

        if buffers.count == 1,
           let data = buffers[0].mData {
            let count = Int(buffers[0].mDataByteSize) / MemoryLayout<Int16>.size
            let pointer = data.bindMemory(to: Int16.self, capacity: count)
            samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
            return samples
        }

        let frameCount = buffers.map { Int($0.mDataByteSize) / MemoryLayout<Int16>.size }.min() ?? 0
        samples.reserveCapacity(frameCount * buffers.count)
        for frame in 0..<frameCount {
            for buffer in buffers {
                guard let data = buffer.mData else {
                    samples.append(0)
                    continue
                }
                let pointer = data.bindMemory(to: Int16.self, capacity: frameCount)
                samples.append(pointer[frame])
            }
        }
        return samples
    }
}

enum ScreenAudioCaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display is available for screen audio capture"
        }
    }
}

// MARK: - Audio Processing Utilities

final class PCM16Chunker {
    private let lock = NSLock()
    nonisolated(unsafe) private var pending = Data()
    private let chunkSize = 3_200
    private let onChunk: @Sendable (Data) -> Void

    init(onChunk: @escaping @Sendable (Data) -> Void) {
        self.onChunk = onChunk
    }

    nonisolated func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        while pending.count >= chunkSize {
            let chunk = pending.prefix(chunkSize)
            onChunk(Data(chunk))
            pending.removeFirst(chunkSize)
        }
    }

    nonisolated func reset() {
        lock.lock()
        defer { lock.unlock() }
        pending.removeAll(keepingCapacity: true)
    }
}

final class PCM16Downsampler {
    private let targetSampleRate: Double = 16_000

    nonisolated func convert(buffer: AVAudioPCMBuffer) -> Data {
        guard let channels = buffer.floatChannelData else { return Data() }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return Data() }

        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sample: Float = 0
            for channel in 0..<channelCount {
                sample += channels[channel][frame]
            }
            mono[frame] = sample / Float(channelCount)
        }
        return convertMonoFloat(mono, sourceSampleRate: buffer.format.sampleRate)
    }

    nonisolated func convertInterleavedFloat32(_ samples: [Float], sourceSampleRate: Double, channels: Int) -> Data {
        guard channels > 0 else { return Data() }
        let frames = samples.count / channels
        guard frames > 0 else { return Data() }
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sample: Float = 0
            for channel in 0..<channels {
                sample += samples[frame * channels + channel]
            }
            mono[frame] = sample / Float(channels)
        }
        return convertMonoFloat(mono, sourceSampleRate: sourceSampleRate)
    }

    nonisolated func convertInt16PCM(_ samples: [Int16], sourceSampleRate: Double, channels: Int) -> Data {
        guard channels > 0 else { return Data() }
        let frames = samples.count / channels
        guard frames > 0 else { return Data() }
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sample: Float = 0
            for channel in 0..<channels {
                sample += Float(Int16(littleEndian: samples[frame * channels + channel])) / Float(Int16.max)
            }
            mono[frame] = sample / Float(channels)
        }
        return convertMonoFloat(mono, sourceSampleRate: sourceSampleRate)
    }

    private nonisolated func convertMonoFloat(_ samples: [Float], sourceSampleRate: Double) -> Data {
        guard !samples.isEmpty, sourceSampleRate > 0 else { return Data() }
        let ratio = targetSampleRate / sourceSampleRate
        let outputCount = max(1, Int(Double(samples.count) * ratio))
        var output = Data(capacity: outputCount * 2)

        for index in 0..<outputCount {
            let sourcePosition = Double(index) / ratio
            let lower = min(Int(sourcePosition), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lower))
            let sample = samples[lower] + (samples[upper] - samples[lower]) * fraction
            var intSample = Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &intSample) { output.append(contentsOf: $0) }
        }

        return output
    }
}
