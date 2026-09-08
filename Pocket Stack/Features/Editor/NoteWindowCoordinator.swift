import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class NoteWindowCoordinator: NSObject {
    private let model: AppModel
    private let preferences: AppPreferences
    private let dictation: DictationCoordinator
    @ObservationIgnored private var windows: [UUID: NoteWindowController] = [:]
    @ObservationIgnored private var noteObserver: NSObjectProtocol?
    @ObservationIgnored private var dictationStartTask: Task<Void, Never>?
    @ObservationIgnored weak var deckCoordinator: DeckCoordinator?

    private(set) var openNoteIDs: Set<UUID> = []
    private(set) var dictatingNoteID: UUID?
    private(set) var dictationState: DictationState = .idle
    private(set) var audioLevel: Float = 0

    init(model: AppModel, preferences: AppPreferences, dictation: DictationCoordinator) {
        self.model = model
        self.preferences = preferences
        self.dictation = dictation
        super.init()
        noteObserver = NotificationCenter.default.addObserver(
            forName: .pocketStackNotesDidChange,
            object: model,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notesDidChange()
            }
        }
    }

    var isDictating: Bool { dictationState != .idle }

    func isOpen(noteID: UUID) -> Bool { windows[noteID] != nil }

    // MARK: - Window Management

    func open(noteID: UUID, anchor: NoteWindowAnchor?) {
        guard model.note(id: noteID)?.isArchived == false else { return }
        if let existing = windows[noteID] {
            existing.focus()
            return
        }

        let controller = NoteWindowController(
            noteID: noteID,
            model: model,
            preferences: preferences,
            delegate: self,
            initialAnchor: anchor
        )
        windows[noteID] = controller
        openNoteIDs.insert(noteID)
        controller.show()
        if controller.isAnchored, let displayID = controller.anchor?.displayID {
            deckCoordinator?.attachmentChanged(noteID: noteID, displayID: displayID, attached: true)
        }
    }

    func close(noteID: UUID) {
        removeWindow(noteID: noteID, closeWindow: true)
    }

    private func removeWindow(noteID: UUID, closeWindow: Bool) {
        guard let controller = windows.removeValue(forKey: noteID) else { return }
        if dictatingNoteID == noteID { stopDictation() }
        let oldAnchor = controller.anchor
        if closeWindow { controller.closeWindow() }
        openNoteIDs.remove(noteID)
        if controller.isAnchored, let displayID = oldAnchor?.displayID {
            deckCoordinator?.attachmentChanged(noteID: noteID, displayID: displayID, attached: false)
        }
    }

    func stop() {
        stopDictation()
        let ids = Array(windows.keys)
        ids.forEach(close(noteID:))
    }

    func screenParametersChanged() {
        windows.values.forEach { $0.screenParametersChanged() }
    }

    func updateAnchors(_ anchors: [UUID: NoteWindowAnchor], displayID: CGDirectDisplayID) {
        for (id, anchor) in anchors {
            windows[id]?.considerAnchor(anchor)
        }
    }

    // MARK: - Dictation

    func toggleDictation(noteID: UUID) {
        if let activeID = dictatingNoteID {
            if activeID == noteID {
                stopDictation()
            } else {
                Task {
                    await finishDictation()
                    startDictation(noteID: noteID)
                }
            }
        } else {
            startDictation(noteID: noteID)
        }
    }

    func stopDictation() {
        guard dictatingNoteID != nil else { return }
        dictationStartTask?.cancel()
        Task { await finishDictation() }
    }

    private func startDictation(noteID: UUID) {
        guard dictatingNoteID == nil, let bridge = windows[noteID]?.bridge else { return }
        dictatingNoteID = noteID
        dictationState = .preparing
        audioLevel = 0
        refreshWindows()
        dictationStartTask = Task {
            let readiness = await dictation.checkProviderReadiness()
            guard !Task.isCancelled else { return }
            guard readiness.isReady else {
                dictatingNoteID = nil
                dictationState = .idle
                refreshWindows()
                UserDefaults.standard.set(SettingsSection.dictation.rawValue, forKey: "settings.selectedPane")
                NotificationCenter.default.post(name: .pocketStackOpenSettings, object: nil)
                NotificationCenter.default.post(name: .pocketStackVoiceNoteWarning, object: readiness.reason)
                return
            }
            guard dictatingNoteID == noteID, windows[noteID] != nil else { return }

            dictation.beginPreparing()
            do {
                try await dictation.start(
                    noteID: noteID,
                    bridge: bridge,
                    onAudioLevel: { [weak self] level in
                        guard self?.dictatingNoteID == noteID else { return }
                        self?.audioLevel = level
                        self?.refreshWindows()
                    }
                ) { [weak self] state in
                    guard self?.dictatingNoteID == noteID else { return }
                    self?.dictationState = state
                    if state == .idle {
                        self?.dictatingNoteID = nil
                        self?.audioLevel = 0
                    }
                    self?.refreshWindows()
                }
            } catch is CancellationError {
                guard dictatingNoteID == noteID else { return }
                bridge.finishDictation(discardInterim: false)
                dictationState = .idle
                dictatingNoteID = nil
                audioLevel = 0
                refreshWindows()
            } catch {
                bridge.finishDictation(discardInterim: true)
                dictationState = .failed(error.localizedDescription)
                audioLevel = 0
                refreshWindows()
                try? await Task.sleep(for: .seconds(3))
                guard dictatingNoteID == noteID else { return }
                dictationState = .idle
                dictatingNoteID = nil
                refreshWindows()
            }
        }
    }

    private func finishDictation() async {
        guard let noteID = dictatingNoteID else { return }
        dictationState = .finalizing
        audioLevel = 0
        windows[noteID]?.bridge.finishDictation(discardInterim: false)
        refreshWindows()
        await dictation.stop()
        guard dictatingNoteID == noteID else { return }
        dictationState = .idle
        dictatingNoteID = nil
        audioLevel = 0
        refreshWindows()
    }

    // MARK: - Model Observation

    private func notesDidChange() {
        for (id, controller) in Array(windows) {
            guard let note = model.note(id: id), !note.isArchived else {
                close(noteID: id)
                continue
            }
            controller.updateWindowAppearance(note: note)
            controller.updateWindowLevel(isPinned: note.isPinned)
        }
    }

    private func refreshWindows() {
        for (id, controller) in windows {
            controller.updatePresentation(
                isDictating: dictatingNoteID == id,
                state: dictationState,
                audioLevel: audioLevel
            )
        }
    }
}

