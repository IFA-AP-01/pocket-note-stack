import AppKit
import SwiftUI

@MainActor
final class LibraryWindowController: NSWindowController {
    private let model: AppModel
    init(model: AppModel) { self.model = model; super.init(window: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func show(archive: Bool) {
        let root = LibraryView(model: model, initialArchive: archive)
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Pocket Stack"
            window.setContentSize(NSSize(width: 920, height: 620))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        } else if let host = window?.contentViewController as? NSHostingController<LibraryView> {
            host.rootView = root
        } else {
            window?.contentViewController = NSHostingController(rootView: root)
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
