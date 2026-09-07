import AppKit
import SwiftUI

extension Notification.Name {
    static let pocketStackOpenSettings = Notification.Name("PocketStackOpenSettings")
    static let pocketStackVoiceNoteWarning = Notification.Name("PocketStackVoiceNoteWarning")
}

@MainActor
enum AppWindowActivation {
    static func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    static func presentAfterMenuDismisses(_ window: NSWindow) {
        present(window)
        Task { @MainActor [weak window] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let window else { return }
            present(window)
        }
    }
}

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private weak var window: NSWindow?
    private var pendingPresentation = false
    private var presentationTask: Task<Void, Never>?

    private init() {}

    func register(_ window: NSWindow?) {
        guard let window else { return }
        self.window = window
        if pendingPresentation {
            pendingPresentation = false
            AppWindowActivation.presentAfterMenuDismisses(window)
        }
    }

    func present(openWindow: () -> Void) {
        if let window {
            AppWindowActivation.presentAfterMenuDismisses(window)
            return
        }

        pendingPresentation = true
        openWindow()
        presentationTask?.cancel()
        presentationTask = Task { @MainActor [weak self] in
            for delay in [0, 40, 120, 240] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard !Task.isCancelled, let self else { return }
                if let window = self.window {
                    self.pendingPresentation = false
                    AppWindowActivation.presentAfterMenuDismisses(window)
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
