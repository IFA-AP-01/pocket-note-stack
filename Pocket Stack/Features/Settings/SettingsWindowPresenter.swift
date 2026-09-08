import AppKit

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private weak var window: NSWindow?

    private init() {}

    func register(_ window: NSWindow?) {
        guard let window else { return }
        window.isReleasedWhenClosed = false
        self.window = window
    }

    func discoverSettingsWindow() -> NSWindow? {
        if let window {
            return window
        }
        let found = NSApp.windows.first { candidate in
            guard !(candidate is DeckPanel), !(candidate is NotePanel), !(candidate is LibraryWindow) else { return false }
            let title = candidate.title.lowercased()
            let id = candidate.identifier?.rawValue.lowercased() ?? ""
            return id == "settings" || id.contains("settings") || title == "settings" || title.contains("settings")
        }
        if let found {
            found.isReleasedWhenClosed = false
            self.window = found
        }
        return found
    }

    func present(fromMenu: Bool = true, openWindow: () -> Void) {
        // Always invoke openWindow to ensure the SwiftUI scene is opened/restored
        openWindow()

        // If window is already known, present it immediately with menu-dismissal protection
        if let existing = discoverSettingsWindow() {
            if fromMenu {
                AppWindowActivation.presentAfterMenuDismisses(existing)
            } else {
                AppWindowActivation.present(existing)
            }
            return
        }

        // On first presentation, poll briefly until SwiftUI completes attaching the window
        Task { @MainActor [weak self] in
            for delay in [30, 80, 150] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, let target = self.discoverSettingsWindow() else { continue }
                if fromMenu {
                    AppWindowActivation.presentAfterMenuDismisses(target)
                } else {
                    AppWindowActivation.present(target)
                }
                return
            }
        }
    }
}
