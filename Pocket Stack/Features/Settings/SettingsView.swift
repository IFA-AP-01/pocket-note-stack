import AppKit
import Observation
import Speech
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case dictation
    case sync
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .dictation: "Voice Note"
        case .sync: "Sync"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .dictation: "waveform"
        case .sync: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var preferences: AppPreferences
    let environment: AppEnvironment
    @AppStorage("settings.selectedPane") private var selectedSection = SettingsSection.general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Settings") {
                    ForEach(SettingsSection.allCases) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsView(preferences: preferences)
                case .shortcuts:
                    ShortcutsSettingsView()
                case .dictation:
                    DictationSettingsView(preferences: preferences)
                case .sync:
                    SyncSettingsView()
                case .about:
                    AboutSettingsView(updateCoordinator: environment.updateCoordinator)
                }
            }
            .navigationTitle(selectedSection.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 520, idealHeight: 580)
        .onChange(of: preferences.edge) { _, _ in refreshDeck() }
        .onChange(of: preferences.edgeWidth) { _, _ in refreshDeck() }
        .onChange(of: preferences.noteSizeIndex) { _, _ in refreshDeck() }
        .onChange(of: preferences.showOverFullScreen) { _, _ in refreshDeck() }
        .onChange(of: preferences.displayTarget) { _, _ in refreshDeck() }
    }

    private func refreshDeck() {
        environment.deckCoordinator.refreshAll()
    }
}

private struct GeneralSettingsView: View {
    @Bindable var preferences: AppPreferences
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    private let fonts = ["", "Noteworthy-Light", "AvenirNext-Regular", "Georgia", "Menlo-Regular"]

