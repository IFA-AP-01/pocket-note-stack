import Foundation

enum DictationError: LocalizedError {
    case unsupportedLocale(String)
    case audioFormatUnavailable
    case appleOnDeviceUnavailable
    case missingAPIKey
    case invalidServerResponse
    case timedOut
    case screenCapturePermissionDenied
    case openAIUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale): "Apple on-device dictation does not support \(locale)."
        case .audioFormatUnavailable: "No compatible microphone format is available."
        case .appleOnDeviceUnavailable: "Apple on-device dictation requires macOS 26 or later."
        case .missingAPIKey: "Add a Gemini API key in Settings > Voice Note."
        case .invalidServerResponse: "Gemini returned an invalid response."
        case .timedOut: "The transcription service timed out."
        case .screenCapturePermissionDenied: "Screen Recording permission is required. Enable it in System Settings > Privacy & Security > Screen Recording."
        case .openAIUnavailable: "OpenAI dictation is coming soon. Please select Apple On-Device or Google Gemini."
        }
    }
}
