import AppKit

@MainActor
final class DeckCoordinator: NSObject {
    private let model: AppModel
    private let preferences: AppPreferences
    private let noteWindows: NoteWindowCoordinator
    private var controllers: [CGDirectDisplayID: DeckController] = [:]
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel, preferences: AppPreferences, noteWindows: NoteWindowCoordinator) {
        self.model = model
        self.preferences = preferences
        self.noteWindows = noteWindows
        super.init()
    }

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        controllers.values.forEach { $0.invalidate() }
        controllers.removeAll()
    }

    func refreshAll() { rebuild() }

    var isDictating: Bool { noteWindows.isDictating }

    func stopDictationAll() { noteWindows.stopDictation() }

    func activate(_ controller: DeckController) {
        controllers.values.filter { $0 !== controller }.forEach { $0.collapse() }
    }

    func createAndExpand() {
        let note = model.create()
        let target = controllerUnderPointer() ?? controllers.values.first
        target?.openNote(note.id)
    }

    func expand(noteID: UUID) {
        (controllerUnderPointer() ?? controllers.values.first)?.openNote(noteID)
    }

    private func rebuild() {
        let screens = targetedScreens()
        let ids = Set(screens.compactMap(Self.displayID))
        let removed = controllers.filter { !ids.contains($0.key) }
        removed.values.forEach { $0.invalidate() }
        controllers = controllers.filter { ids.contains($0.key) }
        for screen in screens {
            guard let id = Self.displayID(screen), controllers[id] == nil else { continue }
            let controller = DeckController(displayID: id, model: model, preferences: preferences, noteWindows: noteWindows)
            controller.coordinator = self
            controllers[id] = controller
        }
        controllers.values.forEach { $0.refresh() }
        noteWindows.screenParametersChanged()
    }

    @objc private func screenParametersChanged() { rebuild() }

    func attachmentChanged(noteID: UUID, displayID: CGDirectDisplayID, attached: Bool) {
        controllers[displayID]?.attachmentChanged(noteID: noteID, attached: attached)
    }

    func prepareReattachment(noteID: UUID, windowFrame: CGRect) {
        for controller in controllers.values where controller.isNearFan(noteID: noteID, windowFrame: windowFrame) {
            controller.prepareReattachment(noteID: noteID)
            return
        }
    }

    private func targetedScreens() -> [NSScreen] {
        let target = preferences.displayTarget
        if target == "main" { return NSScreen.main.map { [$0] } ?? NSScreen.screens }
        if target.hasPrefix("id:"), let id = UInt32(target.dropFirst(3)) {
            return NSScreen.screens.filter { Self.displayID($0) == id }
        }
        return NSScreen.screens
    }

    private func controllerUnderPointer() -> DeckController? {
        let point = NSEvent.mouseLocation
        return controllers.values.first { $0.screen?.frame.contains(point) == true }
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