    var body: some View {
        Form {
            Section("Deck") {
                Picker("Screen edge", selection: $preferences.edge) {
                    Text("Left").tag(DeckEdge.left)
                    Text("Right").tag(DeckEdge.right)
                    Text("Bottom").tag(DeckEdge.bottom)
                }
                .pickerStyle(.segmented)

                Picker("Deck style", selection: $preferences.style) {
                    ForEach(DeckStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Displays", selection: $preferences.displayTarget) {
                    Text("All displays").tag("all")
                    Text("Main display").tag("main")
                }

                LabeledContent("Edge activation width") {
                    HStack {
                        Slider(value: $preferences.edgeWidth, in: 8...44, step: 2)
                            .frame(minWidth: 180)
                        Text("\(Int(preferences.edgeWidth)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Toggle("Open note when hovering a tab", isOn: $preferences.openOnHover)
                Toggle("Show over full-screen apps", isOn: $preferences.showOverFullScreen)
            }

            Section("Notes") {
                Picker("Note font", selection: $preferences.noteFontName) {
                    ForEach(fonts, id: \.self) { font in
                        Text(font.isEmpty ? "System" : font).tag(font)
                    }
                }

                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $preferences.noteFontSize, in: 10...30, step: 0.5)
                            .frame(minWidth: 180)
                        Text(preferences.noteFontSize.formatted(.number.precision(.fractionLength(0...1))) + " pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                Picker("Note size", selection: $preferences.noteSizeIndex) {
                    Text("Small").tag(0)
                    Text("Medium").tag(1)
                    Text("Large").tag(2)
                    Text("Huge").tag(3)
                }
                .pickerStyle(.segmented)
            }

            Section("Startup") {
                Toggle("Launch Pocket Stack at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: updateLaunchAtLogin
                ))
            }
        }
        .formStyle(.grouped)
        .task {
            launchAtLogin = await preferences.checkLaunchAtLogin()
        }
        .alert("Unable to update Login Items", isPresented: Binding(
            get: { launchAtLoginError != nil },
            set: { if !$0 { launchAtLoginError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchAtLoginError ?? "Unknown error")
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        let previousValue = launchAtLogin
        launchAtLogin = enabled
        Task {
            do {
                try await preferences.setLaunchAtLoginAsync(enabled)
                launchAtLogin = await preferences.checkLaunchAtLogin()
            } catch {
                launchAtLogin = previousValue
                launchAtLoginError = error.localizedDescription
            }
        }
    }
}

private struct ShortcutsSettingsView: View {
    private let shortcuts = [
        ("New note", "⌥⌘N"), ("All notes", "⌥⌘A"), ("Archive", "⌥⌘L"),
        ("Close / stop dictation", "Esc"), ("Find", "⌘F"), ("Toggle task", "⌘T"),
        ("Pin", "⌘P"), ("Cycle colour", "⌘."), ("Delete", "⌘⌫"),
    ]

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                ForEach(shortcuts, id: \.0) { name, keys in
                    LabeledContent(name) {
                        Text(keys)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Text("Global shortcuts use the Carbon hot-key API and do not require Accessibility permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

enum APIKeyStatusState {
    case notConfigured
    case configured
    case working

    var title: String {
        switch self {
        case .notConfigured: "Not configured"
        case .configured: "Configured"
        case .working: "Working"
        }
    }

    var icon: String {
        switch self {
        case .notConfigured: "circle.dashed"
        case .configured: "checkmark.circle"
        case .working: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notConfigured: .secondary
        case .configured: .primary
        case .working: .green
        }
    }
}

struct GeminiLanguage: Identifiable, Hashable {
    let id: String
    let name: String
}

private let geminiLanguages: [GeminiLanguage] = {
    let rawList: [GeminiLanguage] = [
        GeminiLanguage(id: "auto", name: "Auto detect"),
        GeminiLanguage(id: "af-ZA", name: "Afrikaans"),
        GeminiLanguage(id: "am-ET", name: "Amharic"),
        GeminiLanguage(id: "ar-EG", name: "Arabic (Egypt)"),
        GeminiLanguage(id: "hy-AM", name: "Armenian"),
        GeminiLanguage(id: "as-IN", name: "Assamese"),
        GeminiLanguage(id: "az-AZ", name: "Azerbaijani"),
        GeminiLanguage(id: "be-BY", name: "Belarusian"),
        GeminiLanguage(id: "bn-BD", name: "Bengali (Bangladesh)"),
        GeminiLanguage(id: "bn-IN", name: "Bengali (India)"),
        GeminiLanguage(id: "bs-BA", name: "Bosnian"),
        GeminiLanguage(id: "bg-BG", name: "Bulgarian"),
        GeminiLanguage(id: "rup-BG", name: "Bulgarian (Aromanian)"),
        GeminiLanguage(id: "my-MM", name: "Burmese"),
        GeminiLanguage(id: "yue-Hant-HK", name: "Cantonese (Traditional)"),
        GeminiLanguage(id: "ca-ES", name: "Catalan"),
        GeminiLanguage(id: "ceb", name: "Cebuano"),
        GeminiLanguage(id: "km-KH", name: "Central Khmer"),
        GeminiLanguage(id: "hr-HR", name: "Croatian"),
        GeminiLanguage(id: "cs-CZ", name: "Czech"),
        GeminiLanguage(id: "da-DK", name: "Danish"),
        GeminiLanguage(id: "nl-NL", name: "Dutch"),
        GeminiLanguage(id: "en-GB", name: "English (Great Britain)"),
        GeminiLanguage(id: "en-IN", name: "English (India)"),
        GeminiLanguage(id: "en-US", name: "English (United States)"),
        GeminiLanguage(id: "et-EE", name: "Estonian"),
        GeminiLanguage(id: "fa-IR", name: "Farsi"),
        GeminiLanguage(id: "fil-PH", name: "Filipino"),
        GeminiLanguage(id: "fi-FI", name: "Finnish"),
        GeminiLanguage(id: "fr-FR", name: "French"),
        GeminiLanguage(id: "gl-ES", name: "Galician"),
        GeminiLanguage(id: "ka-GE", name: "Georgian"),
        GeminiLanguage(id: "de-DE", name: "German"),
        GeminiLanguage(id: "el-GR", name: "Greek"),
        GeminiLanguage(id: "gu-IN", name: "Gujarati"),
        GeminiLanguage(id: "ha-NG", name: "Hausa"),
        GeminiLanguage(id: "he-IL", name: "Hebrew"),
        GeminiLanguage(id: "hi-IN", name: "Hindi"),
        GeminiLanguage(id: "hu-HU", name: "Hungarian"),
        GeminiLanguage(id: "is-IS", name: "Icelandic"),
        GeminiLanguage(id: "id-ID", name: "Indonesian"),
        GeminiLanguage(id: "it-IT", name: "Italian"),
        GeminiLanguage(id: "ja-JP", name: "Japanese"),
        GeminiLanguage(id: "jv-ID", name: "Javanese"),
        GeminiLanguage(id: "kn-IN", name: "Kannada"),
        GeminiLanguage(id: "kk-KZ", name: "Kazakh"),
        GeminiLanguage(id: "ko-KR", name: "Korean"),
        GeminiLanguage(id: "ky-KG", name: "Kyrgyz"),
        GeminiLanguage(id: "lv-LV", name: "Latvian"),
        GeminiLanguage(id: "ln-CD", name: "Lingala"),
        GeminiLanguage(id: "lt-LT", name: "Lithuanian"),
        GeminiLanguage(id: "mk-MK", name: "Macedonian"),
        GeminiLanguage(id: "ms-MY", name: "Malay"),
        GeminiLanguage(id: "ml-IN", name: "Malayalam"),
        GeminiLanguage(id: "mt-MT", name: "Maltese"),
        GeminiLanguage(id: "cmn-Hans-CN", name: "Mandarin Chinese (Simplified)"),
        GeminiLanguage(id: "mr-IN", name: "Marathi"),
        GeminiLanguage(id: "mn-MN", name: "Mongolian"),
        GeminiLanguage(id: "ne-NP", name: "Nepali"),
        GeminiLanguage(id: "nb-NO", name: "Norwegian"),
        GeminiLanguage(id: "or-IN", name: "Oriya"),
        GeminiLanguage(id: "pl-PL", name: "Polish"),
        GeminiLanguage(id: "pt-BR", name: "Portuguese (Brazil)"),
        GeminiLanguage(id: "pt-PT", name: "Portuguese (Portugal)"),
        GeminiLanguage(id: "pa-IN", name: "Punjabi"),
        GeminiLanguage(id: "ro-RO", name: "Romanian"),
        GeminiLanguage(id: "ru-RU", name: "Russian"),
        GeminiLanguage(id: "sr-RS", name: "Serbian"),
        GeminiLanguage(id: "sk-SK", name: "Slovak"),
        GeminiLanguage(id: "sl-SI", name: "Slovenian"),
        GeminiLanguage(id: "es-419", name: "Spanish (Latin America)"),
        GeminiLanguage(id: "es-US", name: "Spanish (United States)"),
        GeminiLanguage(id: "sw-KE", name: "Swahili (Kenya)"),
        GeminiLanguage(id: "sv-SE", name: "Swedish"),
        GeminiLanguage(id: "tg-TJ", name: "Tajik"),
        GeminiLanguage(id: "te-IN", name: "Telugu"),
        GeminiLanguage(id: "th-TH", name: "Thai"),
        GeminiLanguage(id: "tr-TR", name: "Turkish"),
        GeminiLanguage(id: "uk-UA", name: "Ukrainian"),
        GeminiLanguage(id: "uz-UZ", name: "Uzbek"),
        GeminiLanguage(id: "vi-VN", name: "Vietnamese")
    ]
    let sortedRest = rawList.filter { $0.id != "auto" }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return [GeminiLanguage(id: "auto", name: "Auto detect")] + sortedRest
}()

private let openAILanguages: [GeminiLanguage] = {
    var namesByCode: [String: String] = [:]
    for language in geminiLanguages where language.id != "auto" {
        guard let code = Locale(identifier: language.id).language.languageCode?.identifier.lowercased(),
              code.count == 2 else { continue }
        namesByCode[code] = Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? language.name
    }
    namesByCode["zh-cn"] = "Chinese (Simplified)"
    namesByCode["zh-tw"] = "Chinese (Traditional)"
    namesByCode["zh-hk"] = "Chinese (Hong Kong)"
    let languages = namesByCode.map { GeminiLanguage(id: $0.key, name: $0.value) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return [GeminiLanguage(id: "auto", name: "Auto detect")] + languages
}()

private func openAILanguageIdentifier(from identifier: String) -> String {
    guard !identifier.isEmpty, identifier != "auto" else { return "auto" }
    let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    if normalized.hasPrefix("zh-") {
        if normalized.contains("tw") || normalized.contains("hant") { return "zh-tw" }
        if normalized.contains("hk") { return "zh-hk" }
        return "zh-cn"
    }
    return Locale(identifier: normalized).language.languageCode?.identifier.lowercased() ?? "auto"
}

@MainActor
@Observable
private final class DictationSettingsModel {
    var devices: [AudioInputDevice] = []

    // Warning
    var warningMessage: String?

    // Dialog presentation
    var editingProvider: SpeechProvider?

    // Gemini
    var geminiApiKey = ""
    var geminiStatus = ""
    var isGeminiWorking = false
    var isGeminiTestedWorking = false

    // OpenAI
    var openAIApiKey = ""
    var openAIStatus = ""
    var isOpenAIWorking = false
    var isOpenAITestedWorking = false

    // Apple On-Device
    var supportedAppleLocales: [Locale] = []
    var appleModelStatus = ""
    var isAppleWorking = false

    var screenCaptureGranted = CGPreflightScreenCaptureAccess()

    private let keychain = KeychainStore()
    private var geminiTask: Task<Void, Never>?
    private var openAITask: Task<Void, Never>?
    private var appleTask: Task<Void, Never>?

    var geminiStatusState: APIKeyStatusState {
        if geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .notConfigured
        } else if isGeminiTestedWorking {
            return .working
        } else {
            return .configured
        }
    }

    var openAIStatusState: APIKeyStatusState {
        if openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .notConfigured
        } else if isOpenAITestedWorking {
            return .working
        } else {
            return .configured
        }
    }

    func load(preferences: AppPreferences) async {
        devices = AudioInputDeviceCatalog.inputDevices()
        geminiApiKey = (try? keychain.string(for: "gemini-api-key")) ?? ""
        openAIApiKey = (try? keychain.string(for: "openai-api-key")) ?? ""
        screenCaptureGranted = CGPreflightScreenCaptureAccess()

        if #available(macOS 26.0, *) {
            let locales = await DictationTranscriber.supportedLocales
            supportedAppleLocales = locales.sorted {
                let name1 = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
                let name2 = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
        }

        normalizeLocale(for: preferences.speechProvider, preferences: preferences)

        if #available(macOS 26.0, *) {
            if preferences.speechProvider == .appleOnDevice {
                let requestedLocale = Locale(identifier: preferences.speechLocale)
                if let supported = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) {
                    preferences.speechLocale = supported.identifier
                } else if let matchedCurrent = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) {
                    preferences.speechLocale = matchedCurrent.identifier
                } else if let first = supportedAppleLocales.first {
                    preferences.speechLocale = first.identifier
                }
                checkAppleModel(preferences: preferences, download: false)
            }
        }

        evaluateWarning(preferences: preferences)
    }

    func providerChanged(_ provider: SpeechProvider, preferences: AppPreferences) {
        cancelWork()
        normalizeLocale(for: provider, preferences: preferences)
        if #available(macOS 26.0, *) {
            if provider == .appleOnDevice {
                Task { @MainActor in
                    let requestedLocale = Locale(identifier: preferences.speechLocale)
                    if let supported = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) {
                        preferences.speechLocale = supported.identifier
                    }
                    checkAppleModel(preferences: preferences, download: false)
                    evaluateWarning(preferences: preferences)
                }
            }
        }
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        evaluateWarning(preferences: preferences)
    }

    func evaluateWarning(preferences: AppPreferences) {
        if preferences.audioSource != .microphone && !screenCaptureGranted {
            warningMessage = "Screen recording permission is required for system audio capture."
            return
        }

        switch preferences.speechProvider {
        case .appleOnDevice:
            if #available(macOS 26.0, *) {
                if isAppleWorking {
                    if appleModelStatus == "downloading" {
                        warningMessage = nil
                    }
                    return
                }
                switch appleModelStatus {
                case "installed":
                    warningMessage = nil
                case "downloading":
                    warningMessage = nil
                case "supported":
                    warningMessage = "Apple On-Device speech model is not downloaded yet. Please click Download below."
                case "unsupported":
                    warningMessage = "The selected speaker language is not supported by Apple On-Device speech recognition."
                default:
                    if !preferences.speechLocale.isEmpty {
                        warningMessage = "Apple On-Device speech model is not downloaded yet. Please click Download below."
                    }
                }
            } else {
                warningMessage = "Apple On-Device speech recognition requires macOS 26 or later."
            }

        case .geminiLive:
            let key = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                warningMessage = "Google Gemini API key is not configured. Please enter your API key below."
            } else {
                warningMessage = nil
            }

        case .openAI:
            let key = openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                warningMessage = "OpenAI API key is not configured. Please enter your API key below."
            } else {
                warningMessage = nil
            }
        }
    }

