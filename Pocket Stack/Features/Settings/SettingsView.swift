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
        case .dictation: "Dictation"
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
                    AboutSettingsView()
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
    @State private var launchAtLogin = AppPreferences.shared.launchAtLogin
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
            launchAtLogin = preferences.launchAtLogin
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
        do {
            try preferences.setLaunchAtLogin(enabled)
            launchAtLogin = preferences.launchAtLogin
        } catch {
            launchAtLogin = previousValue
            launchAtLoginError = error.localizedDescription
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

@MainActor
@Observable
private final class DictationSettingsModel {
    var devices: [AudioInputDevice] = []
    var apiKey = ""
    var status = ""
    var isWorking = false
    var isConfirmingKeyDeletion = false

    private let keychain = KeychainStore()
    private var workTask: Task<Void, Never>?

    func load(preferences: AppPreferences) async {
        devices = AudioDeviceManager.inputDevices()
        apiKey = (try? keychain.string(for: "gemini-api-key")) ?? ""
        normalizeLocale(for: preferences.speechProvider, preferences: preferences)
        if #available(macOS 26.0, *), preferences.speechProvider == .appleOnDevice {
            checkAppleModel(preferences: preferences, download: false)
        }
    }

    func providerChanged(_ provider: SpeechProvider, preferences: AppPreferences) {
        cancelWork()
        status = ""
        normalizeLocale(for: provider, preferences: preferences)
        if #available(macOS 26.0, *), provider == .appleOnDevice {
            checkAppleModel(preferences: preferences, download: false)
        }
    }

    func saveAPIKey() -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }
        do {
            try keychain.set(trimmedKey, for: "gemini-api-key")
            apiKey = trimmedKey
            status = "Saved in Keychain"
            return true
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    func deleteAPIKey() {
        do {
            try keychain.remove("gemini-api-key")
            apiKey = ""
            status = "Removed"
        } catch {
            status = error.localizedDescription
        }
    }

    func testGeminiConnection() {
        guard saveAPIKey() else { return }
        cancelWork()
        isWorking = true
        status = "Connecting…"
        workTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isWorking = false }
            do {
                try await GeminiLiveEngine().testConnection()
                guard !Task.isCancelled else { return }
                status = "Connected"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                status = error.localizedDescription
            }
        }
    }

    @available(macOS 26.0, *)
    func checkAppleModel(preferences: AppPreferences, download: Bool) {
        cancelWork()
        isWorking = true
        status = download ? "Preparing…" : "Checking…"
        let localeIdentifier = preferences.speechLocale
        workTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isWorking = false }
            let requestedLocale = Locale(identifier: localeIdentifier)
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
                status = "Unsupported"
                return
            }
            guard !Task.isCancelled else { return }
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            do {
                if download,
                   let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    status = "Downloading…"
                    try await request.downloadAndInstall()
                }
                guard !Task.isCancelled else { return }
                status = String(describing: await AssetInventory.status(forModules: [transcriber])).capitalized
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                status = error.localizedDescription
            }
        }
    }

    func cancelWork() {
        workTask?.cancel()
        workTask = nil
        isWorking = false
    }

    private func normalizeLocale(for provider: SpeechProvider, preferences: AppPreferences) {
        switch provider {
        case .appleOnDevice:
            if preferences.speechLocale == "auto" {
                preferences.speechLocale = Locale.current.identifier
            }
        case .geminiLive:
            let locale = preferences.speechLocale.lowercased()
            if locale.hasPrefix("vi") {
                preferences.speechLocale = "vi-VN"
            } else if locale.hasPrefix("en") {
                preferences.speechLocale = "en-US"
            } else if preferences.speechLocale != "auto" {
                preferences.speechLocale = "auto"
            }
        }
    }
}

private struct DictationSettingsView: View {
    @Bindable var preferences: AppPreferences
    @State private var model = DictationSettingsModel()

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Input") {
                Picker("Provider", selection: $preferences.speechProvider) {
                    ForEach(availableSpeechProviders) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                Picker("Microphone", selection: Binding(
                    get: { preferences.microphoneUID ?? "" },
                    set: { preferences.microphoneUID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System default").tag("")
                    ForEach(model.devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }

            if preferences.speechProvider == .appleOnDevice {
                appleSettings(model: model)
            } else {
                Section("Gemini Live") {
                    Picker("Language", selection: $preferences.speechLocale) {
                        Text("Auto detect").tag("auto")
                        Text("English").tag("en-US")
                        Text("Vietnamese").tag("vi-VN")
                    }

                    SecureField("API key", text: $model.apiKey)

                    HStack {
                        Button("Save") {
                            _ = model.saveAPIKey()
                        }
                        .disabled(model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Delete", role: .destructive) {
                            model.isConfirmingKeyDeletion = true
                        }
                        .disabled(model.apiKey.isEmpty)

                        Button("Test Connection") {
                            model.testGeminiConnection()
                        }
                        .disabled(model.isWorking || model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()
                        if model.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(model.status)
                            .foregroundStyle(.secondary)
                    }

                    Text("Microphone audio is streamed to Google only while Gemini Live is selected and dictation is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await model.load(preferences: preferences)
        }
        .onChange(of: preferences.speechProvider) { _, provider in
            model.providerChanged(provider, preferences: preferences)
        }
        .onDisappear {
            model.cancelWork()
        }
        .confirmationDialog(
            "Delete the saved Gemini API key?",
            isPresented: $model.isConfirmingKeyDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete API Key", role: .destructive) {
                model.deleteAPIKey()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func appleSettings(model: DictationSettingsModel) -> some View {
        if #available(macOS 26.0, *) {
            Section("Apple On-Device") {
                TextField("Language / locale", text: $preferences.speechLocale)

                LabeledContent("Language model") {
                    HStack {
                        if model.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(model.status.isEmpty ? "Not checked" : model.status)
                            .foregroundStyle(.secondary)
                        Button("Check / Download") {
                            model.checkAppleModel(preferences: preferences, download: true)
                        }
                        .disabled(model.isWorking)
                    }
                }

                Text("Audio stays on this Mac. Language assets may need to be downloaded once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView(
                "Apple on-device dictation is unavailable",
                systemImage: "waveform.badge.exclamationmark",
                description: Text("Use Gemini Live on this version of macOS.")
            )
        }
    }

    private var availableSpeechProviders: [SpeechProvider] {
        if #available(macOS 26.0, *) {
            SpeechProvider.allCases
        } else {
            [.geminiLive]
        }
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
