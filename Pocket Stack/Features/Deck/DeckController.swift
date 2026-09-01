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
    var showAll = false
    var revealTick = 0
    var dictationState: DictationState = .idle
    let editorBridge = EditorBridge()

    var fanVisible: Bool { state != .rest }
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
    private var idleTimer: Timer?
    private var outsideMonitor: Any?
    private var shrinkWork: DispatchWorkItem?
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
        shrinkWork?.cancel()
        idleTimer?.invalidate()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
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

    func pointerEntered() {
        guard viewState.state == .rest else { return }
        coordinator?.activate(self)
        transition(.fan)
    }

    func pointerExited() {
        guard viewState.state == .fan else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.viewState.state == .fan, let screen = self.screen else { return }
            let edgeWidth = max(70, 70 * self.preferences.deckScale)
            let hot = self.preferences.edge == .right
                ? NSRect(x: screen.frame.maxX - edgeWidth, y: screen.frame.minY, width: edgeWidth, height: screen.frame.height)
                : NSRect(x: screen.frame.minX, y: screen.frame.minY, width: edgeWidth, height: screen.frame.height)
            if !hot.contains(NSEvent.mouseLocation) { self.transition(.rest) }
        }
    }

    func expand(_ id: UUID) {
        guard viewState.dictationState == .idle else { return }
        transition(.expanded(id))
        panel.makeKeyAndOrderFront(nil)
    }

    func closeExpanded() { transition(.fan) }
    func collapse() { if viewState.dictationState == .idle { transition(.rest) } }

    func createNote() {
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
        let oldState = viewState.state
        guard oldState != newState else { return }
        shrinkWork?.cancel()
        shrinkWork = nil

        if newState.rank >= oldState.rank {
            // Fan and editor share one final panel size. Resize first, then let
            // SwiftUI animate content on a later display frame to avoid relayout
            // jitter that looks like the note flying in from mid-screen.
            layout(for: newState)
            if newState == .fan { viewState.revealTick &+= 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 / 60.0) { [weak self] in
                guard let self else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    self.viewState.state = newState
                }
                self.configureMonitors()
                self.configureIdleTimer()
            }
        } else if newState == .rest {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
                viewState.state = newState
            }
            let work = DispatchWorkItem { [weak self] in self?.layout(for: .rest) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: work)
            configureMonitors()
            configureIdleTimer()
        } else {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                viewState.state = newState
            }
            layout(for: newState)
            configureMonitors()
            configureIdleTimer()
        }
        if newState == .rest { viewState.showAll = false }
    }

    private func layout() { layout(for: viewState.state) }

    private func layout(for state: DeckState) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let full = screen.frame
        let width: CGFloat
        let height: CGFloat
        let y: CGFloat
        switch state {
        case .rest:
            width = max(14, preferences.edgeWidth)
            height = min(420, max(54, CGFloat(max(model.activeNotes.count, 1)) * 19 + 20))
            y = visible.midY - height / 2
        case .fan, .expanded:
            width = preferences.noteSize.width + 84
            height = visible.height
            y = visible.minY
        }
        let x = preferences.edge == .right ? full.maxX - width : full.minX
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func configureIdleTimer() {
        idleTimer?.invalidate()
        guard viewState.state != .rest else { return }
        var lastActivity = Date()
        var lastPointer = NSEvent.mouseLocation
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.viewState.dictationState == .idle else { return }
                let pointer = NSEvent.mouseLocation
                if self.viewState.state == .fan, !self.fanHotZone.contains(pointer) {
                    self.transition(.rest)
                    return
                }
                if abs(pointer.x - lastPointer.x) > 2 || abs(pointer.y - lastPointer.y) > 2 {
                    lastPointer = pointer
                    lastActivity = .now
                }
                let idle = Date().timeIntervalSince(lastActivity)
                switch self.viewState.state {
                case .fan where idle > 4: self.transition(.rest)
                case .expanded(let id) where idle > 60 && self.model.note(id: id)?.isPinned != true: self.transition(.rest)
                default: break
                }
            }
        }
    }

    private var fanHotZone: NSRect {
        guard let screen else { return .zero }
        let width = max(72, 72 * preferences.deckScale)
        return preferences.edge == .right
            ? NSRect(x: screen.frame.maxX - width, y: screen.frame.minY, width: width, height: screen.frame.height)
            : NSRect(x: screen.frame.minX, y: screen.frame.minY, width: width, height: screen.frame.height)
    }

    private func configureMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        guard case .expanded = viewState.state else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.viewState.dictationState == .idle else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.transition(.rest) }
            }
        }
    }
}
