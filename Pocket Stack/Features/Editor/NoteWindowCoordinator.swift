import AppKit
import Observation
import SwiftUI

struct NoteWindowAnchor: Equatable {
    let displayID: CGDirectDisplayID
    let edge: DeckEdge
    let tabFrame: CGRect
}

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
            owner: self,
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

    fileprivate func windowDidMove(noteID: UUID, frame: CGRect) {
        windows[noteID]?.reevaluateAttachment()
        if windows[noteID]?.isAnchored == false {
            deckCoordinator?.prepareReattachment(noteID: noteID, windowFrame: frame)
        }
    }

    fileprivate func windowDidClose(noteID: UUID) {
        removeWindow(noteID: noteID, closeWindow: false)
    }

    fileprivate func attachmentChanged(
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
        windows.values.forEach { $0.updatePresentation() }
    }
}

@MainActor
private final class NoteWindowController: NSObject, NSWindowDelegate {
    let noteID: UUID
    let bridge = EditorBridge()
    private let model: AppModel
    private let preferences: AppPreferences
    private unowned let owner: NoteWindowCoordinator
    private let window: NotePanel
    private let presentation = NoteEditorPresentation()
    private var hosting: FirstMouseHostingView<NoteEditorView>!
    private var isClosing = false
    private var currentPinned: Bool?
    private(set) var anchor: NoteWindowAnchor?
    private(set) var isAnchored = false

    init(
        noteID: UUID,
        model: AppModel,
        preferences: AppPreferences,
        owner: NoteWindowCoordinator,
        initialAnchor: NoteWindowAnchor?
    ) {
        self.noteID = noteID
        self.model = model
        self.preferences = preferences
        self.owner = owner
        self.anchor = initialAnchor
        window = NotePanel(contentRect: .zero)
        super.init()
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("note-window-\(noteID.uuidString)")
        window.setFrame(Self.initialFrame(noteID: noteID, preferences: preferences, anchor: initialAnchor), display: false)
        clampToAvailableScreens()
        isAnchored = initialAnchor.map { Self.isFrame(window.frame, anchoredTo: $0, threshold: Self.attachDistance) } ?? false
        persistAttachmentState()
        hosting = FirstMouseHostingView(rootView: makeRootView())
        hosting.frame = window.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.alignCloseButton()
        if let note = model.note(id: noteID) {
            updateWindowAppearance(note: note)
        }
        updateWindowLevel(isPinned: model.note(id: noteID)?.isPinned == true)
    }

    func show() {
        presentWindow()
    }

    func focus() {
        presentWindow()
    }

