import Foundation

@MainActor
final class DictationCoordinator {
    private let preferences: AppPreferences
    private var currentSession: (any DictationSession)?
    private var eventTask: Task<Void, Never>?

    init(preferences: AppPreferences) { self.preferences = preferences }

    func start(noteID: UUID, bridge: EditorBridge, state: @escaping @MainActor (DictationState) -> Void) async throws {
        guard currentSession == nil else { return }
        let engine: any DictationEngine = preferences.speechProvider == .appleOnDevice ? AppleDictationEngine() : GeminiLiveEngine()
        let locale = preferences.speechProvider == .geminiLive && preferences.speechLocale == "auto" ? nil : preferences.speechLocale
        let session = try await engine.start(localeIdentifier: locale, deviceUID: preferences.microphoneUID)
        currentSession = session
        bridge.beginDictation()
        state(.listening)
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
            self?.currentSession = nil
            self?.eventTask = nil
        }
    }

    func stop() async {
        guard let currentSession else { return }
        await currentSession.stop()
    }

    func cancel() async {
        await currentSession?.cancel()
        eventTask?.cancel()
        eventTask = nil
        currentSession = nil
    }
}
