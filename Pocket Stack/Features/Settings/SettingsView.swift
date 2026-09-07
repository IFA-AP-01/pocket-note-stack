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

    // Gemini
    var geminiApiKey = ""
    var geminiStatus = ""
    var isGeminiWorking = false
    var isConfirmingGeminiKeyDeletion = false

    // OpenAI
    var openAIApiKey = ""
    var openAIStatus = ""
    var isOpenAIWorking = false
    var isConfirmingOpenAIKeyDeletion = false

    // Apple On-Device
    var supportedAppleLocales: [Locale] = []
    var appleModelStatus = ""
    var isAppleWorking = false

    var screenCaptureGranted = CGPreflightScreenCaptureAccess()

    private let keychain = KeychainStore()
    private var geminiTask: Task<Void, Never>?
    private var openAITask: Task<Void, Never>?
    private var appleTask: Task<Void, Never>?

    func load(preferences: AppPreferences) async {
        devices = AudioDeviceManager.inputDevices()
        geminiApiKey = (try? keychain.string(for: "gemini-api-key")) ?? ""
        openAIApiKey = (try? keychain.string(for: "openai-api-key")) ?? ""
        normalizeLocale(for: preferences.speechProvider, preferences: preferences)
        if #available(macOS 26.0, *) {
            let locales = await DictationTranscriber.supportedLocales
            supportedAppleLocales = locales.sorted {
                let name1 = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
                let name2 = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
            if preferences.speechProvider == .appleOnDevice {
                checkAppleModel(preferences: preferences, download: false)
            }
        }
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
    }

    func providerChanged(_ provider: SpeechProvider, preferences: AppPreferences) {
        cancelWork()
        normalizeLocale(for: provider, preferences: preferences)
        if #available(macOS 26.0, *) {
            if provider == .appleOnDevice {
                checkAppleModel(preferences: preferences, download: false)
            }
        }
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
    }

    // MARK: - Gemini API Key

    func saveGeminiKey() -> Bool {
        let trimmedKey = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }
        do {
            try keychain.set(trimmedKey, for: "gemini-api-key")
            geminiApiKey = trimmedKey
            geminiStatus = "Saved in Keychain"
            return true
        } catch {
            geminiStatus = error.localizedDescription
            return false
        }
    }

    func deleteGeminiKey() {
        do {
            try keychain.remove("gemini-api-key")
            geminiApiKey = ""
            geminiStatus = "Removed"
        } catch {
            geminiStatus = error.localizedDescription
        }
    }

    func testGeminiConnection() {
        guard saveGeminiKey() else { return }
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
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                geminiStatus = error.localizedDescription
            }
        }
    }

    // MARK: - OpenAI API Key

    func saveOpenAIKey() -> Bool {
        let trimmedKey = openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }
        do {
            try keychain.set(trimmedKey, for: "openai-api-key")
            openAIApiKey = trimmedKey
            openAIStatus = "Saved in Keychain"
            return true
        } catch {
            openAIStatus = error.localizedDescription
            return false
        }
    }

    func deleteOpenAIKey() {
        do {
            try keychain.remove("openai-api-key")
            openAIApiKey = ""
            openAIStatus = "Removed"
        } catch {
            openAIStatus = error.localizedDescription
        }
    }

    func testOpenAIConnection() {
        guard saveOpenAIKey() else { return }
        openAITask?.cancel()
        isOpenAIWorking = true
        openAIStatus = "Connecting…"
        openAITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isOpenAIWorking = false }
            do {
                guard let key = try keychain.string(for: "openai-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                    openAIStatus = "API key missing"
                    return
                }
                guard let url = URL(string: "https://api.openai.com/v1/models") else { return }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10
                let (_, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard let httpResponse = response as? HTTPURLResponse else {
                    openAIStatus = "Invalid response"
                    return
                }
                if httpResponse.statusCode == 200 {
                    openAIStatus = "Connected"
                } else if httpResponse.statusCode == 401 {
                    openAIStatus = "Invalid API key"
                } else {
                    openAIStatus = "HTTP \(httpResponse.statusCode)"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
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
            defer { isAppleWorking = false }
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
                preferences.speechLocale = Locale.current.identifier
            }
        case .geminiLive, .openAI:
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
            // MARK: - Section 1: Input Method (Top)
            Section("Input Method") {
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
                    get: { preferences.microphoneUID ?? "" },
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
            Section("Provider") {
                Picker("Provider", selection: $preferences.speechProvider) {
                    ForEach(availableSpeechProviders) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                if preferences.speechProvider == .appleOnDevice {
                    appleSettings(model: model)
                }

                if preferences.speechProvider == .geminiLive {
                    Picker("Language", selection: $preferences.speechLocale) {
                        Text("Auto detect").tag("auto")
                        Text("English").tag("en-US")
                        Text("Vietnamese").tag("vi-VN")
                    }
                }

                openAIConfigCard(model: model)
                geminiConfigCard(model: model)
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
            isPresented: $model.isConfirmingGeminiKeyDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete API Key", role: .destructive) {
                model.deleteGeminiKey()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete the saved OpenAI API key?",
            isPresented: $model.isConfirmingOpenAIKeyDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete API Key", role: .destructive) {
                model.deleteOpenAIKey()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func appleSettings(model: DictationSettingsModel) -> some View {
        if #available(macOS 26.0, *) {
            Picker("Language / locale", selection: $preferences.speechLocale) {
                if model.supportedAppleLocales.isEmpty {
                    Text(preferences.speechLocale).tag(preferences.speechLocale)
                } else {
                    ForEach(model.supportedAppleLocales, id: \.identifier) { loc in
                        let name = Locale.current.localizedString(forIdentifier: loc.identifier) ?? loc.identifier
                        Text("\(name) (\(loc.identifier))").tag(loc.identifier)
                    }
                }
            }
            .onChange(of: preferences.speechLocale) { _, _ in
                model.checkAppleModel(preferences: preferences, download: false)
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

    @ViewBuilder
    private func openAIConfigCard(model: DictationSettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image("openai")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenAI")
                        .font(.body.weight(.medium))
                    Text("OpenAI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !model.openAIApiKey.isEmpty {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 2)

            SecureField("OpenAI API key", text: Bindable(model).openAIApiKey, prompt: Text("sk-..."))

            HStack {
                Button("Save") {
                    _ = model.saveOpenAIKey()
                }
                .disabled(model.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Delete", role: .destructive) {
                    model.isConfirmingOpenAIKeyDeletion = true
                }
                .disabled(model.openAIApiKey.isEmpty)

                Button("Test Connection") {
                    model.testOpenAIConnection()
                }
                .disabled(model.isOpenAIWorking || model.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if model.isOpenAIWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.openAIStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func geminiConfigCard(model: DictationSettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image("gemini")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gemini")
                        .font(.body.weight(.medium))
                    Text("Google")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !model.geminiApiKey.isEmpty {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 2)

            SecureField("Gemini API key", text: Bindable(model).geminiApiKey, prompt: Text("AIzaSy..."))

            HStack {
                Button("Save") {
                    _ = model.saveGeminiKey()
                }
                .disabled(model.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Delete", role: .destructive) {
                    model.isConfirmingGeminiKeyDeletion = true
                }
                .disabled(model.geminiApiKey.isEmpty)

                Button("Test Connection") {
                    model.testGeminiConnection()
                }
                .disabled(model.isGeminiWorking || model.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if model.isGeminiWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.geminiStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Microphone audio is streamed to Google only while Gemini is selected and dictation is active.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
