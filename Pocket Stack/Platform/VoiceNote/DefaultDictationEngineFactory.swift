import Foundation

struct DefaultDictationEngineFactory: DictationEngineFactory {
    func makeEngine(for provider: SpeechProvider) -> any DictationEngine {
        switch provider {
        case .appleOnDevice:
            if #available(macOS 26.0, *) {
                return AppleDictationEngine()
            }
            return UnavailableAppleDictationEngine()
        case .geminiLive:
            return GeminiLiveEngine()
        case .openAI:
            return OpenAIRealtimeEngine()
        }
    }
}

private struct UnavailableAppleDictationEngine: DictationEngine {
    func readiness(for request: DictationRequest) async -> DictationReadiness {
        .unavailable("Apple On-Device speech recognition requires macOS 26 or later.")
    }

    func start(_ request: DictationRequest) async throws -> any DictationSession {
        throw DictationError.appleOnDeviceUnavailable
    }
}