    // MARK: - Gemini API Key

    func autoSaveGeminiKey() {
        let trimmedKey = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            try? keychain.remove("gemini-api-key")
            isGeminiTestedWorking = false
            geminiStatus = ""
        } else {
            do {
                try keychain.set(trimmedKey, for: "gemini-api-key")
                geminiStatus = "Saved in Keychain"
            } catch {
                geminiStatus = error.localizedDescription
            }
        }
    }

    func clearGeminiKey() {
        geminiApiKey = ""
        try? keychain.remove("gemini-api-key")
        isGeminiTestedWorking = false
        geminiStatus = "Key cleared"
    }

    func testGeminiConnection() {
        autoSaveGeminiKey()
        guard !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        geminiTask?.cancel()
        isGeminiWorking = true
        geminiStatus = "Connecting…"
        geminiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isGeminiWorking = false }
            do {
                try await GeminiLiveEngine().testConnection()
                guard !Task.isCancelled else { return }
                geminiStatus = "Connected"
                isGeminiTestedWorking = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isGeminiTestedWorking = false
                geminiStatus = error.localizedDescription
            }
        }
    }

    // MARK: - OpenAI API Key

    func autoSaveOpenAIKey() {
        let trimmedKey = openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            try? keychain.remove("openai-api-key")
            isOpenAITestedWorking = false
            openAIStatus = ""
        } else {
            do {
                try keychain.set(trimmedKey, for: "openai-api-key")
                openAIStatus = "Saved in Keychain"
            } catch {
                openAIStatus = error.localizedDescription
            }
        }
    }

    func clearOpenAIKey() {
        openAIApiKey = ""
        try? keychain.remove("openai-api-key")
        isOpenAITestedWorking = false
        openAIStatus = "Key cleared"
    }

    func testOpenAIConnection() {
        autoSaveOpenAIKey()
        guard !openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        openAITask?.cancel()
        isOpenAIWorking = true
        openAIStatus = "Connecting…"
        openAITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isOpenAIWorking = false }
            do {
                try await OpenAIRealtimeEngine().testConnection()
                guard !Task.isCancelled else { return }
                openAIStatus = "Connected"
                isOpenAITestedWorking = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isOpenAITestedWorking = false
                openAIStatus = error.localizedDescription
            }
        }
    }

    // MARK: - Apple On-Device

    @available(macOS 26.0, *)
    func checkAppleModel(preferences: AppPreferences, download: Bool) {
        appleTask?.cancel()
        isAppleWorking = true
        let localeIdentifier = preferences.speechLocale
        appleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                isAppleWorking = false
                self.evaluateWarning(preferences: preferences)
            }
            let requestedLocale = Locale(identifier: localeIdentifier)
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
                appleModelStatus = "unsupported"
                return
            }
            guard !Task.isCancelled else { return }
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            do {
                if download,
                   let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    appleModelStatus = "downloading"
                    try await request.downloadAndInstall()
                }
                guard !Task.isCancelled else { return }
                let status = await AssetInventory.status(forModules: [transcriber])
                switch status {
                case .installed:
                    appleModelStatus = "installed"
                case .supported:
                    appleModelStatus = "supported"
                case .downloading:
                    appleModelStatus = "downloading"
                case .unsupported:
                    appleModelStatus = "unsupported"
                @unknown default:
                    appleModelStatus = "unknown"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                appleModelStatus = ""
            }
        }
    }

    func cancelWork() {
        geminiTask?.cancel()
        geminiTask = nil
        openAITask?.cancel()
        openAITask = nil
        appleTask?.cancel()
        appleTask = nil
        isGeminiWorking = false
        isOpenAIWorking = false
        isAppleWorking = false
    }

    private func normalizeLocale(for provider: SpeechProvider, preferences: AppPreferences) {
        switch provider {
        case .appleOnDevice:
            if preferences.speechLocale == "auto" || preferences.speechLocale.isEmpty {
                let current = Locale.current
                if #available(macOS 26.0, *) {
                    if let matched = supportedAppleLocales.first(where: {
                        $0.identifier.replacingOccurrences(of: "_", with: "-") == current.identifier.replacingOccurrences(of: "_", with: "-") ||
                        $0.language.languageCode == current.language.languageCode
                    }) {
                        preferences.speechLocale = matched.identifier
                    } else {
                        preferences.speechLocale = current.identifier.replacingOccurrences(of: "_", with: "-")
                    }
                } else {
                    preferences.speechLocale = current.identifier.replacingOccurrences(of: "_", with: "-")
                }
            }
        case .geminiLive:
            let normalized = preferences.geminiSpeechLocale.replacingOccurrences(of: "_", with: "-")
            preferences.geminiSpeechLocale = geminiLanguages.contains(where: { $0.id == normalized }) ? normalized : "auto"
        case .openAI:
            let normalized = openAILanguageIdentifier(from: preferences.openAISpeechLocale)
            preferences.openAISpeechLocale = openAILanguages.contains(where: { $0.id == normalized }) ? normalized : "auto"
        }
    }
}

