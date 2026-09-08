import AppKit
import Foundation
import Observation
import ServiceManagement

enum DeckEdge: String, CaseIterable, Identifiable {
    case left, right, bottom
    var id: String { rawValue }
}

enum DeckStyle: String, CaseIterable, Identifiable {
    case labelled, compact
    var id: String { rawValue }
    var title: String { self == .labelled ? "Labelled tabs" : "Colour chips" }
}

@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()
    private let defaults = UserDefaults.standard

    var edge: DeckEdge { didSet { defaults.set(edge.rawValue, forKey: "deck.edge") } }
    var style: DeckStyle { didSet { defaults.set(style.rawValue, forKey: "deck.style") } }
    var edgeWidth: Double { didSet { defaults.set(edgeWidth, forKey: "deck.edgeWidth") } }
    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: "deck.openOnHover") } }
    var showOverFullScreen: Bool { didSet { defaults.set(showOverFullScreen, forKey: "deck.fullScreen") } }
    var displayTarget: String { didSet { defaults.set(displayTarget, forKey: "deck.display") } }
    var noteFontSize: Double { didSet { defaults.set(noteFontSize, forKey: "note.fontSize") } }
    var noteFontName: String { didSet { defaults.set(noteFontName, forKey: "note.fontName") } }
    var noteSizeIndex: Int { didSet { defaults.set(noteSizeIndex, forKey: "note.size") } }
    var speechProvider: SpeechProvider { didSet { defaults.set(speechProvider.rawValue, forKey: "speech.provider") } }
    var appleSpeechLocale: String { didSet { defaults.set(appleSpeechLocale, forKey: "speech.locale.apple") } }
    var geminiSpeechLocale: String { didSet { defaults.set(geminiSpeechLocale, forKey: "speech.locale.gemini") } }
    var openAISpeechLocale: String { didSet { defaults.set(openAISpeechLocale, forKey: "speech.locale.openai") } }
    var microphoneUID: String? { didSet { defaults.set(microphoneUID, forKey: "speech.microphone") } }
    var audioSource: AudioSource { didSet { defaults.set(audioSource.rawValue, forKey: "speech.audioSource") } }

    private init() {
        edge = DeckEdge(rawValue: defaults.string(forKey: "deck.edge") ?? "") ?? .right
        style = DeckStyle(rawValue: defaults.string(forKey: "deck.style") ?? "") ?? .labelled
        edgeWidth = defaults.object(forKey: "deck.edgeWidth") as? Double ?? 14
        openOnHover = defaults.object(forKey: "deck.openOnHover") as? Bool ?? false
        showOverFullScreen = defaults.object(forKey: "deck.fullScreen") as? Bool ?? false
        displayTarget = defaults.string(forKey: "deck.display") ?? "all"
        noteFontSize = defaults.object(forKey: "note.fontSize") as? Double ?? 14
        noteFontName = defaults.string(forKey: "note.fontName") ?? "Noteworthy-Light"
        noteSizeIndex = defaults.object(forKey: "note.size") as? Int ?? 1
        let savedSpeechProvider = SpeechProvider(rawValue: defaults.string(forKey: "speech.provider") ?? "") ?? .appleOnDevice
        if #available(macOS 26.0, *) {
            speechProvider = savedSpeechProvider
        } else {
            speechProvider = .geminiLive
        }
        let legacyLocale = defaults.string(forKey: "speech.locale")
        appleSpeechLocale = defaults.string(forKey: "speech.locale.apple")
            ?? (savedSpeechProvider == .appleOnDevice ? legacyLocale : nil)
            ?? Locale.current.identifier
        geminiSpeechLocale = defaults.string(forKey: "speech.locale.gemini")
            ?? (savedSpeechProvider == .geminiLive ? legacyLocale : nil)
            ?? "auto"
        openAISpeechLocale = defaults.string(forKey: "speech.locale.openai")
            ?? (savedSpeechProvider == .openAI ? Self.openAILanguageCode(from: legacyLocale) : nil)
            ?? "auto"
        microphoneUID = defaults.string(forKey: "speech.microphone")
        audioSource = AudioSource(rawValue: defaults.string(forKey: "speech.audioSource") ?? "") ?? .microphone
        if appleSpeechLocale.isEmpty || appleSpeechLocale == "auto" {
            appleSpeechLocale = Locale.current.identifier
        }
        if geminiSpeechLocale.isEmpty {
            geminiSpeechLocale = "auto"
        }
        if openAISpeechLocale.isEmpty {
            openAISpeechLocale = "auto"
        }
    }

    var speechLocale: String {
        get {
            switch speechProvider {
            case .appleOnDevice: appleSpeechLocale
            case .geminiLive: geminiSpeechLocale
            case .openAI: openAISpeechLocale
            }
        }
        set {
            switch speechProvider {
            case .appleOnDevice: appleSpeechLocale = newValue
            case .geminiLive: geminiSpeechLocale = newValue
            case .openAI: openAISpeechLocale = newValue
            }
        }
    }

    private static func openAILanguageCode(from localeIdentifier: String?) -> String? {
        guard let localeIdentifier,
              !localeIdentifier.isEmpty,
              localeIdentifier != "auto" else { return nil }
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        if normalized.lowercased().hasPrefix("zh-") {
            if normalized.localizedCaseInsensitiveContains("TW") || normalized.localizedCaseInsensitiveContains("Hant") {
                return "zh-tw"
            }
            if normalized.localizedCaseInsensitiveContains("HK") {
                return "zh-hk"
            }
            return "zh-cn"
        }
        return Locale(identifier: normalized).language.languageCode?.identifier.lowercased()
    }

    var noteSize: CGSize {
        let sizes = [CGSize(width: 400, height: 320), CGSize(width: 470, height: 390), CGSize(width: 560, height: 470), CGSize(width: 680, height: 560)]
        return sizes[min(max(noteSizeIndex, 0), sizes.count - 1)]
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
