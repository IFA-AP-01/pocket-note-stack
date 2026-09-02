import AppKit
import Speech
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case shortcuts
    case speech
    case sync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .speech: "Dictation"
        case .sync: "Sync"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        case .speech: "waveform"
        case .sync: "arrow.triangle.2.circlepath"
        }
    }
}

struct SettingsView: View {
    @Bindable var preferences: AppPreferences
    let environment: AppEnvironment
    @AppStorage("settings.selectedPane") private var selectedPane = SettingsPane.general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPane) {
                Section("Settings") {
                    ForEach(SettingsPane.allCases) { pane in
                        NavigationLink(value: pane) {
                            Label(pane.title, systemImage: pane.systemImage)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selectedPane {
                case .general:
                    GeneralSettingsView(
                        preferences: preferences,
                        refresh: environment.deckCoordinator.refreshAll
                    )
                case .appearance:
                    AppearanceSettingsView(
                        preferences: preferences,
                        refresh: environment.deckCoordinator.refreshAll
                    )
                case .shortcuts:
                    ShortcutsSettingsView()
                case .speech:
                    SpeechSettingsView(preferences: preferences)
                case .sync:
                    SyncSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 520)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var preferences: AppPreferences
    let refresh: () -> Void
    @State private var launchAtLogin = AppPreferences.shared.launchAtLogin

    var body: some View {
        Form {
            Section("Deck") {
                Picker("Screen edge", selection: $preferences.edge) {
                    Text("Left").tag(DeckEdge.left)
                    Text("Right").tag(DeckEdge.right)
                    Text("Bottom").tag(DeckEdge.bottom)
                }
                Picker("Style", selection: $preferences.style) {
                    ForEach(DeckStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Displays", selection: $preferences.displayTarget) {
                    Text("All displays").tag("all"); Text("Main display").tag("main")
                }
                Slider(value: $preferences.deckScale, in: 0.7...1.8, step: 0.05) { Text("Deck scale") }
                Slider(value: $preferences.edgeWidth, in: 8...44, step: 2) { Text("Edge activation width") }
                Toggle("Open note when hovering a tab", isOn: $preferences.openOnHover)
                Toggle("Show over full-screen apps", isOn: $preferences.showOverFullScreen)
            }
            Section("Startup") {
                Toggle("Launch Pocket Stack at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in preferences.launchAtLogin = value }
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.edge) { _, _ in refresh() }
        .onChange(of: preferences.style) { _, _ in refresh() }
        .onChange(of: preferences.deckScale) { _, _ in refresh() }
        .onChange(of: preferences.edgeWidth) { _, _ in refresh() }
        .onChange(of: preferences.showOverFullScreen) { _, _ in refresh() }
        .onChange(of: preferences.displayTarget) { _, _ in refresh() }
    }
}

private struct AppearanceSettingsView: View {
    @Bindable var preferences: AppPreferences
    let refresh: () -> Void
    private let fonts = ["", "Noteworthy-Light", "AvenirNext-Regular", "Georgia", "Menlo-Regular"]

    var body: some View {
        Form {
            Picker("Note font", selection: $preferences.noteFontName) {
                ForEach(fonts, id: \.self) { Text($0.isEmpty ? "System" : $0).tag($0) }
            }
            Slider(value: $preferences.noteFontSize, in: 10...30, step: 0.5) { Text("Font size") }
            Picker("Note size", selection: $preferences.noteSizeIndex) {
                Text("Small").tag(0); Text("Medium").tag(1); Text("Large").tag(2); Text("Huge").tag(3)
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.noteFontName) { _, _ in refresh() }
        .onChange(of: preferences.noteFontSize) { _, _ in refresh() }
        .onChange(of: preferences.noteSizeIndex) { _, _ in refresh() }
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
                    LabeledContent(name) { Text(keys).font(.system(.body, design: .monospaced)) }
                }
            }
            Text("Global shortcuts use the Carbon hot-key API and do not require Accessibility permission.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}

private struct SpeechSettingsView: View {
    @Bindable var preferences: AppPreferences
    @State private var devices: [AudioInputDevice] = []
    @State private var apiKey = ""
    @State private var status = ""
    @State private var isWorking = false
    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Picker("Provider", selection: $preferences.speechProvider) {
                ForEach(availableSpeechProviders) { Text($0.title).tag($0) }
            }
            Picker("Microphone", selection: Binding(
                get: { preferences.microphoneUID ?? "" },
                set: { preferences.microphoneUID = $0.isEmpty ? nil : $0 }
            )) {
                Text("System default").tag("")
                ForEach(devices) { Text($0.name).tag($0.uid) }
            }
            if preferences.speechProvider == .appleOnDevice {
                if #available(macOS 26.0, *) {
                    TextField("Language / locale", text: $preferences.speechLocale)
                    HStack {
                        Text("On-device model"); Spacer()
                        Text(status.isEmpty ? "Checking…" : status).foregroundStyle(.secondary)
                        Button("Check / Download") { checkAppleModel(download: true) }.disabled(isWorking)
                    }
                    Text("Audio stays on this Mac. Language assets may need to be downloaded once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Picker("Language", selection: $preferences.speechLocale) {
                    Text("Auto detect").tag("auto"); Text("English").tag("en-US"); Text("Vietnamese").tag("vi-VN")
                }
                SecureField("Gemini API key", text: $apiKey)
                HStack {
                    Button("Save") { saveKey() }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Delete", role: .destructive) { deleteKey() }
                    Button("Test Connection") { testGemini() }.disabled(isWorking || apiKey.isEmpty)
                    Spacer(); Text(status).foregroundStyle(.secondary)
                }
                Text("Microphone audio is streamed to Google only while Gemini Live is selected and dictation is active.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            devices = AudioDeviceManager.inputDevices()
            apiKey = (try? keychain.string(for: "gemini-api-key")) ?? ""
            if #available(macOS 26.0, *), preferences.speechProvider == .appleOnDevice {
                checkAppleModel(download: false)
            }
        }
        .onChange(of: preferences.speechProvider) { _, provider in
            status = ""
            if #available(macOS 26.0, *), provider == .appleOnDevice {
                checkAppleModel(download: false)
            }
        }
    }

    private var availableSpeechProviders: [SpeechProvider] {
        if #available(macOS 26.0, *) {
            SpeechProvider.allCases
        } else {
            [.geminiLive]
        }
    }

    private func saveKey() {
        do { try keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "gemini-api-key"); status = "Saved in Keychain" }
        catch { status = error.localizedDescription }
    }
    private func deleteKey() {
        do { try keychain.remove("gemini-api-key"); apiKey = ""; status = "Removed" }
        catch { status = error.localizedDescription }
    }
    private func testGemini() {
        saveKey(); isWorking = true; status = "Connecting…"
        Task {
            do { try await GeminiLiveEngine().testConnection(); status = "Connected" }
            catch { status = error.localizedDescription }
            isWorking = false
        }
    }
    @available(macOS 26.0, *)
    private func checkAppleModel(download: Bool) {
        isWorking = true
        Task {
            let requested = Locale(identifier: preferences.speechLocale)
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
                status = "Unsupported"; isWorking = false; return
            }
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            do {
                if download, let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    status = "Downloading…"; try await request.downloadAndInstall()
                }
                status = String(describing: await AssetInventory.status(forModules: [transcriber])).capitalized
            } catch { status = error.localizedDescription }
            isWorking = false
        }
    }
}

private struct SyncSettingsView: View {
    var body: some View {
        Form {
            Section {
                Toggle("Enable local Wi-Fi sync", isOn: .constant(false))
                TextField("Device name", text: .constant(Host.current().localizedName ?? "This Mac"))
                TextField("Port", value: .constant(8765), format: .number)
                Button("Pair mobile device…") {}
                LabeledContent("Status", value: "Coming soon")
            }.disabled(true)
            ContentUnavailableView("Local sync is coming soon", systemImage: "wifi", description: Text("No listener or note data transfer is enabled in this release."))
        }.formStyle(.grouped)
    }
}
