import AppKit

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private weak var window: NSWindow?

    private init() {}

    func discoverSettingsWindow() -> NSWindow? {
        if let window {
            return window
        }
        let found = NSApp.windows.first { candidate in
            guard !(candidate is DeckPanel) else { return false }
            let title = candidate.title.lowercased()
            let id = candidate.identifier?.rawValue.lowercased() ?? ""
            return title == "settings" || id == "settings" || title.contains("settings") || id.contains("settings")
        }
        if let found {
            found.isReleasedWhenClosed = false
            self.window = found
        }
        return found
    }

    func present(fromMenu: Bool = true, openWindow: () -> Void) {
        if let existing = discoverSettingsWindow() {
            if fromMenu {
                AppWindowActivation.presentAfterMenuDismisses(existing)
            } else {
                AppWindowActivation.present(existing)
            }
            return
        }

        openWindow()

        if fromMenu {
            AppWindowActivation.performAfterMenuDismisses { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                if let target = self?.discoverSettingsWindow() {
                    target.makeKeyAndOrderFront(nil)
                }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if let target = discoverSettingsWindow() {
                target.makeKeyAndOrderFront(nil)
            }
        }
    }
}
