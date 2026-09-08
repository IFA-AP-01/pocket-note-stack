import AppKit
import SwiftUI

@MainActor
protocol NoteWindowControllerDelegate: AnyObject {
    func noteWindowDidMove(noteID: UUID, frame: CGRect)
    func noteWindowDidClose(noteID: UUID)
    func noteWindowAttachmentChanged(
        noteID: UUID,
        oldAnchor: NoteWindowAnchor?,
        newAnchor: NoteWindowAnchor?,
        attached: Bool
    )
    func noteWindowRequestClose(noteID: UUID)
    func noteWindowRequestToggleDictation(noteID: UUID)
}

@MainActor
final class NoteWindowController: NSObject, NSWindowDelegate {
    let noteID: UUID
    let bridge = EditorBridge()
    private let model: AppModel
    private let preferences: AppPreferences
    private weak var delegate: NoteWindowControllerDelegate?
    private let window: NotePanel
    private let presentation = NoteEditorPresentation()
    private var hosting: FirstMouseHostingView<NoteEditorView>!
    private var moveSettledWorkItem: DispatchWorkItem?
    private var isClosing = false
    private var currentPinned: Bool?
    private(set) var anchor: NoteWindowAnchor?
    private(set) var isAnchored = false

    init(
        noteID: UUID,
        model: AppModel,
        preferences: AppPreferences,
        delegate: NoteWindowControllerDelegate,
        initialAnchor: NoteWindowAnchor?
    ) {
        self.noteID = noteID
        self.model = model
        self.preferences = preferences
        self.delegate = delegate
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
        applyWindowLevel()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func closeWindow() {
        guard !isClosing else { return }
        isClosing = true
        moveSettledWorkItem?.cancel()
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
            delegate?.noteWindowAttachmentChanged(
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
            delegate?.noteWindowAttachmentChanged(
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
        applyWindowLevel()
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
            delegate?.noteWindowAttachmentChanged(noteID: noteID, oldAnchor: anchor, newAnchor: nil, attached: false)
        }
        delegate?.noteWindowDidMove(noteID: noteID, frame: window.frame)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        scheduleMoveSettled()
    }

    func windowDidResize(_ notification: Notification) {
        persistFrame()
        reevaluateAttachment()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyWindowLevel()
    }

    func windowDidResignKey(_ notification: Notification) {
        applyWindowLevel()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        moveSettledWorkItem?.cancel()
        persistFrame()
        delegate?.noteWindowDidClose(noteID: noteID)
    }

    // MARK: - Presentation

    private func makeRootView() -> NoteEditorView {
        let noteID = self.noteID
        return NoteEditorView(
            noteID: noteID,
            model: model,
            preferences: preferences,
            bridge: bridge,
            presentation: presentation,
            onClose: { [weak self] in
                self?.delegate?.noteWindowRequestClose(noteID: noteID)
            },
            onMicrophone: { [weak self] in
                self?.delegate?.noteWindowRequestToggleDictation(noteID: noteID)
            }
        )
    }

    func updatePresentation(isDictating: Bool, state: DictationState, audioLevel: Float) {
        presentation.dictationState = isDictating ? state : .idle
        presentation.audioLevel = isDictating ? audioLevel : 0
    }

    // MARK: - Frame Positioning & Persistence

    private static func initialFrame(noteID: UUID, preferences: AppPreferences, anchor: NoteWindowAnchor?) -> CGRect {
        let defaults = UserDefaults.standard
        let size = preferences.noteSize
        if let saved = defaults.string(forKey: "note.window.frame.\(noteID.uuidString)") {
            let frame = NSRectFromString(saved)
            if frame.width > 0, frame.height > 0 {
                return CGRect(origin: frame.origin, size: size)
            }
        }
        let screen = anchor.flatMap { target in
            NSScreen.screens.first { DeckCoordinator.displayID($0) == target.displayID }
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let center: CGPoint
        switch anchor?.edge {
        case .left:
            center = CGPoint(
                x: visible.minX + visible.width * 0.25,
                y: visible.minY + visible.height * 0.65
            )
        case .right:
            center = CGPoint(
                x: visible.minX + visible.width * 0.75,
                y: visible.minY + visible.height * 0.65
            )
        case .bottom:
            center = CGPoint(
                x: visible.midX,
                y: visible.minY + visible.height * 0.25
            )
        case nil:
            center = CGPoint(x: visible.midX, y: visible.midY)
        }
        let frame = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return frame
    }

    private var frameKey: String { "note.window.frame.\(noteID.uuidString)" }
    private var detachedKey: String { "note.window.detached.\(noteID.uuidString)" }

    private func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
    }

    private func applyWindowLevel() {
        window.level = currentPinned == true ? .floating : .normal
    }

    private func scheduleMoveSettled() {
        moveSettledWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.moveSettledWorkItem = nil
            self.persistFrame()
            self.delegate?.noteWindowDidMove(noteID: self.noteID, frame: self.window.frame)
        }
        moveSettledWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
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
