import AppKit
import SwiftUI

final class LibraryWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return false
        }

        if flags == .command {
            switch chars {
            case "x":
                return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "c":
                return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            case "v":
                return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "z":
                return NSApp.sendAction(#selector(PocketTextView.undo(_:)), to: nil, from: self)
            case "a":
                return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "w":
                self.performClose(nil)
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            switch chars {
            case "z":
                return NSApp.sendAction(#selector(PocketTextView.redo(_:)), to: nil, from: self)
            default:
                break
            }
        }
        return false
    }
}

@MainActor
final class LibraryWindowController: NSWindowController {
    private let model: AppModel
    init(model: AppModel) { self.model = model; super.init(window: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func show(archive: Bool) {
        let root = LibraryView(model: model, initialArchive: archive)
        if window == nil {
            let window = LibraryWindow(contentViewController: NSHostingController(rootView: root))
            window.title = archive ? "Archive" : "All Notes"
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
        window?.title = archive ? "Archive" : "All Notes"
        showWindow(nil)
        if let window {
            AppWindowActivation.presentAfterMenuDismisses(window)
        }
    }
}
