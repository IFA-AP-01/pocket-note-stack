import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom Attribute Keys
extension NSAttributedString.Key {
    static let psImageSource = NSAttributedString.Key("PSMarkdownImageSource")
    static let psImageAlt = NSAttributedString.Key("PSMarkdownImageAlt")
    static let psChecklist = NSAttributedString.Key("PSMarkdownChecklist")
    static let psStyleRole = NSAttributedString.Key("PSStyleRole") // "title", "heading", "subheading", "body", "mono"
}

// MARK: - PocketEditorScrollView (Outer Scroll Forwarding & Dynamic Height)

final class PocketEditorScrollView: NSScrollView {
    var fitsContent: Bool = false

    override var intrinsicContentSize: NSSize {
        if fitsContent, let textView = documentView as? PocketTextView {
            return NSSize(width: NSView.noIntrinsicMetric, height: textView.contentHeight)
        }
        return super.intrinsicContentSize
    }

    override func scrollWheel(with event: NSEvent) {
        if fitsContent {
            if let enclosing = enclosingScrollView {
                enclosing.scrollWheel(with: event)
            } else {
                nextResponder?.scrollWheel(with: event)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - PocketNoteEditorView (SwiftUI Wrapper)

struct PocketNoteEditorView: View {
    @Binding var text: String
    let palette: NotePaletteColor
    let fontSize: CGFloat
    let fontName: String
    let bridge: EditorBridge
    var scrolls: Bool = true
    var onExit: (() -> Void)? = nil

    var body: some View {
        PocketNativeEditorRepresentable(
            text: $text,
            palette: palette,
            fontSize: fontSize,
            fontName: fontName,
            bridge: bridge,
            scrolls: scrolls,
            onExit: onExit
        )
        .background(palette.paper)
    }
}

// MARK: - NSViewRepresentable

private struct PocketNativeEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let palette: NotePaletteColor
    let fontSize: CGFloat
    let fontName: String
    let bridge: EditorBridge
    var scrolls: Bool = true
    var onExit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PocketEditorScrollView {
        let defaultNoteSize = AppPreferences.shared.noteSize
        let initialWidth = max(360, defaultNoteSize.width)
        let initialHeight = max(240, defaultNoteSize.height)
        let initialFrame = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)

        let scrollView = PocketEditorScrollView(frame: initialFrame)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        if !scrolls {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
            scrollView.fitsContent = true
        } else {
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.fitsContent = false
        }

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let contentWidth = max(initialWidth - 36, 320)
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = PocketTextView(frame: initialFrame, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.editorCoordinator = context.coordinator
        textView.onExit = onExit
        textView.minSize = NSSize(width: 0, height: scrolls ? initialHeight : 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.allowsUndo = true

        context.coordinator.textView = textView
        bridge.activeTextView = textView

        textView.applyTheme(palette: palette, fontSize: fontSize, fontName: fontName)
        context.coordinator.loadText(text)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: PocketEditorScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PocketTextView else { return }
        context.coordinator.parent = self
        bridge.activeTextView = textView
        textView.onExit = onExit
        textView.applyTheme(palette: palette, fontSize: fontSize, fontName: fontName)

        if !context.coordinator.isInternalUpdate && context.coordinator.lastLoadedText != text {
            context.coordinator.loadText(text)
            if !scrolls {
                scrollView.invalidateIntrinsicContentSize()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PocketEditorScrollView, context: Context) -> CGSize? {
        guard !scrolls else { return nil }
        guard let textView = nsView.documentView as? PocketTextView else { return nil }
        let targetWidth = proposal.width ?? (nsView.bounds.width > 0 ? nsView.bounds.width : 600)
        let height = textView.contentHeight
        return CGSize(width: targetWidth, height: height)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PocketNativeEditorRepresentable
        weak var textView: PocketTextView?
        var isInternalUpdate = false
        var lastLoadedText = ""

        init(_ parent: PocketNativeEditorRepresentable) {
            self.parent = parent
        }

        func loadText(_ newText: String) {
            guard let textView else { return }
            lastLoadedText = newText
            textView.loadContent(newText)
            textView.undoManager?.removeAllActions()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !textView.hasMarkedText() else { return }
            isInternalUpdate = true
            let serialized = textView.serializeContent()
            lastLoadedText = serialized
            parent.text = serialized
            isInternalUpdate = false
            if !parent.scrolls, let scroll = textView.enclosingScrollView {
                scroll.invalidateIntrinsicContentSize()
            }
        }
    }
}

// MARK: - PocketTextView (Native Apple Notes Rich Text Editor)

final class PocketTextView: NSTextView {
    fileprivate weak var editorCoordinator: PocketNativeEditorRepresentable.Coordinator?
    var onExit: (() -> Void)?

    private var currentPalette: NotePaletteColor?
    private var currentFontSize: CGFloat = 15
    private var currentFontName: String = ""
    private var cursorTrackingArea: NSTrackingArea?

    private let customUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        return customUndoManager
    }

    @objc func undo(_ sender: Any?) {
        if let um = undoManager, um.canUndo {
            um.undo()
        }
    }

    @objc func redo(_ sender: Any?) {
        if let um = undoManager, um.canRedo {
            um.redo()
        }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(undo(_:)) || aSelector == Selector(("undo:")) {
            return undoManager?.canUndo ?? false
        }
        if aSelector == #selector(redo(_:)) || aSelector == Selector(("redo:")) {
            return undoManager?.canRedo ?? false
        }
        return super.responds(to: aSelector)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) || item.action == Selector(("undo:")) {
            return undoManager?.canUndo ?? false
        }
        if item.action == #selector(redo(_:)) || item.action == Selector(("redo:")) {
            return undoManager?.canRedo ?? false
        }
        return super.validateUserInterfaceItem(item)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        allowsUndo = true
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        allowsUndo = true
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        if let scroll = enclosingScrollView as? PocketEditorScrollView, scroll.fitsContent {
            scroll.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    var contentHeight: CGFloat {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return 160
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        var totalHeight = usedRect.maxY
        if layoutManager.extraLineFragmentRect.height > 0 {
            totalHeight = max(totalHeight, layoutManager.extraLineFragmentRect.maxY)
        }

        let finalHeight = ceil(totalHeight + textContainerInset.height * 2 + 16)
        return max(160, finalHeight)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            EditorBridge.setLastActive(self)
            window?.invalidateCursorRects(for: self)
            let mouseLoc = window?.mouseLocationOutsideOfEventStream ?? .zero
            let loc = convert(mouseLoc, from: nil)
            if visibleRect.contains(loc) {
                NSCursor.iBeam.set()
            }
        }
        return ok
    }

    override func cancelOperation(_ sender: Any?) {
        if let onExit {
            onExit()
        } else {
            super.cancelOperation(sender)
        }
    }

    // MARK: - Always Maintain I-Beam Cursor in Floating Mode

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if visibleRect.contains(loc) {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let loc = convert(event.locationInWindow, from: nil)
        if visibleRect.contains(loc) {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        let loc = convert(event.locationInWindow, from: nil)
        if visibleRect.contains(loc) {
            NSCursor.iBeam.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(visibleRect, cursor: .iBeam)
    }

    // MARK: - Native Vietnamese Typing & Undo Support

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    // MARK: - Native Shortcuts & Key Equivalents (Cmd+C, Cmd+V, Cmd+X, Cmd+Z, etc.)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return super.performKeyEquivalent(with: event)
        }

        if flags == .command {
            switch chars {
            case "c":
                copy(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            case "z":
                if let um = undoManager, um.canUndo {
                    um.undo()
                }
                return true
            case "y":
                if let um = undoManager, um.canRedo {
                    um.redo()
                }
                return true
            case "b":
                toggleBold()
                return true
            case "i":
                toggleItalic()
                return true
            case "u":
                toggleUnderline()
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            switch chars {
            case "z":
                if let um = undoManager, um.canRedo {
                    um.redo()
                }
                return true
            case "v":
                pasteAsPlainText(nil)
                return true
            case "x", "s":
                toggleStrikethrough()
                return true
            case "c", "l":
                toggleChecklist()
                return true
            case "u":
                toggleBulletList()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Appearance & Fonts

    func applyTheme(palette: NotePaletteColor, fontSize: CGFloat, fontName: String) {
        currentPalette = palette
        currentFontSize = fontSize
        currentFontName = fontName

        backgroundColor = NSColor(palette.paper)
        drawsBackground = true
        textColor = NSColor(palette.ink)
        insertionPointColor = NSColor(palette.accent)
        selectedTextAttributes = [
            .backgroundColor: NSColor(palette.accent).withAlphaComponent(0.25),
            .foregroundColor: NSColor(palette.ink)
        ]
    }

    func fontForRole(_ role: String?) -> NSFont {
        switch role {
        case "title":
            return NSFont.systemFont(ofSize: max(24, currentFontSize * 1.65), weight: .bold)
        case "heading":
            return NSFont.systemFont(ofSize: max(19, currentFontSize * 1.3), weight: .bold)
        case "subheading":
            return NSFont.systemFont(ofSize: max(16, currentFontSize * 1.15), weight: .semibold)
        case "mono":
            return NSFont.monospacedSystemFont(ofSize: max(13, currentFontSize - 1), weight: .regular)
        default:
            if !currentFontName.isEmpty, let custom = NSFont(name: currentFontName, size: currentFontSize) {
                return custom
            }
            return NSFont.systemFont(ofSize: currentFontSize, weight: .regular)
        }
    }

    // MARK: - Apple Notes Circular Checkbox Attachment

    func makeCheckboxAttachment(checked: Bool) -> NSAttributedString {
        let palette = currentPalette ?? NotePalette.color(0)
        let diameter: CGFloat = 17
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()

        let rect = NSRect(x: 1.0, y: 1.0, width: diameter - 2.0, height: diameter - 2.0)

        if checked {
            // Filled circle with accent color + white checkmark
            let path = NSBezierPath(ovalIn: rect)
            NSColor(palette.accent).setFill()
            path.fill()

            let check = NSBezierPath()
            check.move(to: NSPoint(x: 4.5, y: 8.5))
            check.line(to: NSPoint(x: 7.2, y: 5.5))
            check.line(to: NSPoint(x: 12.5, y: 11.5))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            // Hollow circle ring matching Apple Notes reference
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 1.5
            NSColor(palette.ink).withAlphaComponent(0.42).setStroke()
            path.stroke()
        }

        image.unlockFocus()

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -3.0, width: diameter, height: diameter)

        let attr = NSMutableAttributedString(attachment: attachment)
        attr.addAttributes([
            NSAttributedString.Key.psChecklist: checked,
            .font: fontForRole(nil)
        ], range: NSRange(location: 0, length: attr.length))
        return attr
    }

    // MARK: - 100% Reliable Checkbox Click Interaction

    override func mouseDown(with event: NSEvent) {
        if window?.isKeyWindow == false {
            window?.makeKey()
        }
        NSCursor.iBeam.set()

        let clickPointInView = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: clickPointInView.x - textContainerOrigin.x,
            y: clickPointInView.y - textContainerOrigin.y
        )

        if let layoutManager = layoutManager, let textContainer = textContainer, let storage = textStorage {
            let queryPoint = NSPoint(x: max(0, containerPoint.x), y: max(0, containerPoint.y))
            let glyphIndex = layoutManager.glyphIndex(for: queryPoint, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let fullText = (string as NSString)

            if charIndex < fullText.length {
                let lineRange = fullText.lineRange(for: NSRange(location: charIndex, length: 0))

                // Find if there is a checklist attachment on this line
                var boxCharIndex: Int? = nil
                let scanEnd = min(lineRange.location + 8, lineRange.location + lineRange.length)
                for i in lineRange.location..<scanEnd {
                    if storage.attribute(.psChecklist, at: i, effectiveRange: nil) != nil {
                        boxCharIndex = i
                        break
                    }
                }

                if let targetCharIdx = boxCharIndex,
                   let isChecked = storage.attribute(.psChecklist, at: targetCharIdx, effectiveRange: nil) as? Bool {
                    
                    let boxGlyphIndex = layoutManager.glyphIndexForCharacter(at: targetCharIdx)
                    let boxRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: boxGlyphIndex, length: 1), in: textContainer)
                    
                    // Box rect in text view coordinates
                    let boxViewRect = NSRect(
                        x: boxRect.origin.x + textContainerOrigin.x,
                        y: boxRect.origin.y + textContainerOrigin.y,
                        width: boxRect.width,
                        height: boxRect.height
                    )
                    
                    // Generous tap target: from left edge x = 0 to 24pt past the box, and line height vertically
                    let tapRect = NSRect(
                        x: 0,
                        y: boxViewRect.minY - 4,
                        width: boxViewRect.maxX + 24,
                        height: boxViewRect.height + 8
                    )

                    if tapRect.contains(clickPointInView) {
                        let newChecked = !isChecked
                        let newBox = makeCheckboxAttachment(checked: newChecked)
                        
                        let replaceRange = NSRange(location: targetCharIdx, length: 1)
                        guard shouldChangeText(in: replaceRange, replacementString: nil) else { return }
                        storage.replaceCharacters(in: replaceRange, with: newBox)

                        let lineEnd = lineRange.location + lineRange.length
                        let textStart = targetCharIdx + 1
                        if textStart < lineEnd {
                            let textRange = NSRange(location: textStart, length: lineEnd - textStart)
                            let ink = NSColor(currentPalette?.ink ?? Color.primary)
                            if newChecked {
                                storage.addAttributes([
                                    .foregroundColor: ink.withAlphaComponent(0.45),
                                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                                ], range: textRange)
                            } else {
                                storage.removeAttribute(.strikethroughStyle, range: textRange)
                                storage.addAttribute(.foregroundColor, value: ink, range: textRange)
                            }
                        }

                        didChangeText()
                        setNeedsDisplay(bounds)
                        return
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Smart Enter & List Continuation

    override func insertNewline(_ sender: Any?) {
        let selected = selectedRange()
        guard let storage = textStorage else {
            super.insertNewline(sender)
            return
        }

        let fullText = (string as NSString)
        let lineRange = fullText.lineRange(for: NSRange(location: min(selected.location, fullText.length), length: 0))
        let line = fullText.substring(with: lineRange).trimmingCharacters(in: .newlines)

        // 1. Checklist continuation
        var existingBoxIdx: Int? = nil
        let scanEnd = min(lineRange.location + 8, lineRange.location + lineRange.length)
        for i in lineRange.location..<scanEnd {
            if storage.attribute(.psChecklist, at: i, effectiveRange: nil) != nil {
                existingBoxIdx = i
                break
            }
        }

        if let boxIdx = existingBoxIdx {
            let afterBoxStart = boxIdx + 1
            let lineAfterBox = afterBoxStart < (lineRange.location + lineRange.length)
                ? fullText.substring(with: NSRange(location: afterBoxStart, length: (lineRange.location + lineRange.length) - afterBoxStart)).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            if lineAfterBox.isEmpty {
                // Empty checklist -> exit list mode
                let removeRange = NSRange(location: lineRange.location, length: lineRange.length)
                storage.replaceCharacters(in: removeRange, with: "\n")
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
                return
            } else {
                // Continue checklist on next line
                let nextBox = makeCheckboxAttachment(checked: false)
                let item = NSMutableAttributedString(string: "\n")
                item.append(nextBox)
                item.append(NSAttributedString(string: " "))

                storage.replaceCharacters(in: selected, with: item)
                didChangeText()
                setSelectedRange(NSRange(location: selected.location + item.length, length: 0))
                return
            }
        }

        // 2. Bullet list continuation (• )
        if line == "•" || line == "• " {
            if shouldChangeText(in: lineRange, replacementString: "\n") {
                storage.replaceCharacters(in: lineRange, with: "\n")
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
            }
            return
        } else if line.hasPrefix("• ") {
            insertText("\n• ", replacementRange: selected)
            return
        }

        // 3. Dashed list continuation (– )
        if line == "–" || line == "– " {
            if shouldChangeText(in: lineRange, replacementString: "\n") {
                storage.replaceCharacters(in: lineRange, with: "\n")
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
            }
            return
        } else if line.hasPrefix("– ") {
            insertText("\n– ", replacementRange: selected)
            return
        }

        // 4. Numbered list continuation (1. )
        if let match = line.range(of: #"^(\d+)\.\s*(.*)"#, options: .regularExpression) {
            let matched = String(line[match])
            let parts = matched.split(separator: ".", maxSplits: 1)
            if let numStr = parts.first, let num = Int(numStr) {
                let remainder = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                if remainder.isEmpty {
                    if shouldChangeText(in: lineRange, replacementString: "\n") {
                        storage.replaceCharacters(in: lineRange, with: "\n")
                        didChangeText()
                        setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    }
                    return
                } else {
                    insertText("\n\(num + 1). ", replacementRange: selected)
                    return
                }
            }
        }

        // 5. Block quote continuation (▍ )
        if line == "▍" || line == "▍ " {
            if shouldChangeText(in: lineRange, replacementString: "\n") {
                storage.replaceCharacters(in: lineRange, with: "\n")
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
            }
            return
        } else if line.hasPrefix("▍ ") {
            insertText("\n▍ ", replacementRange: selected)
            return
        }

        super.insertNewline(sender)
    }

    // MARK: - Paste & Drag-and-Drop Image Attachments

    override func paste(_ sender: Any?) {
        let pboard = NSPasteboard.general

        // 1. Standalone image files (e.g. copied in Finder)
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            for url in urls {
                if let uti = UTType(filenameExtension: url.pathExtension), uti.conforms(to: .image) {
                    if let filename = AttachmentManager.shared.saveFile(from: url) {
                        insertImageAttachment(filename: filename, alt: url.deletingPathExtension().lastPathComponent)
                        return
                    }
                }
            }
        }

        // 2. Direct image in pasteboard (Screenshots, Copy Image from Chrome/Safari/Firefox/Preview/etc.)
        let types = pboard.types ?? []
        let hasDirectImageData = types.contains(where: {
            $0 == .png || $0 == .tiff || $0.rawValue.lowercased().contains("image")
        })

        if hasDirectImageData, let image = NSImage(pasteboard: pboard) {
            // Only treat as text document if user copied a large block of text that happens to have image data
            let plainText = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isLargeTextDocument = plainText.contains("\n") && plainText.count > 120

            if !isLargeTextDocument {
                if let filename = AttachmentManager.shared.saveImage(image) {
                    insertImageAttachment(filename: filename, alt: "Image")
                    return
                }
            }
        }

        // 3. Rich text: sanitize colors and foreign background boxes
        if let items = pboard.readObjects(forClasses: [NSAttributedString.self], options: nil) as? [NSAttributedString],
           let rawAttr = items.first, rawAttr.length > 0 {
            let sanitized = sanitizePastedAttributedString(rawAttr)
            let selected = selectedRange()
            if shouldChangeText(in: selected, replacementString: sanitized.string) {
                textStorage?.replaceCharacters(in: selected, with: sanitized)
                didChangeText()
                setSelectedRange(NSRange(location: selected.location + sanitized.length, length: 0))
                return
            }
        }

        // 4. Plain text fallback
        if let plain = pboard.string(forType: .string), !plain.isEmpty {
            pastePlainTextString(plain)
            return
        }

        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        let pboard = NSPasteboard.general
        if let str = pboard.string(forType: .string) {
            pastePlainTextString(str)
        } else {
            super.pasteAsPlainText(sender)
        }
    }

    private func pastePlainTextString(_ string: String) {
        let selected = selectedRange()
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 3
        pStyle.paragraphSpacing = 6

        let attrs: [NSAttributedString.Key: Any] = [
            .font: fontForRole(nil),
            .foregroundColor: NSColor(currentPalette?.ink ?? Color.primary),
            .paragraphStyle: pStyle
        ]
        let attrString = NSAttributedString(string: string, attributes: attrs)
        if shouldChangeText(in: selected, replacementString: string) {
            textStorage?.replaceCharacters(in: selected, with: attrString)
            didChangeText()
            setSelectedRange(NSRange(location: selected.location + attrString.length, length: 0))
        }
    }

    private func sanitizePastedAttributedString(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = fontForRole(nil)
        let ink = NSColor(currentPalette?.ink ?? Color.primary)
        let accent = NSColor(currentPalette?.accent ?? Color.blue)

        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 3
        pStyle.paragraphSpacing = 6

        source.enumerateAttributes(in: NSRange(location: 0, length: source.length), options: []) { attrs, range, _ in
            let substring = (source.string as NSString).substring(with: range)
            var newAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: ink,
                .paragraphStyle: pStyle
            ]

            let sourceFont = attrs[.font] as? NSFont
            var isBold = false
            var isItalic = false
            var isMono = false
            var isLargeTitle = false
            var isLargeHeading = false

            if let sf = sourceFont {
                let traits = NSFontManager.shared.traits(of: sf)
                isBold = traits.contains(.boldFontMask)
                isItalic = traits.contains(.italicFontMask)
                let fName = sf.fontName.lowercased()
                isMono = sf.isFixedPitch || fName.contains("mono") || fName.contains("menlo") || fName.contains("courier") || fName.contains("code")

                if sf.pointSize >= currentFontSize * 1.5 {
                    isLargeTitle = true
                } else if sf.pointSize >= currentFontSize * 1.25 {
                    isLargeHeading = true
                }
            }

            let targetFont: NSFont
            if isLargeTitle {
                targetFont = fontForRole("title")
                newAttrs[NSAttributedString.Key.psStyleRole] = "title"
            } else if isLargeHeading {
                targetFont = fontForRole("heading")
                newAttrs[NSAttributedString.Key.psStyleRole] = "heading"
            } else if isMono {
                targetFont = fontForRole("mono")
            } else {
                var f = baseFont
                if isBold {
                    f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
                }
                if isItalic {
                    f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
                }
                targetFont = f
            }
            newAttrs[.font] = targetFont

            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                newAttrs[.underlineStyle] = underline
            }
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                newAttrs[.strikethroughStyle] = strike
            }

            if let link = attrs[.link] {
                newAttrs[.link] = link
                newAttrs[.foregroundColor] = accent
                newAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            // Stripping .backgroundColor guarantees no dark boxes on the note paper

            if let attachment = attrs[.attachment] as? NSTextAttachment {
                var imageFilename = attrs[NSAttributedString.Key.psImageSource] as? String
                if imageFilename == nil, let img = attachment.image {
                    imageFilename = AttachmentManager.shared.saveImage(img)
                }
                if let imageFilename {
                    newAttrs[NSAttributedString.Key.psImageSource] = imageFilename
                    newAttrs[NSAttributedString.Key.psImageAlt] = attrs[NSAttributedString.Key.psImageAlt] as? String ?? "Image"
                }
                newAttrs[.attachment] = attachment
            }

            result.append(NSAttributedString(string: substring, attributes: newAttrs))
        }

        return result
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let uti = UTType(filenameExtension: url.pathExtension), uti.conforms(to: .image) {
                    if let filename = AttachmentManager.shared.saveFile(from: url) {
                        var point = convert(sender.draggingLocation, from: nil)
                        point.x -= textContainerOrigin.x
                        point.y -= textContainerOrigin.y
                        if let layoutManager = layoutManager, let textContainer = textContainer {
                            let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
                            let charIdx = layoutManager.characterIndexForGlyph(at: glyph)
                            setSelectedRange(NSRange(location: charIdx, length: 0))
                        }
                        insertImageAttachment(filename: filename, alt: url.deletingPathExtension().lastPathComponent)
                        return true
                    }
                }
            }
        }
        if let image = NSImage(pasteboard: pboard), let filename = AttachmentManager.shared.saveImage(image) {
            insertImageAttachment(filename: filename, alt: "Image")
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - Image Attachments & Dynamic Width

    var effectiveContentWidth: CGFloat {
        if let container = textContainer, container.size.width > 120 {
            return container.size.width
        }
        if bounds.width > 120 {
            return bounds.width
        }
        if let scroll = enclosingScrollView, scroll.contentSize.width > 120 {
            return scroll.contentSize.width
        }
        return max(360, AppPreferences.shared.noteSize.width)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = bounds.width
        super.setFrameSize(newSize)
        if abs(newSize.width - oldWidth) > 20 && newSize.width > 150 {
            adjustImageAttachmentsForCurrentWidth()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            adjustImageAttachmentsForCurrentWidth()
        }
    }

    private func adjustImageAttachmentsForCurrentWidth() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let currentWidth = effectiveContentWidth
        let targetWidth = max(160, min(currentWidth - 36, 560))

        storage.enumerateAttribute(NSAttributedString.Key.psImageSource, in: NSRange(location: 0, length: storage.length), options: []) { val, range, _ in
            guard let filename = val as? String,
                  let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { return }

            var image: NSImage?
            if let loaded = AttachmentManager.shared.loadImage(named: filename) {
                image = loaded
            } else if let localURL = URL(string: filename), localURL.isFileURL, let loaded = NSImage(contentsOf: localURL) {
                image = loaded
            } else if let loaded = NSImage(contentsOfFile: filename) {
                image = loaded
            }

            guard let img = image else { return }
            let origW = max(1, img.size.width)
            let origH = max(1, img.size.height)
            let scale = origW > targetWidth ? (targetWidth / origW) : 1.0
            let displayWidth = max(80, min(origW * scale, targetWidth))
            let displayHeight = max(40, origH * (displayWidth / origW))
            let displaySize = NSSize(width: displayWidth, height: displayHeight)

            if abs(attachment.bounds.width - displayWidth) > 5 {
                let rounded = NSImage(size: displaySize, flipped: false) { rect in
                    let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                    path.addClip()
                    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    return true
                }

                attachment.image = rounded
                attachment.bounds = NSRect(origin: NSPoint(x: 0, y: -4), size: displaySize)
                layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager?.invalidateDisplay(forCharacterRange: range)
            }
        }
    }

    func makeImageAttachment(filename: String, alt: String, maxWidth: CGFloat) -> NSAttributedString {
        var image: NSImage?
        if let loaded = AttachmentManager.shared.loadImage(named: filename) {
            image = loaded
        } else if let localURL = URL(string: filename), localURL.isFileURL, let loaded = NSImage(contentsOf: localURL) {
            image = loaded
        } else if let loaded = NSImage(contentsOfFile: filename) {
            image = loaded
        }

        let attachment = NSTextAttachment()
        let usableWidth = maxWidth > 120 ? maxWidth : effectiveContentWidth
        let targetWidth = max(160, min(usableWidth - 36, 560))

        if let img = image {
            let originalSize = img.size
            let origW = max(1, originalSize.width)
            let origH = max(1, originalSize.height)
            let scale = origW > targetWidth ? (targetWidth / origW) : 1.0
            let displayWidth = max(80, min(origW * scale, targetWidth))
            let displayHeight = max(40, origH * (displayWidth / origW))
            let displaySize = NSSize(width: displayWidth, height: displayHeight)

            let rounded = NSImage(size: displaySize, flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                path.addClip()
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                return true
            }

            attachment.image = rounded
            attachment.bounds = NSRect(origin: NSPoint(x: 0, y: -4), size: displaySize)
        } else {
            let displaySize = NSSize(width: targetWidth, height: 42)
            let placeholder = NSImage(size: displaySize)
            placeholder.lockFocus()
            let rect = NSRect(origin: .zero, size: displaySize)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSColor.quaternaryLabelColor.setFill()
            path.fill()
            let title = "🖼 \(alt.isEmpty ? filename : alt)" as NSString
            title.draw(at: NSPoint(x: 12, y: 12), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            placeholder.unlockFocus()
            attachment.image = placeholder
            attachment.bounds = NSRect(origin: NSPoint(x: 0, y: -4), size: displaySize)
        }

        let attrString = NSMutableAttributedString(attachment: attachment)
        attrString.addAttributes([
            NSAttributedString.Key.psImageSource: filename,
            NSAttributedString.Key.psImageAlt: alt
        ], range: NSRange(location: 0, length: attrString.length))
        return attrString
    }

    func insertImageAttachment(filename: String, alt: String) {
        let selected = selectedRange()
        let imageAttr = makeImageAttachment(filename: filename, alt: alt, maxWidth: effectiveContentWidth)

        let prefix = selected.location > 0 ? "\n" : ""
        let replacement = NSMutableAttributedString(string: prefix)
        replacement.append(imageAttr)
        replacement.append(NSAttributedString(string: "\n\n"))

        if shouldChangeText(in: selected, replacementString: replacement.string) {
            textStorage?.replaceCharacters(in: selected, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: selected.location + replacement.length, length: 0))
        }
    }

    // MARK: - Load & Serialize (Full Rich Text Preservation via Standard Markdown)

    func loadContent(_ raw: String) {
        let containerWidth = effectiveContentWidth
        let attrString = NSMutableAttributedString()
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 3
        pStyle.paragraphSpacing = 6

        let lines = raw.components(separatedBy: "\n")

        for (lineIdx, rawLine) in lines.enumerated() {
            var line = rawLine
            var role: String = "body"
            var isChecklist = false
            var isChecked = false

            // Convert markdown prefixes to roles and checklists
            if line.hasPrefix("# ") {
                role = "title"
                line.removeFirst(2)
            } else if line.hasPrefix("## ") {
                role = "heading"
                line.removeFirst(3)
            } else if line.hasPrefix("### ") {
                role = "subheading"
                line.removeFirst(4)
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") || line.hasPrefix("☑ ") || line.hasPrefix("✓ ") {
                isChecklist = true
                isChecked = true
                if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { line.removeFirst(6) }
                else if line.hasPrefix("☑ ") || line.hasPrefix("✓ ") { line.removeFirst(2) }
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("☐ ") || line.hasPrefix("◯ ") || line.hasPrefix("○ ") {
                isChecklist = true
                isChecked = false
                if line.hasPrefix("- [ ] ") { line.removeFirst(6) }
                else if line.hasPrefix("☐ ") || line.hasPrefix("◯ ") || line.hasPrefix("○ ") { line.removeFirst(2) }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            }

            if isChecklist {
                while line.hasPrefix(" ") {
                    line.removeFirst()
                }
            }

            let lineAttr = NSMutableAttributedString()

            if isChecklist {
                let box = makeCheckboxAttachment(checked: isChecked)
                lineAttr.append(box)
                lineAttr.append(NSAttributedString(string: " "))
            }

            // Parse inline formatting (images, bold, italic, underline, strikethrough, code, links)
            let parsedLine = parseInlineMarkdown(line, role: role, maxWidth: containerWidth)
            lineAttr.append(parsedLine)

            let fullLineRange = NSRange(location: 0, length: lineAttr.length)
            let ink = NSColor(currentPalette?.ink ?? Color.primary)

            lineAttr.addAttribute(.paragraphStyle, value: pStyle, range: fullLineRange)
            if role != "body" {
                lineAttr.addAttribute(NSAttributedString.Key.psStyleRole, value: role, range: fullLineRange)
            }

            if isChecked {
                let textStart = isChecklist ? min(2, lineAttr.length) : 0
                if textStart < lineAttr.length {
                    lineAttr.addAttributes([
                        .foregroundColor: ink.withAlphaComponent(0.45),
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ], range: NSRange(location: textStart, length: lineAttr.length - textStart))
                }
            }

            attrString.append(lineAttr)
            if lineIdx < lines.count - 1 {
                attrString.append(NSAttributedString(string: "\n"))
            }
        }

        let savedSelected = selectedRange()
        textStorage?.setAttributedString(attrString)
        let newLength = (string as NSString).length
        setSelectedRange(NSRange(location: min(savedSelected.location, newLength), length: 0))
    }

    private func parseInlineMarkdown(_ text: String, role: String, maxWidth: CGFloat) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString() }

        let result = NSMutableAttributedString()
        let imgPattern = #"!\[(.*?)\]\((.*?)\)"#
        guard let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: []) else {
            return parseTextChunkFormatting(text, role: role)
        }

        let nsText = text as NSString
        let matches = imgRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var currentIdx = 0
        for match in matches {
            if match.range.location > currentIdx {
                let textChunk = nsText.substring(with: NSRange(location: currentIdx, length: match.range.location - currentIdx))
                result.append(parseTextChunkFormatting(textChunk, role: role))
            }
            let alt = nsText.substring(with: match.range(at: 1))
            let source = nsText.substring(with: match.range(at: 2))
            result.append(makeImageAttachment(filename: source, alt: alt, maxWidth: maxWidth))
            currentIdx = match.range.location + match.range.length
        }

        if currentIdx < nsText.length {
            let textChunk = nsText.substring(with: NSRange(location: currentIdx, length: nsText.length - currentIdx))
            result.append(parseTextChunkFormatting(textChunk, role: role))
        }

        return result
    }

    private func parseTextChunkFormatting(_ text: String, role: String) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString() }
        let baseFont = fontForRole(role)
        let ink = NSColor(currentPalette?.ink ?? Color.primary)
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: ink
        ])

        // 1. Links [title](url)
        if let linkRegex = try? NSRegularExpression(pattern: #"\[(.*?)\]\((.*?)\)"#, options: []) {
            let matches = linkRegex.matches(in: attr.string, options: [], range: NSRange(location: 0, length: attr.length)).reversed()
            for m in matches {
                let ns = attr.string as NSString
                let title = ns.substring(with: m.range(at: 1))
                let url = ns.substring(with: m.range(at: 2))
                let rep = NSAttributedString(string: title, attributes: [
                    .font: baseFont,
                    .link: url,
                    .foregroundColor: NSColor(currentPalette?.accent ?? Color.blue),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ])
                attr.replaceCharacters(in: m.range, with: rep)
            }
        }

        // 2. Underline <u>...</u>
        applyTagPattern(#"<u>(.*?)</u>"#, to: attr, tagPrefixLen: 3, tagSuffixLen: 4) { range in
            attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }

        // 3. Strikethrough ~~...~~
        applyTagPattern(#"~~(.*?)~~"#, to: attr, tagPrefixLen: 2, tagSuffixLen: 2) { range in
            attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }

        // 4. Inline code `...`
        applyTagPattern(#"`([^`]+)`"#, to: attr, tagPrefixLen: 1, tagSuffixLen: 1) { range in
            attr.addAttribute(.font, value: fontForRole("mono"), range: range)
        }

        // 5. Bold + Italic ***...***
        applyTagPattern(#"\*\*\*(.*?)\*\*\*"#, to: attr, tagPrefixLen: 3, tagSuffixLen: 3) { range in
            attr.enumerateAttribute(.font, in: range, options: []) { val, subRange, _ in
                let curF = (val as? NSFont) ?? baseFont
                let b = NSFontManager.shared.convert(curF, toHaveTrait: .boldFontMask)
                let bi = NSFontManager.shared.convert(b, toHaveTrait: .italicFontMask)
                attr.addAttribute(.font, value: bi, range: subRange)
            }
        }

        // 6. Bold **...**
        applyTagPattern(#"\*\*(.*?)\*\*"#, to: attr, tagPrefixLen: 2, tagSuffixLen: 2) { range in
            attr.enumerateAttribute(.font, in: range, options: []) { val, subRange, _ in
                let curF = (val as? NSFont) ?? baseFont
                let b = NSFontManager.shared.convert(curF, toHaveTrait: .boldFontMask)
                attr.addAttribute(.font, value: b, range: subRange)
            }
        }

        // 7. Italic *...*
        applyTagPattern(#"\*(.*?)\*"#, to: attr, tagPrefixLen: 1, tagSuffixLen: 1) { range in
            attr.enumerateAttribute(.font, in: range, options: []) { val, subRange, _ in
                let curF = (val as? NSFont) ?? baseFont
                let i = NSFontManager.shared.convert(curF, toHaveTrait: .italicFontMask)
                attr.addAttribute(.font, value: i, range: subRange)
            }
        }

        return attr
    }