// MARK: - NoteWindowControllerDelegate

extension NoteWindowCoordinator: NoteWindowControllerDelegate {
    func noteWindowDidMove(noteID: UUID, frame: CGRect) {
        windows[noteID]?.reevaluateAttachment()
        if windows[noteID]?.isAnchored == false {
            deckCoordinator?.prepareReattachment(noteID: noteID, windowFrame: frame)
        }
    }

    func noteWindowDidClose(noteID: UUID) {
        removeWindow(noteID: noteID, closeWindow: false)
    }

    func noteWindowAttachmentChanged(
        noteID: UUID,
        oldAnchor: NoteWindowAnchor?,
        newAnchor: NoteWindowAnchor?,
        attached: Bool
    ) {
        if let oldID = oldAnchor?.displayID, oldID != newAnchor?.displayID || !attached {
            deckCoordinator?.attachmentChanged(noteID: noteID, displayID: oldID, attached: false)
        }
        if attached, let newID = newAnchor?.displayID {
            deckCoordinator?.attachmentChanged(noteID: noteID, displayID: newID, attached: true)
        }
    }

    func noteWindowRequestClose(noteID: UUID) {
        close(noteID: noteID)
    }

    func noteWindowRequestToggleDictation(noteID: UUID) {
        toggleDictation(noteID: noteID)
    }
}
