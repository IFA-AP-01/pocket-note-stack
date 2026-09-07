import AppKit
import Combine
import ScreenCaptureKit

@MainActor
final class DictationCoordinator: ObservableObject {
    private let preferences: AppPreferences
    @Published private(set) var isRecording = false
    private var currentSession: (any DictationSession)?
    private var eventTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?

    init(preferences: AppPreferences) { self.preferences = preferences }

    func beginPreparing() {
        isRecording = true
    }

    func start(
        noteID: UUID,
        bridge: EditorBridge,
        onAudioLevel: (@MainActor @Sendable (Float) -> Void)? = nil,
        state: @escaping @MainActor (DictationState) -> Void
    ) async throws {
        guard currentSession == nil else { return }

        if preferences.audioSource != .microphone, !CGPreflightScreenCaptureAccess() {
            throw DictationError.screenCapturePermissionDenied
        }

        let engine: any DictationEngine
        switch preferences.speechProvider {
        case .appleOnDevice:
            guard #available(macOS 26.0, *) else {
                throw DictationError.appleOnDeviceUnavailable
            }
            engine = AppleDictationEngine()
        case .geminiLive:
            engine = GeminiLiveEngine()
        }
        let locale = preferences.speechProvider == .geminiLive && preferences.speechLocale == "auto" ? nil : preferences.speechLocale
        do {
            let session = try await engine.start(localeIdentifier: locale, deviceUID: preferences.microphoneUID, audioSource: preferences.audioSource)
            currentSession = session
            isRecording = true
            bridge.beginDictation()
            state(.listening)

            if let levels = session.audioLevels {
                levelTask = Task {
                    for await level in levels {
                        onAudioLevel?(level)
                    }
                    onAudioLevel?(0.0)
                }
            }

            eventTask = Task { [weak self] in
                do {
                    for try await event in session.events {
                        guard let self else { return }
                        switch event {
                        case .interim(let text):
                            bridge.applyInterim(text)
                            self.silenceTask?.cancel()
                            self.silenceTask = nil
                        case .final(let text):
                            bridge.commitFinal(text)
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                self.resetSilenceTimer(bridge: bridge)
                            }
                        }
                    }
                    self?.silenceTask?.cancel()
                    self?.silenceTask = nil
                    bridge.finishDictation(discardInterim: true)
                    state(.idle)
                } catch {
                    self?.silenceTask?.cancel()
                    self?.silenceTask = nil
                    bridge.finishDictation(discardInterim: true)
                    state(.failed(error.localizedDescription))
                    try? await Task.sleep(for: .seconds(3))
                    state(.idle)
                }
                self?.silenceTask?.cancel()
                self?.silenceTask = nil
                self?.levelTask?.cancel()
                self?.levelTask = nil
                onAudioLevel?(0.0)
                self?.currentSession = nil
                self?.isRecording = false
                self?.eventTask = nil
            }
        } catch {
            isRecording = false
            throw error
        }
    }

    private func resetSilenceTimer(bridge: EditorBridge) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self, weak bridge] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            guard let self, self.isRecording else { return }
            bridge?.insertDictationNewline()
        }
    }

    func stop() async {
        isRecording = false
        silenceTask?.cancel()
        silenceTask = nil
        levelTask?.cancel()
        levelTask = nil
        guard let currentSession else { return }
        await currentSession.stop()
    }

    func cancel() async {
        isRecording = false
        silenceTask?.cancel()
        silenceTask = nil
        levelTask?.cancel()
        levelTask = nil
        await currentSession?.cancel()
        eventTask?.cancel()
        eventTask = nil
        currentSession = nil
    }
}
