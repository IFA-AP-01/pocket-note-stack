import AppKit
import Observation
import SwiftUI

@MainActor
final class UndoToastController {
    private let model: AppModel
    private let panel: NSPanel

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: UndoToastView(model: model))
    }

    func start() { observe(); update() }
    func stop() { panel.orderOut(nil) }

    private func observe() {
        withObservationTracking {
            _ = model.pendingDelete
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.update(); self?.observe() }
        }
    }

    private func update() {
        guard model.pendingDelete != nil, let screen = NSScreen.main else {
            panel.orderOut(nil)
            return
        }
        let frame = panel.frame
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - frame.width / 2, y: screen.visibleFrame.minY + 28))
        panel.orderFrontRegardless()
    }
}

private struct UndoToastView: View {
    let model: AppModel
    var body: some View {
        HStack {
            Image(systemName: "trash")
            Text("Note deleted").lineLimit(1)
            Spacer()
            Button("Undo") { model.undoDelete() }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(width: 260, height: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