    private func applyTagPattern(_ pattern: String, to attr: NSMutableAttributedString, tagPrefixLen: Int, tagSuffixLen: Int, applyStyle: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: attr.string, options: [], range: NSRange(location: 0, length: attr.length)).reversed()
        for m in matches {
            let matchRange = m.range
            guard matchRange.length >= tagPrefixLen + tagSuffixLen else { continue }
            let contentRange = NSRange(location: matchRange.location + tagPrefixLen, length: matchRange.length - tagPrefixLen - tagSuffixLen)
            applyStyle(contentRange)

            let suffixRange = NSRange(location: matchRange.location + matchRange.length - tagSuffixLen, length: tagSuffixLen)
            attr.replaceCharacters(in: suffixRange, with: "")

            let prefixRange = NSRange(location: matchRange.location, length: tagPrefixLen)
            attr.replaceCharacters(in: prefixRange, with: "")
        }
    }

    func serializeContent() -> String {
        guard let storage = textStorage else { return string }
        let fullString = storage.string as NSString
        let totalLength = fullString.length
        guard totalLength > 0 else { return "" }

        var lines: [String] = []
        var lineStart = 0

        while lineStart < totalLength {
            let lineRange = fullString.lineRange(for: NSRange(location: lineStart, length: 0))

            // Check for checklist attachment in this line
            var isChecklist = false
            var isChecked = false
            var attachmentLength = 0

            let scanLimit = min(lineRange.location + 4, lineRange.location + lineRange.length)
            for i in lineRange.location..<scanLimit {
                if let checked = storage.attribute(.psChecklist, at: i, effectiveRange: nil) as? Bool {
                    isChecklist = true
                    isChecked = checked
                    attachmentLength = 1
                    if i + 1 < lineRange.location + lineRange.length {
                        let nextChar = fullString.substring(with: NSRange(location: i + 1, length: 1))
                        if nextChar == " " {
                            attachmentLength += 1
                        }
                    }
                    break
                }
            }

            var linePrefix = ""
            if isChecklist {
                linePrefix = isChecked ? "✓ " : "◯ "
            } else {
                if let role = storage.attribute(NSAttributedString.Key.psStyleRole, at: lineRange.location, effectiveRange: nil) as? String {
                    switch role {
                    case "title": linePrefix = "# "
                    case "heading": linePrefix = "## "
                    case "subheading": linePrefix = "### "
                    default: break
                    }
                }
            }

            // Determine content range excluding checklist attachment and line breaks
            var lineLengthWithoutNewline = lineRange.length
            while lineLengthWithoutNewline > 0 {
                let charCode = fullString.character(at: lineRange.location + lineLengthWithoutNewline - 1)
                if charCode == 10 || charCode == 13 { // \n or \r
                    lineLengthWithoutNewline -= 1
                } else {
                    break
                }
            }

            let contentStart = lineRange.location + attachmentLength
            let contentLength = max(0, (lineRange.location + lineLengthWithoutNewline) - contentStart)

            if contentLength == 0 {
                lines.append(linePrefix)
                lineStart = lineRange.location + lineRange.length
                continue
            }

            let evalRange = NSRange(location: contentStart, length: contentLength)

            struct FormattedSpan {
                var text: String
                var isBold: Bool
                var isItalic: Bool
                var isMono: Bool
                var isUnderline: Bool
                var isStrike: Bool
                var link: String?
                var image: (alt: String, src: String)?
            }

            var spans: [FormattedSpan] = []

            storage.enumerateAttributes(in: evalRange, options: []) { attrs, range, _ in
                if let imageSource = attrs[NSAttributedString.Key.psImageSource] as? String {
                    let alt = attrs[NSAttributedString.Key.psImageAlt] as? String ?? "Image"
                    spans.append(FormattedSpan(text: "", isBold: false, isItalic: false, isMono: false, isUnderline: false, isStrike: false, link: nil, image: (alt: alt, src: imageSource)))
                    return
                } else if let attachment = attrs[.attachment] as? NSTextAttachment, let img = attachment.image {
                    if let savedFilename = AttachmentManager.shared.saveImage(img) {
                        spans.append(FormattedSpan(text: "", isBold: false, isItalic: false, isMono: false, isUnderline: false, isStrike: false, link: nil, image: (alt: "Image", src: savedFilename)))
                        return
                    }
                }

                let subText = fullString.substring(with: range)
                guard !subText.isEmpty else { return }

                var isBold = false
                var isItalic = false
                var isMono = false
                if let font = attrs[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    isBold = traits.contains(.boldFontMask)
                    isItalic = traits.contains(.italicFontMask)
                    let fName = font.fontName.lowercased()
                    isMono = font.isFixedPitch || fName.contains("mono") || fName.contains("menlo") || fName.contains("courier") || fName.contains("code")
                }

                let isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
                let isStrike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0

                var linkStr: String? = nil
                if let l = attrs[.link] {
                    linkStr = (l as? URL)?.absoluteString ?? (l as? String)
                }

                // If line itself is title or heading, avoid double-wrapping entire line in bold asterisks
                if linePrefix.hasPrefix("#") {
                    isBold = false
                }

                // If checklist is checked, do not duplicate strikethrough markdown
                let effectiveStrike = isChecklist && isChecked ? false : isStrike

                if let last = spans.last,
                   last.image == nil,
                   last.isBold == isBold,
                   last.isItalic == isItalic,
                   last.isMono == isMono,
                   last.isUnderline == isUnderline,
                   last.isStrike == effectiveStrike,
                   last.link == linkStr {
                    spans[spans.count - 1].text += subText
                } else {
                    spans.append(FormattedSpan(
                        text: subText,
                        isBold: isBold,
                        isItalic: isItalic,
                        isMono: isMono,
                        isUnderline: isUnderline,
                        isStrike: effectiveStrike,
                        link: linkStr,
                        image: nil
                    ))
                }
            }

            var lineResult = ""
            for span in spans {
                if let img = span.image {
                    lineResult += "![\(img.alt)](\(img.src))"
                    continue
                }

                let text = span.text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lineResult += text
                    continue
                }

                let leadingSpaces = String(text.prefix(while: { $0.isWhitespace }))
                let trailingSpaces = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
                let coreStart = text.index(text.startIndex, offsetBy: leadingSpaces.count)
                let coreEnd = text.index(text.endIndex, offsetBy: -trailingSpaces.count)
                var core = String(text[coreStart..<coreEnd])

                if span.isMono {
                    core = "`\(core)`"
                }
                if span.isStrike {
                    core = "~~\(core)~~"
                }
                if span.isUnderline {
                    core = "<u>\(core)</u>"
                }
                if span.isBold && span.isItalic {
                    core = "***\(core)***"
                } else if span.isBold {
                    core = "**\(core)**"
                } else if span.isItalic {
                    core = "*\(core)*"
                }
                if let link = span.link {
                    core = "[\(core)](\(link))"
                }

                lineResult += String(leadingSpaces) + core + String(trailingSpaces)
            }

            lines.append(linePrefix + lineResult.trimmingCharacters(in: .newlines))
            lineStart = lineRange.location + lineRange.length
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Native Rich Text Formatting (NO MARKDOWN TAGS)

    private func stripListPrefixes(in range: NSRange) {
        guard let storage = textStorage else { return }
        let line = (storage.string as NSString).substring(with: range)

        // Check if line starts with circular checkbox attachment
        if range.length > 0 && storage.attribute(.psChecklist, at: range.location, effectiveRange: nil) != nil {
            let removeLen = min(2, range.length)
            let r = NSRange(location: range.location, length: removeLen)
            storage.replaceCharacters(in: r, with: "")
            return
        }

        let prefixes = ["• ", "– ", "1. ", "2. ", "3. ", "4. ", "5. ", "▍ "]
        for p in prefixes {
            if line.hasPrefix(p) {
                let r = NSRange(location: range.location, length: p.count)
                storage.replaceCharacters(in: r, with: "")
                break
            }
        }
    }

    func setTitle() {
        let selected = selectedRange()
        let fullText = (string as NSString)
        let lineRange = fullText.lineRange(for: NSRange(location: min(selected.location, fullText.length), length: 0))
        guard let storage = textStorage else { return }

        stripListPrefixes(in: lineRange)
        let updatedLineRange = (storage.string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))

        storage.addAttribute(.font, value: fontForRole("title"), range: updatedLineRange)
        storage.addAttribute(NSAttributedString.Key.psStyleRole, value: "title", range: updatedLineRange)
        didChangeText()
    }

    func setHeading() {
        let selected = selectedRange()
        let fullText = (string as NSString)
        let lineRange = fullText.lineRange(for: NSRange(location: min(selected.location, fullText.length), length: 0))
        guard let storage = textStorage else { return }

        stripListPrefixes(in: lineRange)
        let updatedLineRange = (storage.string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))

        storage.addAttribute(.font, value: fontForRole("heading"), range: updatedLineRange)
        storage.addAttribute(NSAttributedString.Key.psStyleRole, value: "heading", range: updatedLineRange)
        didChangeText()
    }

    func setSubheading() {
        let selected = selectedRange()
        let fullText = (string as NSString)
        let lineRange = fullText.lineRange(for: NSRange(location: min(selected.location, fullText.length), length: 0))
        guard let storage = textStorage else { return }

        stripListPrefixes(in: lineRange)
        let updatedLineRange = (storage.string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))

        storage.addAttribute(.font, value: fontForRole("subheading"), range: updatedLineRange)
        storage.addAttribute(NSAttributedString.Key.psStyleRole, value: "subheading", range: updatedLineRange)
        didChangeText()
    }

    func setBody() {
        let selected = selectedRange()
        let fullText = (string as NSString)
        let lineRange = fullText.lineRange(for: NSRange(location: min(selected.location, fullText.length), length: 0))
        guard let storage = textStorage else { return }

        stripListPrefixes(in: lineRange)
        let updatedLineRange = (storage.string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))

        storage.addAttribute(.font, value: fontForRole("body"), range: updatedLineRange)
        storage.removeAttribute(NSAttributedString.Key.psStyleRole, range: updatedLineRange)
        didChangeText()
    }

    func setMonostyled() {
        let selected = selectedRange()
        guard let storage = textStorage else { return }
        let range = selected.length > 0 ? selected : (string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))
        storage.addAttribute(.font, value: fontForRole("mono"), range: range)
        didChangeText()
    }

    func toggleBold() {
        let selected = selectedRange()
        guard let storage = textStorage, selected.length > 0 else { return }
        guard shouldChangeText(in: selected, replacementString: nil) else { return }

        var isAllBold = true
        storage.enumerateAttribute(.font, in: selected, options: []) { val, _, stop in
            if let f = val as? NSFont {
                if !NSFontManager.shared.traits(of: f).contains(.boldFontMask) {
                    isAllBold = false
                    stop.pointee = true
                }
            }
        }

        storage.enumerateAttribute(.font, in: selected, options: []) { val, range, _ in
            let f = (val as? NSFont) ?? fontForRole(nil)
            let newF = isAllBold ? NSFontManager.shared.convert(f, toNotHaveTrait: .boldFontMask) : NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: newF, range: range)
        }
        didChangeText()
    }

    func toggleItalic() {
        let selected = selectedRange()
        guard let storage = textStorage, selected.length > 0 else { return }
        guard shouldChangeText(in: selected, replacementString: nil) else { return }

        var isAllItalic = true
        storage.enumerateAttribute(.font, in: selected, options: []) { val, _, stop in
            if let f = val as? NSFont {
                if !NSFontManager.shared.traits(of: f).contains(.italicFontMask) {
                    isAllItalic = false
                    stop.pointee = true
                }
            }
        }

        storage.enumerateAttribute(.font, in: selected, options: []) { val, range, _ in
            let f = (val as? NSFont) ?? fontForRole(nil)
            let newF = isAllItalic ? NSFontManager.shared.convert(f, toNotHaveTrait: .italicFontMask) : NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: newF, range: range)
        }
        didChangeText()
    }

    func toggleUnderline() {
        let selected = selectedRange()
        guard let storage = textStorage, selected.length > 0 else { return }
        guard shouldChangeText(in: selected, replacementString: nil) else { return }

        var hasUnderline = false
        if let style = storage.attribute(.underlineStyle, at: selected.location, effectiveRange: nil) as? Int, style != 0 {
            hasUnderline = true
        }

        if hasUnderline {
            storage.removeAttribute(.underlineStyle, range: selected)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selected)
        }
        didChangeText()
    }

    func toggleStrikethrough() {
        let selected = selectedRange()
        guard let storage = textStorage, selected.length > 0 else { return }
        guard shouldChangeText(in: selected, replacementString: nil) else { return }

        var hasStrike = false
        if let style = storage.attribute(.strikethroughStyle, at: selected.location, effectiveRange: nil) as? Int, style != 0 {
            hasStrike = true
        }

        if hasStrike {
            storage.removeAttribute(.strikethroughStyle, range: selected)
        } else {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: selected)
        }
        didChangeText()
    }

    func toggleChecklist() {
        guard let storage = textStorage else { return }
        let selected = selectedRange()
        let fullText = (string as NSString)
        let lineRange = fullText.lineRange(for: NSRange(location: min(selected.location, fullText.length), length: 0))

        // If line already has checklist circle, remove it
        var existingBoxIndex: Int? = nil
        let scanEnd = min(lineRange.location + 8, lineRange.location + lineRange.length)
        for i in lineRange.location..<scanEnd {
            if storage.attribute(.psChecklist, at: i, effectiveRange: nil) != nil {
                existingBoxIndex = i
                break
            }
        }

        if let boxIdx = existingBoxIndex {
            var removeLen = 1
            if boxIdx + 1 < lineRange.location + lineRange.length {
                if fullText.substring(with: NSRange(location: boxIdx + 1, length: 1)) == " " {
                    removeLen += 1
                }
            }
            let removeRange = NSRange(location: boxIdx, length: removeLen)
            guard shouldChangeText(in: removeRange, replacementString: "") else { return }
            storage.replaceCharacters(in: removeRange, with: "")

            let updatedLineRange = (storage.string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))
            storage.removeAttribute(.strikethroughStyle, range: updatedLineRange)
            let ink = NSColor(currentPalette?.ink ?? Color.primary)
            storage.addAttribute(.foregroundColor, value: ink, range: updatedLineRange)

            didChangeText()
            setSelectedRange(NSRange(location: min(selected.location, storage.length), length: 0))
            return
        }

        // Clean any other list prefixes
        stripListPrefixes(in: lineRange)
        let updatedRange = (storage.string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))

        let box = makeCheckboxAttachment(checked: false)
        let insertAttr = NSMutableAttributedString()
        insertAttr.append(box)
        insertAttr.append(NSAttributedString(string: " "))

        let targetRange = NSRange(location: updatedRange.location, length: 0)
        guard shouldChangeText(in: targetRange, replacementString: insertAttr.string) else { return }
        storage.replaceCharacters(in: targetRange, with: insertAttr)
        didChangeText()
        setSelectedRange(NSRange(location: updatedRange.location + insertAttr.length, length: 0))
    }

    func toggleBulletList() { togglePrefix("• ") }
    func toggleDashedList() { togglePrefix("– ") }
    func toggleNumberedList() { togglePrefix("1. ") }
    func toggleBlockQuote() { togglePrefix("▍ ") }

    private func togglePrefix(_ prefix: String) {
        guard let storage = textStorage else { return }
        let selected = selectedRange()
        let fullText = (string as NSString)
        let lineRange = fullText.lineRange(for: NSRange(location: min(selected.location, fullText.length), length: 0))
        let line = fullText.substring(with: lineRange)

        if line.hasPrefix(prefix) {
            let r = NSRange(location: lineRange.location, length: prefix.count)
            guard shouldChangeText(in: r, replacementString: "") else { return }
            storage.replaceCharacters(in: r, with: "")
            didChangeText()
            return
        }

        stripListPrefixes(in: lineRange)
        let updatedRange = (storage.string as NSString).lineRange(for: NSRange(location: min(selected.location, storage.length), length: 0))
        let targetRange = NSRange(location: updatedRange.location, length: 0)
        guard shouldChangeText(in: targetRange, replacementString: prefix) else { return }
        storage.replaceCharacters(in: targetRange, with: prefix)
        didChangeText()
    }
}
