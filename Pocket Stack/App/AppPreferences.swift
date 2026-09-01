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
    var deckScale: Double { didSet { defaults.set(deckScale, forKey: "deck.scale") } }
    var edgeWidth: Double { didSet { defaults.set(edgeWidth, forKey: "deck.edgeWidth") } }
    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: "deck.openOnHover") } }
    var showOverFullScreen: Bool { didSet { defaults.set(showOverFullScreen, forKey: "deck.fullScreen") } }
    var displayTarget: String { didSet { defaults.set(displayTarget, forKey: "deck.display") } }
    var noteFontSize: Double { didSet { defaults.set(noteFontSize, forKey: "note.fontSize") } }
    var noteFontName: String { didSet { defaults.set(noteFontName, forKey: "note.fontName") } }
    var noteSizeIndex: Int { didSet { defaults.set(noteSizeIndex, forKey: "note.size") } }
    var markdownStyling: Bool { didSet { defaults.set(markdownStyling, forKey: "note.markdown") } }
    var speechProvider: SpeechProvider { didSet { defaults.set(speechProvider.rawValue, forKey: "speech.provider") } }
    var speechLocale: String { didSet { defaults.set(speechLocale, forKey: "speech.locale") } }
    var microphoneUID: String? { didSet { defaults.set(microphoneUID, forKey: "speech.microphone") } }

    private init() {
        edge = DeckEdge(rawValue: defaults.string(forKey: "deck.edge") ?? "") ?? .right
        style = DeckStyle(rawValue: defaults.string(forKey: "deck.style") ?? "") ?? .labelled
        deckScale = defaults.object(forKey: "deck.scale") as? Double ?? 1
        edgeWidth = defaults.object(forKey: "deck.edgeWidth") as? Double ?? 14
        openOnHover = defaults.object(forKey: "deck.openOnHover") as? Bool ?? false
        showOverFullScreen = defaults.object(forKey: "deck.fullScreen") as? Bool ?? false
        displayTarget = defaults.string(forKey: "deck.display") ?? "all"
        noteFontSize = defaults.object(forKey: "note.fontSize") as? Double ?? 14
        noteFontName = defaults.string(forKey: "note.fontName") ?? "Noteworthy-Light"
        noteSizeIndex = defaults.object(forKey: "note.size") as? Int ?? 1
        markdownStyling = defaults.object(forKey: "note.markdown") as? Bool ?? true
        speechProvider = SpeechProvider(rawValue: defaults.string(forKey: "speech.provider") ?? "") ?? .appleOnDevice
        speechLocale = defaults.string(forKey: "speech.locale") ?? Locale.current.identifier
        microphoneUID = defaults.string(forKey: "speech.microphone")
    }

    var noteSize: CGSize {
        let sizes = [CGSize(width: 400, height: 320), CGSize(width: 470, height: 390), CGSize(width: 560, height: 470), CGSize(width: 680, height: 560)]
        return sizes[min(max(noteSizeIndex, 0), sizes.count - 1)]
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Pocket Stack launch-at-login: %@", error.localizedDescription)
            }
        }
    }
}
