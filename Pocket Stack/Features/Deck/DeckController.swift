import AppKit
import Observation
import SwiftUI

enum DeckState: Equatable {
    case rest
    case fan
    case expanded(UUID)

    var rank: Int {
        switch self {
        case .rest: 0
        case .fan: 1
        case .expanded: 2
        }
    }

    var expandedID: UUID? {
        if case .expanded(let id) = self { return id }
        return nil
    }
}

@MainActor
@Observable
final class DeckViewState {
    var state: DeckState = .rest
    var tabWindowStart = 0
    var revealTick = 0
    var fanInteractionActive = false
    var isCollapsing = false
}

@MainActor
private final class DeckTransitionScheduler {
    private var generation = 0
    private var hasPendingAction = false

    @discardableResult
    func cancelPending() -> Bool {
        let cancelledAction = hasPendingAction
        hasPendingAction = false
        generation &+= 1
        return cancelledAction
    }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        generation &+= 1
        hasPendingAction = true
        let scheduledGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.generation == scheduledGeneration else { return }
            self?.hasPendingAction = false
            action()
        }
    }
}


@MainActor
final class DeckController: NSObject {
    let displayID: CGDirectDisplayID
    let viewState = DeckViewState()
    private let model: AppModel
    private let preferences: AppPreferences
    private let noteWindows: NoteWindowCoordinator
    private let panel = DeckPanel()
    private var tracking: DeckTrackingView!
    private var hosting: FirstMouseHostingView<DeckRootView>!
    private var shrinkWork: DispatchWorkItem?
    private let transitionScheduler = DeckTransitionScheduler()
    private var tabFrames: [UUID: CGRect] = [:]
    private var anchoredNoteIDs: Set<UUID> = []
    private var pendingOpenNoteIDs: Set<UUID> = []
    private var pendingState: DeckState?
    weak var coordinator: DeckCoordinator?

    init(displayID: CGDirectDisplayID, model: AppModel, preferences: AppPreferences, noteWindows: NoteWindowCoordinator) {
        self.displayID = displayID
        self.model = model
        self.preferences = preferences
        self.noteWindows = noteWindows
        super.init()
        tracking = DeckTrackingView(frame: panel.contentView?.bounds ?? .zero)
        tracking.controller = self
        tracking.autoresizingMask = [.width, .height]
        hosting = FirstMouseHostingView(rootView: DeckRootView(model: model, preferences: preferences, noteWindows: noteWindows, state: viewState, controller: self))
        hosting.frame = tracking.bounds
        hosting.autoresizingMask = [.width, .height]
        tracking.addSubview(hosting)
        panel.contentView = tracking
        refresh()
        panel.orderFrontRegardless()
    }

    func invalidate() {
        transitionScheduler.cancelPending()
        pendingState = nil
        pendingOpenNoteIDs.removeAll()
        shrinkWork?.cancel()
        restTransitionWork?.cancel()
        panel.orderOut(nil)
    }

