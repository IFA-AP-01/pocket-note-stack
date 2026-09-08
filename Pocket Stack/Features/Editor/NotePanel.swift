import AppKit

final class NotePanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var areCursorRectsEnabled: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else {
            return false
        }
        if flags == .command {
            switch characters {
            case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "z": return NSApp.sendAction(#selector(PocketTextView.undo(_:)), to: nil, from: self)
            case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "w": performClose(nil); return true
            default: break
            }
        } else if flags == [.command, .shift], characters == "z" {
            return NSApp.sendAction(#selector(PocketTextView.redo(_:)), to: nil, from: self)
        }
        return false
    }

    override func performClose(_ sender: Any?) {
        guard let controller = delegate as? NoteWindowController else {
            super.performClose(sender)
            return
        }
        guard !controller.bridge.isDictating else { return }
        super.performClose(sender)
    }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Note"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        if let closeButton = standardWindowButton(.closeButton) {
            closeButton.isHidden = false
            alignCloseButton()
            setupCloseButtonCursor(closeButton)
        }
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    private func setupCloseButtonCursor(_ button: NSButton) {
        button.trackingAreas.forEach(button.removeTrackingArea)
        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(area)
    }

    func alignCloseButton() {
        guard let closeButton = standardWindowButton(.closeButton) else { return }
        let targetOrigin = CGPoint(x: 14, y: 4)
        if closeButton.frame.origin != targetOrigin {
            closeButton.setFrameOrigin(targetOrigin)
        }
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        alignCloseButton()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        alignCloseButton()
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        if let hit = contentView?.hitTest(event.locationInWindow) {
            var current: NSView? = hit
            while let v = current {
                if v is NativeWindowDragHandle.DragHandleView { return }
                current = v.superview
            }
        }
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let loc = event.locationInWindow
        if let closeButton = standardWindowButton(.closeButton) {
            let rect = closeButton.convert(closeButton.bounds, to: nil)
            if rect.contains(loc) {
                NSCursor.arrow.set()
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.arrow.set()
    }
}
