import AppKit
import SwiftUI

extension Notification.Name {
    static let pocketStackOpenSettings = Notification.Name("PocketStackOpenSettings")
}

/// SwiftUI owns the Settings scene, while this presenter only restores the
/// expected AppKit focus semantics for an LSUIElement/accessory application.
@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()
    private weak var window: NSWindow?
    private var focusTask: Task<Void, Never>?

    private init() {}

    func register(_ window: NSWindow?) {
        guard let window else { return }
        guard self.window !== window else { return }
        self.window = window
        focus(window)
    }

    /// Call immediately after OpenSettingsAction. The retries cover the first
    /// scene creation and subsequent clicks while the existing window is
    /// behind another application.
    func requestFocus() {
        NSApp.activate()
        focusTask?.cancel()
        focusTask = Task { @MainActor [weak self] in
            for delay in [0, 40, 140, 300] {
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                guard !Task.isCancelled, let self else { return }
                if let window = self.window ?? self.discoverSettingsWindow() {
                    self.window = window
                    self.focus(window)
                    return
                }
            }
        }
    }

    private func discoverSettingsWindow() -> NSWindow? {
        NSApp.windows.first { candidate in
            guard !(candidate is DeckPanel) else { return false }
            let identifier = candidate.identifier?.rawValue.lowercased() ?? ""
            let title = candidate.title.lowercased()
            return identifier.contains("settings") || title.contains("settings")
        }
    }

    private func focus(_ window: NSWindow) {
        NSApp.activate()
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct SettingsWindowProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        registerWindow(of: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { registerWindow(of: view) }

    private func registerWindow(of view: NSView) {
        DispatchQueue.main.async {
            SettingsWindowPresenter.shared.register(view.window)
        }
    }
}

/// A single, ordered action avoids the race between SettingsLink and a
/// simultaneous tap gesture in an accessory application.
struct PocketStackSettingsButton<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            open()
        } label: {
            label()
        }
    }

    private func open() {
        NSApp.activate()
        openSettings()
        SettingsWindowPresenter.shared.requestFocus()
    }
}

/// The menu-bar label is always alive, so AppKit menu commands can request the
/// SwiftUI Settings scene without using the deprecated showSettingsWindow: selector.
struct PocketStackMenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: "note.text")
            .accessibilityLabel("Pocket Stack")
            .onReceive(NotificationCenter.default.publisher(for: .pocketStackOpenSettings)) { _ in
                NSApp.activate()
                openSettings()
                SettingsWindowPresenter.shared.requestFocus()
            }
    }
}
