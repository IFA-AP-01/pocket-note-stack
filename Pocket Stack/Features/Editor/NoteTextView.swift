import AppKit
import SwiftUI

struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let bridge: EditorBridge
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat
    let markdown: Bool
    let onCommand: (EditorCommand) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let textView = FirstMouseTextView()
        textView.delegate = context.coordinator
        textView.onCommand = onCommand
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        bridge.textView = textView
        applyStyle(textView)
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        (textView as? FirstMouseTextView)?.onCommand = onCommand
        if textView.string != text, !bridge.isDictating { textView.string = text }
        applyStyle(textView)
    }

    private func applyStyle(_ textView: NSTextView) {
        let font = fontName.isEmpty ? NSFont.systemFont(ofSize: fontSize) : NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        textView.font = font
        textView.textColor = NSColor(palette.ink)
        textView.insertionPointColor = NSColor(palette.ink)
        guard markdown else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.addAttributes([.font: font, .foregroundColor: NSColor(palette.ink)], range: full)
        let patterns: [(String, NSFont)] = [
            ("(?m)^#{1,6} .+$", NSFont.systemFont(ofSize: fontSize + 3, weight: .bold)),
            ("\\*\\*[^*]+\\*\\*", NSFont.systemFont(ofSize: fontSize, weight: .bold)),
            ("`[^`]+`", NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)),
        ]
        for (pattern, styledFont) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: textView.string, range: full) {
                textView.textStorage?.addAttribute(.font, value: styledFont, range: match.range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        init(parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class FirstMouseTextView: NSTextView {
    var onCommand: ((EditorCommand) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let control = event.modifierFlags.contains(.control)
        switch (event.keyCode, command, shift, control) {
        case (53, _, _, _): onCommand?(.escape)
        case (3, true, _, _): performFindPanelAction(nil)
        case (17, true, false, _): onCommand?(.toggleTask)
        case (35, true, false, _): onCommand?(.togglePin)
        case (47, true, false, _): onCommand?(.cycleColor)
        case (51, true, false, _): onCommand?(.delete)
        case (0, true, true, _): onCommand?(.archive)
        case (24, false, _, true): onCommand?(.increaseFont)
        case (27, false, _, true): onCommand?(.decreaseFont)
        default: super.keyDown(with: event)
        }
    }
}

enum EditorCommand { case escape, toggleTask, togglePin, cycleColor, delete, archive, increaseFont, decreaseFont }
