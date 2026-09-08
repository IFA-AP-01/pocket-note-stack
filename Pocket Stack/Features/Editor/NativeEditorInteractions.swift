import AppKit
import SwiftUI

struct NativeArrowCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ nsView: CursorView, context: Context) {}

    final class CursorView: NSView {
        private var trackingArea: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
        override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }
        override func mouseEntered(with event: NSEvent) { NSCursor.arrow.set() }
    }
}

struct NativeWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        private var trackingArea: NSTrackingArea?

        override var intrinsicContentSize: NSSize {
            NSSize(width: 28, height: 24)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.set()
            window?.performDrag(with: event)
            if let window {
                let mouseInView = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
                if mouseInView {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            } else {
                NSCursor.arrow.set()
            }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
        override func mouseMoved(with event: NSEvent) { NSCursor.openHand.set() }
        override func mouseEntered(with event: NSEvent) { NSCursor.openHand.set() }
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    }
}
