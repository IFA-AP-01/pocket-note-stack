import AppKit
import Combine
import ScreenCaptureKit

@MainActor
final class DictationCoordinator: ObservableObject {
    private let preferences: AppPreferences
    private let engineFactory: any DictationEngineFactory
    @Published private(set) var isRecording = false
    private var currentSession: (any DictationSession)?
    private var eventTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?

    init(
        preferences: AppPreferences,
        engineFactory: any DictationEngineFactory = DefaultDictationEngineFactory()
    ) {
        self.preferences = preferences
        self.engineFactory = engineFactory
    }

    func checkProviderReadiness() async -> (isReady: Bool, reason: String) {
        if preferences.audioSource != .microphone, !CGPreflightScreenCaptureAccess() {
            return (false, "Screen recording permission is required for system audio capture.")
        }

        let readiness = await engineFactory
            .makeEngine(for: preferences.speechProvider)
            .readiness(for: makeRequest())
        return (readiness.isReady, readiness.reason)
    }

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

        let engine = engineFactory.makeEngine(for: preferences.speechProvider)
        do {
            let session = try await engine.start(makeRequest())
            guard !Task.isCancelled else {
                await session.cancel()
                throw CancellationError()
            }
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
                        case .promoteInterim:
                            bridge.promoteInterim()
                        case .final(let text):
                            bridge.commitFinal(text)
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                self.resetSilenceTimer(bridge: bridge)
                            }
                        }
                    }
                    self?.silenceTask?.cancel()
                    self?.silenceTask = nil
                    bridge.finishDictation(discardInterim: false)
                    state(.idle)
                } catch {
                    self?.silenceTask?.cancel()
                    self?.silenceTask = nil
                    bridge.finishDictation(discardInterim: false)
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

    private func makeRequest() -> DictationRequest {
        let locale: String?
        if preferences.speechProvider == .appleOnDevice {
            locale = (preferences.speechLocale.isEmpty || preferences.speechLocale == "auto")
                ? Locale.current.identifier
                : preferences.speechLocale
        } else {
            locale = (preferences.speechLocale == "auto" || preferences.speechLocale.isEmpty)
                ? nil
                : preferences.speechLocale
        }
        return DictationRequest(
            localeIdentifier: locale,
            deviceUID: preferences.microphoneUID,
            audioSource: preferences.audioSource
        )
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
        await eventTask?.value
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