private struct DictationSettingsView: View {
    @Bindable var preferences: AppPreferences
    @State private var model = DictationSettingsModel()

    var body: some View {
        @Bindable var model = model

        Form {
            // MARK: - Warning Banner (Top)
            if let warning = model.warningMessage, !warning.isEmpty {
                Section {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.yellow)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Voice Note Not Ready")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(warning)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            withAnimation {
                                model.warningMessage = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: - Section 1: Input Method (Top)
            Section(
                header: Text("Input Method"),
                footer: Text("Choose audio source for recording: Microphone records your voice, System Audio captures computer audio, and Both combines them.")
            ) {
                Picker("Capture", selection: $preferences.audioSource) {
                    ForEach(AudioSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: preferences.audioSource) { _, _ in
                    model.screenCaptureGranted = CGPreflightScreenCaptureAccess()
                }

                Picker("Microphone", selection: Binding(
                    get: {
                        guard let uid = preferences.microphoneUID,
                              model.devices.contains(where: { $0.uid == uid }) else { return "" }
                        return uid
                    },
                    set: { preferences.microphoneUID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System default").tag("")
                    ForEach(model.devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }

                if preferences.audioSource != .microphone {
                    if !model.screenCaptureGranted {
                        LabeledContent("Screen Recording") {
                            Button("Grant Permission") {
                                CGRequestScreenCaptureAccess()
                                model.screenCaptureGranted = CGPreflightScreenCaptureAccess()
                            }
                        }
                        Button("Open System Settings") {
                            openScreenCaptureSettings()
                        }
                        Text("Screen audio requires Screen Recording permission. Grant it, then restart Pocket Stack.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Screen Recording", value: "Granted")
                    }
                }
            }

            // MARK: - Section 2: Provider
            Section(
                header: Text("Provider"),
                footer: Text(providerDescription(for: preferences.speechProvider))
            ) {
                Picker("Provider", selection: $preferences.speechProvider) {
                    ForEach(availableSpeechProviders) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                if preferences.speechProvider == .appleOnDevice {
                    appleSettings(model: model)
                }

                if preferences.speechProvider == .geminiLive {
                    Picker("Speaker language", selection: Binding(
                        get: {
                            let locale = preferences.geminiSpeechLocale
                            return geminiLanguages.contains(where: { $0.id == locale }) ? locale : "auto"
                        },
                        set: { preferences.geminiSpeechLocale = $0 }
                    )) {
                        ForEach(geminiLanguages) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                }

                if preferences.speechProvider == .openAI {
                    Picker("Speaker language", selection: Binding(
                        get: {
                            let locale = openAILanguageIdentifier(from: preferences.openAISpeechLocale)
                            return openAILanguages.contains(where: { $0.id == locale }) ? locale : "auto"
                        },
                        set: { preferences.openAISpeechLocale = $0 }
                    )) {
                        ForEach(openAILanguages) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                }
            }

            // MARK: - Section 3: API Key Configuration
            Section(
                header: Text("API Keys"),
                footer: Text("Click a provider to enter, test, or clear API keys. Keys are autosaved and stored securely in macOS Keychain.")
            ) {
                apiKeyRow(
                    icon: "openai",
                    title: "OpenAI",
                    subtitle: "Realtime Speech-to-Text",
                    status: model.openAIStatusState
                ) {
                    model.openAIStatus = ""
                    model.editingProvider = .openAI
                }

                apiKeyRow(
                    icon: "gemini",
                    title: "Gemini",
                    subtitle: "Google Live Transcribe",
                    status: model.geminiStatusState
                ) {
                    model.geminiStatus = ""
                    model.editingProvider = .geminiLive
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $model.editingProvider) { provider in
            APIKeyDialogView(provider: provider, model: model)
        }
        .task {
            await model.load(preferences: preferences)
        }
        .onChange(of: preferences.speechProvider) { _, provider in
            model.providerChanged(provider, preferences: preferences)
        }
        .onChange(of: preferences.audioSource) { _, _ in
            model.screenCaptureGranted = CGPreflightScreenCaptureAccess()
            model.evaluateWarning(preferences: preferences)
        }
        .onChange(of: preferences.speechLocale) { _, _ in
            model.evaluateWarning(preferences: preferences)
        }
        .onChange(of: model.geminiApiKey) { _, _ in
            model.evaluateWarning(preferences: preferences)
        }
        .onChange(of: model.openAIApiKey) { _, _ in
            model.evaluateWarning(preferences: preferences)
        }
        .onChange(of: model.appleModelStatus) { _, _ in
            model.evaluateWarning(preferences: preferences)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketStackVoiceNoteWarning)) { notification in
            if let reason = notification.object as? String {
                withAnimation {
                    model.warningMessage = reason
                }
            }
        }
        .onDisappear {
            model.cancelWork()
        }
    }

    private func providerDescription(for provider: SpeechProvider) -> String {
        switch provider {
        case .appleOnDevice:
            return "Private, on-device transcription with zero network latency. Requires downloading language models."
        case .geminiLive:
            return "Streaming live speech-to-text powered by Google Gemini Live API."
        case .openAI:
            return "Real-time speech transcription powered by OpenAI Realtime WebSocket API."
        }
    }

    private func apiKeyRow(
        icon: String,
        title: String,
        subtitle: String,
        status: APIKeyStatusState,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: status.icon)
                        .foregroundStyle(status.color)
                    Text(status.title)
                        .font(.caption)
                        .foregroundStyle(status.color)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func appleSettings(model: DictationSettingsModel) -> some View {
        if #available(macOS 26.0, *) {
            Picker("Speaker language", selection: $preferences.speechLocale) {
                if model.supportedAppleLocales.isEmpty {
                    let name = Locale.current.localizedString(forIdentifier: preferences.speechLocale) ?? preferences.speechLocale
                    Text(name.isEmpty ? "System Default" : name).tag(preferences.speechLocale)
                } else {
                    if !preferences.speechLocale.isEmpty && !model.supportedAppleLocales.contains(where: { $0.identifier == preferences.speechLocale }) {
                        let name = Locale.current.localizedString(forIdentifier: preferences.speechLocale) ?? preferences.speechLocale
                        Text(name).tag(preferences.speechLocale)
                    }
                    ForEach(model.supportedAppleLocales, id: \.identifier) { loc in
                        let name = Locale.current.localizedString(forIdentifier: loc.identifier) ?? loc.identifier
                        Text(name).tag(loc.identifier)
                    }
                }
            }
            .onChange(of: preferences.speechLocale) { _, _ in
                model.checkAppleModel(preferences: preferences, download: false)
                model.evaluateWarning(preferences: preferences)
            }

            LabeledContent("Language model") {
                HStack(spacing: 8) {
                    if model.isAppleWorking {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.appleModelStatus == "downloading" ? "Downloading…" : "Checking…")
                            .foregroundStyle(.secondary)
                    } else {
                        switch model.appleModelStatus {
                        case "installed":
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Installed")
                                    .foregroundStyle(.secondary)
                            }
                        case "supported":
                            Button("Download") {
                                model.checkAppleModel(preferences: preferences, download: true)
                            }
                        case "downloading":
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading…")
                                .foregroundStyle(.secondary)
                        case "unsupported":
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("Unsupported")
                                    .foregroundStyle(.secondary)
                            }
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    private func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    private var availableSpeechProviders: [SpeechProvider] {
        if #available(macOS 26.0, *) {
            SpeechProvider.allCases
        } else {
            [.geminiLive, .openAI]
        }
    }
}

private struct APIKeyDialogView: View {
    let provider: SpeechProvider
    @Bindable var model: DictationSettingsModel
    @Environment(\.dismiss) private var dismiss

    var isGemini: Bool { provider == .geminiLive }
    var providerName: String { isGemini ? "Google Gemini" : "OpenAI" }
    var assetName: String { isGemini ? "gemini" : "openai" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(providerName) API Key")
                        .font(.headline)
                    Text("API key is saved automatically to macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if isGemini {
                    SecureField("AIzaSy...", text: $model.geminiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.geminiApiKey) { _, _ in
                            model.autoSaveGeminiKey()
                        }
                } else {
                    SecureField("sk-...", text: $model.openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.openAIApiKey) { _, _ in
                            model.autoSaveOpenAIKey()
                        }
                }
            }

            let status = isGemini ? model.geminiStatus : model.openAIStatus
            let isWorking = isGemini ? model.isGeminiWorking : model.isOpenAIWorking
            if isWorking || !status.isEmpty {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status == "Connected" ? .green : .secondary)
                }
            }

            HStack {
                Button("Test Connection") {
                    if isGemini {
                        model.testGeminiConnection()
                    } else {
                        model.testOpenAIConnection()
                    }
                }
                .disabled(isGemini ? (model.isGeminiWorking || model.geminiApiKey.isEmpty) : (model.isOpenAIWorking || model.openAIApiKey.isEmpty))

                Button("Clear", role: .destructive) {
                    if isGemini {
                        model.clearGeminiKey()
                    } else {
                        model.clearOpenAIKey()
                    }
                }
                .disabled(isGemini ? model.geminiApiKey.isEmpty : model.openAIApiKey.isEmpty)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct SyncSettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Sync is coming soon",
            systemImage: "arrow.triangle.2.circlepath",
            description: Text("No listener, account, or note transfer service is enabled in this release.")
        )
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var updateCoordinator: UpdateCoordinator
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var notices: String {
        guard let url = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "Third-party notices are unavailable."
        }
        return contents
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Pocket Stack")
                            .font(.title2.bold())
                        Text("Version \(version) (\(build))")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Updates") {
                Button("Check for Updates…") {
                    updateCoordinator.checkForUpdates()
                }
                .disabled(!updateCoordinator.canCheckForUpdates)

                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updateCoordinator.automaticallyChecksForUpdates },
                        set: updateCoordinator.setAutomaticallyChecksForUpdates
                    )
                )
            }

            Section("Acknowledgements") {
                ScrollView {
                    Text(notices)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220)
            }
        }
        .formStyle(.grouped)
    }
}
