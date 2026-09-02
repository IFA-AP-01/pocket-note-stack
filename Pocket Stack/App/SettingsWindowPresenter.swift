import AppKit
import SwiftUI

extension Notification.Name {
    static let pocketStackOpenSettings = Notification.Name("PocketStackOpenSettings")
}

struct PocketStackSettingsButton<Label: View>: View {
    @Environment(\.openWindow) private var openWindow
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
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
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
    }
}
