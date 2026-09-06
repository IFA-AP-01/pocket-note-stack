import AppKit
import ScreenCaptureKit

@MainActor
final class DictationCoordinator {
    private let preferences: AppPreferences
    private var currentSession: (any DictationSession)?
    private var eventTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

    init(preferences: AppPreferences) { self.preferences = preferences }

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
        let session = try await engine.start(localeIdentifier: locale, deviceUID: preferences.microphoneUID, audioSource: preferences.audioSource)
        currentSession = session
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
                    switch event {
                    case .interim(let text): bridge.applyInterim(text)
                    case .final(let text): bridge.commitFinal(text)
                    }
                }
                bridge.finishDictation(discardInterim: true)
                state(.idle)
            } catch {
                bridge.finishDictation(discardInterim: true)
                state(.failed(error.localizedDescription))
                try? await Task.sleep(for: .seconds(3))
                state(.idle)
            }
            self?.levelTask?.cancel()
            self?.levelTask = nil
            onAudioLevel?(0.0)
            self?.currentSession = nil
            self?.eventTask = nil
        }
    }

    func stop() async {
        levelTask?.cancel()
        levelTask = nil
        guard let currentSession else { return }
        await currentSession.stop()
    }

    func cancel() async {
        levelTask?.cancel()
        levelTask = nil
        await currentSession?.cancel()
        eventTask?.cancel()
        eventTask = nil
        currentSession = nil
    }
}
