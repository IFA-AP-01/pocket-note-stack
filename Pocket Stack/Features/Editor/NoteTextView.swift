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
        let currentMarkdown = markdownString(from: textView)
        if currentMarkdown != text, !bridge.isDictating { textView.string = text }
        applyStyle(textView)
    }

    func markdownString(from textView: NSTextView) -> String {
        var result = ""
        let attrString = textView.attributedString()
        attrString.enumerateAttributes(in: NSRange(location: 0, length: attrString.length), options: []) { attrs, range, _ in
            if let md = attrs[NSAttributedString.Key("MarkdownOriginal")] as? String {
                result += md
            } else {
                result += (attrString.string as NSString).substring(with: range)
            }
        }
        return result
    }

    private func applyStyle(_ textView: NSTextView) {
        let font = fontName.isEmpty ? NSFont.systemFont(ofSize: fontSize) : NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        textView.font = font
        textView.textColor = NSColor(palette.ink)
        textView.insertionPointColor = NSColor(palette.ink)
        guard markdown else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.addAttributes([.font: font, .foregroundColor: NSColor(palette.ink)], range: full)
        let patterns: [(String, NSFont, NSColor?)] = [
            ("(?m)^# .+$", NSFont.systemFont(ofSize: fontSize + 6, weight: .bold), nil),
            ("(?m)^## .+$", NSFont.systemFont(ofSize: fontSize + 4, weight: .bold), nil),
            ("(?m)^### .+$", NSFont.systemFont(ofSize: fontSize + 2, weight: .semibold), nil),
            ("\\*\\*[^*]+\\*\\*", NSFont.systemFont(ofSize: fontSize, weight: .bold), nil),
            ("\\*[^*]+\\*", NSFont.systemFont(ofSize: fontSize, weight: .regular), nil), // Italic doesn't have a reliable italic system font weight without font descriptor, but let's just make it italic
            ("~~[^~]+~~", NSFont.systemFont(ofSize: fontSize), NSColor.tertiaryLabelColor),
            ("`[^`]+`", NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular), nil),
            ("(?m)^[-*] .+$", NSFont.systemFont(ofSize: fontSize), nil),
            ("(?m)^\\d+\\. .+$", NSFont.systemFont(ofSize: fontSize), nil),
            ("(?m)^[-*] \\[[ xX]\\] .+$", NSFont.systemFont(ofSize: fontSize), nil)
        ]
        for (pattern, styledFont, styledColor) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: textView.string, range: full) {
                textView.textStorage?.addAttribute(.font, value: styledFont, range: match.range)
                if let color = styledColor {
                    textView.textStorage?.addAttribute(.foregroundColor, value: color, range: match.range)
                }
                
                // For italic
                if pattern == "\\*[^*]+\\*" {
                    let descriptor = font.fontDescriptor.withSymbolicTraits(.italic) ?? font.fontDescriptor
                    if let italicFont = NSFont(descriptor: descriptor, size: fontSize) {
                        textView.textStorage?.addAttribute(.font, value: italicFont, range: match.range)
                    }
                }
                // For strikethrough
                if pattern == "~~[^~]+~~" {
                    textView.textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
                }
            }
        }
        
        // Handle Images ![Alt](filename.png)
        let imagePattern = "!\\[.*?\\]\\(([^)]+)\\)"
        guard let imgRegex = try? NSRegularExpression(pattern: imagePattern) else { return }
        
        let fullForImg = NSRange(location: 0, length: (textView.string as NSString).length)
        let imgMatches = imgRegex.matches(in: textView.string, range: fullForImg).reversed()
        for match in imgMatches {
            if let pathRange = Range(match.range(at: 1), in: textView.string),
               let fullRange = Range(match.range, in: textView.string) {
                let filename = String(textView.string[pathRange])
                let originalMarkdown = String(textView.string[fullRange])
                if let image = AttachmentManager.shared.loadImage(named: filename) {
                    let attachment = NSTextAttachment()
                    let maxWidth: CGFloat = 300
                    if image.size.width > maxWidth {
                        let ratio = maxWidth / image.size.width
                        attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: image.size.height * ratio)
                    } else {
                        attachment.bounds = CGRect(origin: .zero, size: image.size)
                    }
                    attachment.image = image
                    
                    let attachStr = NSMutableAttributedString(attachment: attachment)
                    attachStr.addAttribute(NSAttributedString.Key("MarkdownOriginal"), value: originalMarkdown, range: NSRange(location: 0, length: 1))
                    
                    textView.textStorage?.beginEditing()
                    textView.textStorage?.replaceCharacters(in: match.range, with: attachStr)
                    textView.textStorage?.endEditing()
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        init(parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let result = parent.markdownString(from: textView)
            if parent.text != result {
                parent.text = result
            }
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
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "a":
                self.selectAll(nil)
                return true
            case "c":
                self.copy(nil)
                return true
            case "v":
                if event.modifierFlags.contains(.shift) {
                    self.pasteAsPlainText(nil)
                } else {
                    self.paste(nil)
                }
                return true
            case "x":
                self.cut(nil)
                return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    self.undoManager?.redo()
                } else {
                    self.undoManager?.undo()
                }
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let image = images.first {
            if let filename = AttachmentManager.shared.saveImage(image) {
                let markdown = "![Image](\(filename))"
                insertMarkdown(markdown)
                return
            }
        }
        
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first {
            if ["png", "jpg", "jpeg", "gif", "heic"].contains(url.pathExtension.lowercased()) {
                if let filename = AttachmentManager.shared.saveFile(from: url) {
                    let markdown = "![Image](\(filename))"
                    insertMarkdown(markdown)
                    return
                }
            }
        }
        super.paste(sender)
    }
    
    private func insertMarkdown(_ text: String) {
        if shouldChangeText(in: selectedRange(), replacementString: text) {
            textStorage?.replaceCharacters(in: selectedRange(), with: text)
            didChangeText()
        }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadItem(withDataConformingToTypes: ["public.image", "public.file-url"]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first {
            if ["png", "jpg", "jpeg", "gif", "heic"].contains(url.pathExtension.lowercased()) {
                if let filename = AttachmentManager.shared.saveFile(from: url) {
                    let markdown = "![Image](\(filename))"
                    insertMarkdown(markdown)
                    return true
                }
            }
        }
        
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let image = images.first {
            if let filename = AttachmentManager.shared.saveImage(image) {
                let markdown = "![Image](\(filename))"
                insertMarkdown(markdown)
                return true
            }
        }
        
        return super.performDragOperation(sender)
    }
}

enum EditorCommand { 
    case escape, toggleTask, togglePin, cycleColor, delete, archive, increaseFont, decreaseFont 
    case formatTitle, formatHeading, formatSubheading, formatBody, formatMonospaced
    case formatBold, formatItalic, formatStrikethrough, formatUnderline
    case formatBulletList, formatDashList, formatNumberList, formatCheckList
    case insertTable, insertImage
}
