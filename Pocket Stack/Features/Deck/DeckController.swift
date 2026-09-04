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
    var dictationState: DictationState = .idle
    let editorBridge = EditorBridge()
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
    private let dictation: DictationCoordinator
    private let panel = DeckPanel()
    private var tracking: DeckTrackingView!
    private var hosting: FirstMouseHostingView<DeckRootView>!
    private var shrinkWork: DispatchWorkItem?
    private let transitionScheduler = DeckTransitionScheduler()
    weak var coordinator: DeckCoordinator?

    init(displayID: CGDirectDisplayID, model: AppModel, preferences: AppPreferences, dictation: DictationCoordinator) {
        self.displayID = displayID
        self.model = model
        self.preferences = preferences
        self.dictation = dictation
        super.init()
        tracking = DeckTrackingView(frame: panel.contentView?.bounds ?? .zero)
        tracking.controller = self
        tracking.autoresizingMask = [.width, .height]
        hosting = FirstMouseHostingView(rootView: DeckRootView(model: model, preferences: preferences, state: viewState, controller: self))
        hosting.frame = tracking.bounds
        hosting.autoresizingMask = [.width, .height]
        tracking.addSubview(hosting)
        panel.contentView = tracking
        refresh()
        panel.orderFrontRegardless()
    }

    func invalidate() {
        transitionScheduler.cancelPending()
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
        hosting.rootView = DeckRootView(model: model, preferences: preferences, state: viewState, controller: self)
    }

    func updateLayout() {
        layout()
    }

    private var restTransitionWork: DispatchWorkItem?

    func scheduleTransitionToRest() {
        guard viewState.state == .fan,
              !viewState.fanInteractionActive,
              !viewState.isCollapsing,
              restTransitionWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.restTransitionWork = nil
            guard let self,
                  self.viewState.state == .fan,
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
        guard viewState.state == .fan else { return }
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

    func expand(_ id: UUID) {
        cancelTransitionToRest()
        cancelCollapseAnimation()
        guard viewState.dictationState == .idle else { return }
        transition(.expanded(id))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeExpanded() { transition(.fan) }
    func collapse() {
        guard viewState.dictationState == .idle else { return }
        transition(.rest)
    }

    func deleteNote(_ id: UUID) {
        if viewState.state.expandedID == id {
            closeExpanded()
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            model.delete(id: id)
        }
    }

    func createNote() {
        viewState.tabWindowStart = 0
        let note = model.create()
        expand(note.id)
    }

    func toggleDictation(noteID: UUID) {
        Task {
            if viewState.dictationState == .idle {
                viewState.dictationState = .preparing
                do {
                    try await dictation.start(noteID: noteID, bridge: viewState.editorBridge) { [weak self] state in
                        self?.viewState.dictationState = state
                    }
                } catch {
                    viewState.editorBridge.finishDictation(discardInterim: true)
                    viewState.dictationState = .failed(error.localizedDescription)
                    try? await Task.sleep(for: .seconds(3))
                    viewState.dictationState = .idle
                }
            } else {
                viewState.dictationState = .finalizing
                await dictation.stop()
            }
        }
    }

    func showContextMenu(_ event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(AppDelegate.newNote), keyEquivalent: "")
        menu.addItem(withTitle: "All Notes", action: #selector(AppDelegate.openAllNotes), keyEquivalent: "")
        menu.addItem(withTitle: "Archive", action: #selector(AppDelegate.openArchive), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Pocket Stack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = NSApp.delegate } }
        NSMenu.popUpContextMenu(menu, with: event, for: tracking)
    }

    private func transition(_ newState: DeckState) {
        let cancelledDeferredTransition = transitionScheduler.cancelPending()
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
            transitionScheduler.schedule(after: 2.0 / 60.0) { [weak self] in
                guard let self else { return }
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