    var screen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }

    func refresh() {
        panel.level = preferences.showOverFullScreen ? .statusBar : .floating
        layout()
        hosting.rootView = DeckRootView(model: model, preferences: preferences, noteWindows: noteWindows, state: viewState, controller: self)
    }

    func updateLayout() {
        layout()
    }

    private var restTransitionWork: DispatchWorkItem?

    func scheduleTransitionToRest() {
        guard viewState.state == .fan,
              anchoredNoteIDs.isEmpty,
              !viewState.fanInteractionActive,
              !viewState.isCollapsing,
              restTransitionWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.restTransitionWork = nil
            guard let self,
                  self.viewState.state == .fan,
                  self.anchoredNoteIDs.isEmpty,
                  !self.viewState.fanInteractionActive,
                  !self.viewState.isCollapsing else { return }
            self.transition(.rest)
        }
        restTransitionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func cancelTransitionToRest() {
        restTransitionWork?.cancel()
        restTransitionWork = nil
    }

    func pointerEntered() {
        cancelTransitionToRest()
        cancelCollapseAnimation()
        guard viewState.state == .rest else { return }
        coordinator?.activate(self)
        transition(.fan)
    }

    func pointerExited() {
        guard viewState.state == .fan, anchoredNoteIDs.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.viewState.state == .fan else { return }
            self.viewState.fanInteractionActive = false
            self.scheduleTransitionToRest()
        }
    }

    func fanInteractionChanged(_ active: Bool) {
        guard viewState.state == .fan else { return }
        viewState.fanInteractionActive = active
        if active {
            cancelTransitionToRest()
            cancelCollapseAnimation()
        } else {
            scheduleTransitionToRest()
        }
    }

    func openNote(_ id: UUID) {
        cancelTransitionToRest()
        cancelCollapseAnimation()
        if noteWindows.isOpen(noteID: id) {
            noteWindows.open(noteID: id, anchor: nil)
            return
        }
        ensureTabVisible(id)
        transition(.fan)
        if let anchor = anchor(for: id), !isTabExpanded(tabFrames[id]) {
            noteWindows.open(noteID: id, anchor: anchor)
        } else {
            pendingOpenNoteIDs.insert(id)
        }
    }

    func collapse() {
        guard anchoredNoteIDs.isEmpty else { return }
        transition(.rest)
    }

    func deleteNote(_ id: UUID) {
        pendingOpenNoteIDs.remove(id)
        noteWindows.close(noteID: id)
        withAnimation(.easeInOut(duration: 0.25)) {
            model.delete(id: id)
        }
    }

    func createNote() {
        viewState.tabWindowStart = 0
        let note = model.create()
        openNote(note.id)
    }

    @objc func stopDictationAction() {
        noteWindows.stopDictation()
    }

    func showContextMenu(_ event: NSEvent) {
        let menu = NSMenu()
        if noteWindows.isDictating {
            let stopItem = menu.addItem(withTitle: "Stop Dictation", action: #selector(stopDictationAction), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "New Note", action: #selector(AppDelegate.newNote), keyEquivalent: "")
        menu.addItem(withTitle: "All Notes", action: #selector(AppDelegate.openAllNotes), keyEquivalent: "")
        menu.addItem(withTitle: "Archive", action: #selector(AppDelegate.openArchive), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Pocket Stack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.items.forEach {
            if $0.action != #selector(NSApplication.terminate(_:)) && $0.target == nil {
                $0.target = NSApp.delegate
            }
        }
        NSMenu.popUpContextMenu(menu, with: event, for: tracking)
    }

    func noteTabFrameChanged(noteID: UUID, localFrame: CGRect?) {
        guard let localFrame else {
            tabFrames.removeValue(forKey: noteID)
            return
        }
        guard let screen else { return }
        let converted = panel.convertToScreen(hosting.convert(localFrame, to: nil))
        let frame = stableTabFrame(converted, on: screen)
        guard tabFrames[noteID] != frame else { return }
        tabFrames[noteID] = frame

        let anchor = NoteWindowAnchor(displayID: displayID, edge: preferences.edge, tabFrame: frame)
        noteWindows.updateAnchors([noteID: anchor], displayID: displayID)
        if pendingOpenNoteIDs.contains(noteID), !isTabExpanded(frame) {
            pendingOpenNoteIDs.remove(noteID)
            noteWindows.open(noteID: noteID, anchor: anchor)
        }
    }

    func attachmentChanged(noteID: UUID, attached: Bool) {
        if attached {
            anchoredNoteIDs.insert(noteID)
            cancelTransitionToRest()
            cancelCollapseAnimation()
            ensureTabVisible(noteID)
            transition(.fan)
        } else {
            anchoredNoteIDs.remove(noteID)
            if anchoredNoteIDs.isEmpty, !viewState.fanInteractionActive {
                scheduleTransitionToRest()
            }
        }
    }

    func isNearFan(noteID: UUID, windowFrame: CGRect) -> Bool {
        let threshold: CGFloat = 100
        if let tabFrame = tabFrames[noteID] {
            switch preferences.edge {
            case .left:
                return abs(windowFrame.minX - tabFrame.maxX) <= threshold
                    && windowFrame.minY - threshold <= tabFrame.midY
                    && tabFrame.midY <= windowFrame.maxY + threshold
            case .right:
                return abs(windowFrame.maxX - tabFrame.minX) <= threshold
                    && windowFrame.minY - threshold <= tabFrame.midY
                    && tabFrame.midY <= windowFrame.maxY + threshold
            case .bottom:
                return abs(windowFrame.minY - tabFrame.maxY) <= threshold
                    && windowFrame.minX - threshold <= tabFrame.midX
                    && tabFrame.midX <= windowFrame.maxX + threshold
            }
        }
        guard let screen else { return false }
        switch preferences.edge {
        case .left: return abs(windowFrame.minX - (screen.frame.minX + DeckMetrics.Fan.crossAxisSize)) <= threshold
        case .right: return abs(windowFrame.maxX - (screen.frame.maxX - DeckMetrics.Fan.crossAxisSize)) <= threshold
        case .bottom: return abs(windowFrame.minY - (screen.visibleFrame.minY + DeckMetrics.Fan.crossAxisSize)) <= threshold
        }
    }

    func prepareReattachment(noteID: UUID) {
        guard model.activeNotes.contains(where: { $0.id == noteID }) else { return }
        cancelTransitionToRest()
        ensureTabVisible(noteID)
        transition(.fan)
    }

    private func ensureTabVisible(_ noteID: UUID) {
        guard let index = model.activeNotes.firstIndex(where: { $0.id == noteID }) else { return }
        let window = DeckTabWindow(startIndex: viewState.tabWindowStart, noteCount: model.activeNotes.count)
        if index < window.visibleRange.lowerBound {
            viewState.tabWindowStart = index
        } else if index >= window.visibleRange.upperBound {
            viewState.tabWindowStart = max(0, index - DeckTabWindow.capacity + 1)
        }
    }

    private func anchor(for noteID: UUID) -> NoteWindowAnchor? {
        guard let frame = tabFrames[noteID] else { return nil }
        return NoteWindowAnchor(displayID: displayID, edge: preferences.edge, tabFrame: frame)
    }

    private func stableTabFrame(_ frame: CGRect, on screen: NSScreen) -> CGRect {
        let depth = preferences.style == .labelled
            ? DeckMetrics.Tab.closedDepthLabelled
            : DeckMetrics.Tab.closedDepthUnlabelled
        switch preferences.edge {
        case .left:
            return CGRect(x: screen.frame.minX, y: frame.minY, width: depth, height: frame.height)
        case .right:
            return CGRect(x: screen.frame.maxX - depth, y: frame.minY, width: depth, height: frame.height)
        case .bottom:
            return CGRect(x: frame.minX, y: screen.visibleFrame.minY, width: frame.width, height: depth)
        }
    }

    private func isTabExpanded(_ frame: CGRect?) -> Bool {
        guard let frame else { return true }
        let closedLength = preferences.style == .labelled
            ? DeckMetrics.Tab.closedLengthLabelled
            : DeckMetrics.Tab.closedLengthUnlabelled
        switch preferences.edge {
        case .left, .right: return frame.height > closedLength + 2
        case .bottom: return frame.width > closedLength + 2
        }
    }

    private func transition(_ newState: DeckState) {
        if pendingState == newState { return }
        let cancelledDeferredTransition = transitionScheduler.cancelPending()
        pendingState = nil
        let oldState = viewState.state
        guard oldState != newState else {
            if cancelledDeferredTransition { layout(for: newState) }
            return
        }
        if newState == .rest, viewState.isCollapsing { return }
        if newState != .rest { cancelCollapseAnimation() }
        shrinkWork?.cancel()
        shrinkWork = nil

        if newState.rank >= oldState.rank {
            layout(for: newState)
            if newState == .fan { viewState.revealTick &+= 1 }
            pendingState = newState
            transitionScheduler.schedule(after: 2.0 / 60.0) { [weak self] in
                guard let self else { return }
                guard self.pendingState == newState else { return }
                self.pendingState = nil
                withAnimation(.easeOut(duration: 0.3)) {
                    self.viewState.state = newState
                }
            }
        } else if newState == .rest {
            cancelTransitionToRest()
            viewState.fanInteractionActive = false
            withAnimation(.easeIn(duration: 0.18)) { viewState.isCollapsing = true }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.viewState.isCollapsing else { return }
                self.shrinkWork = nil
                self.layout(for: .rest)
                withAnimation(.easeOut(duration: 0.22)) {
                    self.viewState.state = .rest
                    self.viewState.isCollapsing = false
                }
                self.viewState.tabWindowStart = 0
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
            return
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                viewState.state = newState
            }
            layout(for: newState)
        }
    }

    private func cancelCollapseAnimation() {
        guard viewState.isCollapsing else { return }
        shrinkWork?.cancel()
        shrinkWork = nil
        withAnimation(.easeOut(duration: 0.12)) { viewState.isCollapsing = false }
    }

    private func layout() { layout(for: viewState.state) }

    private func layout(for state: DeckState) {
        guard let screen else { return }
        panel.setFrame(
            DeckLayout.panelFrame(
                state: state,
                edge: preferences.edge,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                noteSize: preferences.noteSize,
                noteCount: model.activeNotes.count,
                edgeWidth: preferences.edgeWidth
            ),
            display: true
        )
    }

}
