import Foundation

enum SpeechProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleOnDevice
    case geminiLive
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice: "Apple On-Device"
        case .geminiLive: "Google Gemini"
        case .openAI: "OpenAI"
        }
    }
}

enum AudioSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case microphone
    case screen
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .screen: "System Audio"
        case .both: "Both"
        }
    }
}

struct DictationRequest: Sendable {
    let localeIdentifier: String?
    let deviceUID: String?
    let audioSource: AudioSource
}

struct DictationReadiness: Sendable {
    let isReady: Bool
    let reason: String

    static let ready = DictationReadiness(isReady: true, reason: "")

    static func unavailable(_ reason: String) -> DictationReadiness {
        DictationReadiness(isReady: false, reason: reason)
    }
}

enum TranscriptEvent: Equatable, Sendable {
    case interim(String)
    case promoteInterim
    case final(String)
}

enum DictationState: Equatable, Sendable {
    case idle
    case preparing
    case listening
    case finalizing
    case failed(String)
}