    private func presentWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.alignCloseButton()
        window.orderFrontRegardless()
    }

    func closeWindow() {
        guard !isClosing else { return }
        isClosing = true
        persistFrame()
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    func updateAnchor(_ newAnchor: NoteWindowAnchor) {
        let previous = anchor
        anchor = newAnchor
        let wasAnchored = isAnchored
        if !isAnchored {
            isAnchored = Self.isFrame(window.frame, anchoredTo: newAnchor, threshold: Self.attachDistance)
        }
        if wasAnchored != isAnchored || previous?.displayID != newAnchor.displayID {
            owner.attachmentChanged(
                noteID: noteID,
                oldAnchor: previous,
                newAnchor: newAnchor,
                attached: isAnchored
            )
        }
        persistAttachmentState()
    }

    func considerAnchor(_ newAnchor: NoteWindowAnchor) {
        if anchor?.displayID == newAnchor.displayID {
            updateAnchor(newAnchor)
        } else if !isAnchored, Self.isFrame(window.frame, anchoredTo: newAnchor, threshold: Self.attachDistance) {
            updateAnchor(newAnchor)
        }
    }

    func reevaluateAttachment() {
        guard let anchor else { return }
        let wasAnchored = isAnchored
        let threshold = isAnchored ? Self.detachDistance : Self.attachDistance
        isAnchored = Self.isFrame(window.frame, anchoredTo: anchor, threshold: threshold)
        if wasAnchored != isAnchored {
            owner.attachmentChanged(
                noteID: noteID,
                oldAnchor: anchor,
                newAnchor: anchor,
                attached: isAnchored
            )
            persistAttachmentState()
        }
    }

    func updateWindowLevel(isPinned: Bool) {
        guard currentPinned != isPinned else { return }
        currentPinned = isPinned
        window.level = isPinned ? .statusBar : .normal
        window.collectionBehavior = isPinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.managed]
    }

    func updateWindowAppearance(note: Note) {
        window.backgroundColor = NSColor(NotePalette.color(for: note).paper)
    }

    func clampToAvailableScreens() {
        guard !NSScreen.screens.isEmpty else { return }
        let current = window.frame
        let target = NSScreen.screens.first(where: { $0.frame.intersects(current) })
            ?? NSScreen.screens.min(by: { Self.distance(from: current, to: $0.frame) < Self.distance(from: current, to: $1.frame) })
        guard let visible = target?.visibleFrame else { return }
        var clamped = current
        clamped.size.width = min(max(clamped.width, 320), visible.width)
        clamped.size.height = min(max(clamped.height, 240), visible.height)
        clamped.origin.x = min(max(clamped.minX, visible.minX), visible.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.minY, visible.minY), visible.maxY - clamped.height)
        if clamped != current { window.setFrame(clamped, display: true) }
    }

    func screenParametersChanged() {
        clampToAvailableScreens()
        guard let anchor,
              !NSScreen.screens.contains(where: { DeckCoordinator.displayID($0) == anchor.displayID }) else {
            reevaluateAttachment()
            return
        }
        let wasAnchored = isAnchored
        isAnchored = false
        self.anchor = nil
        persistAttachmentState()
        if wasAnchored {
            owner.attachmentChanged(noteID: noteID, oldAnchor: anchor, newAnchor: nil, attached: false)
        }
        owner.windowDidMove(noteID: noteID, frame: window.frame)
    }

    func windowDidMove(_ notification: Notification) {
        owner.windowDidMove(noteID: noteID, frame: window.frame)
    }

    fileprivate func windowDragEnded() {
        alignToBackingPixels()
        persistFrame()
        reevaluateAttachment()
        hosting.needsDisplay = true
        hosting.displayIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        persistFrame()
        reevaluateAttachment()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        owner.windowDidClose(noteID: noteID)
    }

    private func makeRootView() -> NoteEditorView {
        let noteID = self.noteID
        return NoteEditorView(
            noteID: noteID,
            model: model,
            preferences: preferences,
            bridge: bridge,
            presentation: presentation,
            onClose: { [weak owner] in owner?.close(noteID: noteID) },
            onMicrophone: { [weak owner] in owner?.toggleDictation(noteID: noteID) }
        )
    }

    func updatePresentation() {
        let noteIsDictating = owner.dictatingNoteID == noteID
        presentation.dictationState = noteIsDictating ? owner.dictationState : .idle
        presentation.audioLevel = noteIsDictating ? owner.audioLevel : 0
    }

    private static func initialFrame(noteID: UUID, preferences: AppPreferences, anchor: NoteWindowAnchor?) -> CGRect {
        let defaults = UserDefaults.standard
        let detachedKey = "note.window.detached.\(noteID.uuidString)"
        if anchor == nil || defaults.bool(forKey: detachedKey),
           let saved = defaults.string(forKey: "note.window.frame.\(noteID.uuidString)") {
            let frame = NSRectFromString(saved)
            if frame.width > 0, frame.height > 0 { return frame }
        }
        let size = preferences.noteSize
        guard let anchor else {
            let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: size.width, height: size.height)
            return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        }
        let gap: CGFloat = 10
        switch anchor.edge {
        case .left:
            return CGRect(x: anchor.tabFrame.maxX + gap, y: anchor.tabFrame.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return CGRect(x: anchor.tabFrame.minX - gap - size.width, y: anchor.tabFrame.midY - size.height / 2, width: size.width, height: size.height)
        case .bottom:
            return CGRect(x: anchor.tabFrame.midX - size.width / 2, y: anchor.tabFrame.maxY + gap, width: size.width, height: size.height)
        }
    }

    private var frameKey: String { "note.window.frame.\(noteID.uuidString)" }
    private var detachedKey: String { "note.window.detached.\(noteID.uuidString)" }

    private func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
    }

    private func alignToBackingPixels() {
        let scale = window.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let alignedOrigin = CGPoint(
            x: (window.frame.origin.x * scale).rounded() / scale,
            y: (window.frame.origin.y * scale).rounded() / scale
        )
        if alignedOrigin != window.frame.origin {
            window.setFrameOrigin(alignedOrigin)
        }
    }

    private func persistAttachmentState() {
        UserDefaults.standard.set(!isAnchored, forKey: detachedKey)
    }

    private static let attachDistance: CGFloat = 28
    private static let detachDistance: CGFloat = 52

    private static func isFrame(_ frame: CGRect, anchoredTo anchor: NoteWindowAnchor, threshold: CGFloat) -> Bool {
        let parallelOverlap: Bool
        let distance: CGFloat
        switch anchor.edge {
        case .left:
            distance = abs(frame.minX - anchor.tabFrame.maxX)
            parallelOverlap = frame.minY - threshold <= anchor.tabFrame.midY && anchor.tabFrame.midY <= frame.maxY + threshold
        case .right:
            distance = abs(frame.maxX - anchor.tabFrame.minX)
            parallelOverlap = frame.minY - threshold <= anchor.tabFrame.midY && anchor.tabFrame.midY <= frame.maxY + threshold
        case .bottom:
            distance = abs(frame.minY - anchor.tabFrame.maxY)
            parallelOverlap = frame.minX - threshold <= anchor.tabFrame.midX && anchor.tabFrame.midX <= frame.maxX + threshold
        }
        return distance <= threshold && parallelOverlap
    }

    private static func distance(from lhs: CGRect, to rhs: CGRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }
}

private final class NotePanel: NSWindow {
    private var nativeCloseButtonOrigin: CGPoint?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else {
            return false
        }
        if flags == .command {
            switch characters {
            case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "z": return NSApp.sendAction(#selector(PocketTextView.undo(_:)), to: nil, from: self)
            case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "w": performClose(nil); return true
            default: break
            }
        } else if flags == [.command, .shift], characters == "z" {
            return NSApp.sendAction(#selector(PocketTextView.redo(_:)), to: nil, from: self)
        }
        return false
    }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Note"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        if let closeButton = standardWindowButton(.closeButton) {
            nativeCloseButtonOrigin = closeButton.frame.origin
            alignCloseButton()
        }
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        minSize = CGSize(width: 320, height: 240)
        animationBehavior = .none
    }

    func alignCloseButton() {
        guard let closeButton = standardWindowButton(.closeButton),
              let nativeCloseButtonOrigin else { return }
        closeButton.setFrameOrigin(
            CGPoint(x: nativeCloseButtonOrigin.x, y: nativeCloseButtonOrigin.y - 3)
        )
    }
}

struct NativeWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
            (window?.delegate as? NoteWindowController)?.windowDragEnded()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
