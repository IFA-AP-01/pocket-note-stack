import Foundation
import Speech

@available(macOS 26.0, *)
struct AppleDictationEngine: DictationEngine {
    func readiness(for request: DictationRequest) async -> DictationReadiness {
        let identifier = request.localeIdentifier ?? Locale.current.identifier
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: identifier)
        ) else {
            return .unavailable("The selected speaker language is not supported by Apple On-Device speech recognition.")
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            return .unavailable("Apple On-Device language model is not downloaded yet. Please download it in Settings.")
        }
        return .ready
    }

    func start(_ request: DictationRequest) async throws -> any DictationSession {
        try await AppleDictationSession.create(request: request)
    }

    static func modelStatus(localeIdentifier: String) async -> AssetInventory.Status {
        let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: localeIdentifier)
        )
        guard let locale else { return .unsupported }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        return await AssetInventory.status(forModules: [transcriber])
    }
}
