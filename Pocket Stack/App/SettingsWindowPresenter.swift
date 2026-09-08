import AppKit
import SwiftUI

extension Notification.Name {
    static let pocketStackOpenSettings = Notification.Name("PocketStackOpenSettings")
    static let pocketStackVoiceNoteWarning = Notification.Name("PocketStackVoiceNoteWarning")
}

@MainActor
enum AppWindowActivation {
    static func present(_ window: NSWindow) {
        // Elevate level temporarily so the window punches through other applications
        // (e.g. Chrome, Safari) immediately (0ms), even before AppKit completes menu dismissal.
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        // After AppKit's menu dismissal cycle finishes and attempts to restore the previous app (~100-140ms),
        // settle the window back to .normal level and re-assert frontmost key focus.
        Task { @MainActor [weak window] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let window, window.isVisible else { return }
            window.level = .normal
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    static func presentAfterMenuDismisses(_ window: NSWindow) {
        present(window)
    }
}

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private weak var window: NSWindow?
    private var pendingPresentation = false
    private var presentationTask: Task<Void, Never>?

    private init() {}

    private func discoverSettingsWindow() -> NSWindow? {
        NSApp.windows.first { candidate in
            guard !(candidate is DeckPanel) else { return false }
            let title = candidate.title.lowercased()
            let id = candidate.identifier?.rawValue.lowercased() ?? ""
            return title == "settings" || id == "settings" || title.contains("settings") || id.contains("settings")
        }
    }

    func register(_ window: NSWindow?) {
        guard let window else { return }
        window.isReleasedWhenClosed = false
        self.window = window

        if pendingPresentation {
            pendingPresentation = false
            AppWindowActivation.present(window)
        }
    }

    func present(openWindow: () -> Void) {
        // If window already exists (open or hidden), bring it to front immediately (0ms)
        if let existing = window ?? discoverSettingsWindow() {
            self.window = existing
            AppWindowActivation.present(existing)
            return
        }

        // Otherwise, request SwiftUI to open the window scene for the first time
        pendingPresentation = true
        openWindow()

        presentationTask?.cancel()
        presentationTask = Task { @MainActor [weak self] in
            for delay in [30, 80, 160] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                if let target = self.window ?? self.discoverSettingsWindow() {
                    self.window = target
                    if self.pendingPresentation {
                        self.pendingPresentation = false
                        AppWindowActivation.present(target)
                    }
                    return
                }
            }
        }
    }
}

private final class SettingsWindowRegistrationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        SettingsWindowPresenter.shared.register(window)
    }
}

struct SettingsWindowRegistration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowRegistrationView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        SettingsWindowPresenter.shared.register(view.window)
    }
}

struct PocketStackSettingsButton<Label: View>: View {
    @Environment(\.openWindow) private var openWindow
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            SettingsWindowPresenter.shared.present {
                openWindow(id: "settings")
            }
        } label: {
            label()
        }
    }
}

/// The menu-bar label stays alive while this accessory app is running, so it
/// bridges AppKit menu commands to SwiftUI's window-opening environment.
struct PocketStackMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "note.text")
            .accessibilityLabel("Pocket Stack")
            .onReceive(NotificationCenter.default.publisher(for: .pocketStackOpenSettings)) { _ in
                SettingsWindowPresenter.shared.present {
                    openWindow(id: "settings")
                }
            }
    }
}
