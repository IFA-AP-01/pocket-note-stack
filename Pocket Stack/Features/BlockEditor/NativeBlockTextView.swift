import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import SwiftUI

private extension NSAttributedString.Key {
    static let blockBold = Self("PocketStack.block.bold")
    static let blockItalic = Self("PocketStack.block.italic")
    static let blockStrike = Self("PocketStack.block.strike")
    static let blockUnderline = Self("PocketStack.block.underline")
    static let blockCode = Self("PocketStack.block.code")
    static let blockMath = Self("PocketStack.block.math")
}

@MainActor
final class WYSIWYGTextView: NSTextView {
    var commandHandler: ((EditorCommand, NSTextView) -> Bool)?
    var imageHandler: ((String) -> Void)?
    var documentCopyHandler: (() -> Bool)?
    var documentSelectAllHandler: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return NSSize(width: NSView.noIntrinsicMetric, height: 24) }
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 24))
    }

    override func layout() {
        super.layout()
        textContainer?.containerSize.width = max(bounds.width - textContainerInset.width * 2, 1)
        invalidateIntrinsicContentSize()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let command: EditorCommand?
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": command = .formatBold
        case "i": command = .formatItalic
        case "u": command = .formatUnderline
        case "c":
            copy(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "a":
            selectAll(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default: command = nil
        }
        if let command, commandHandler?(command, self) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func copy(_ sender: Any?) {
        if documentCopyHandler?() != true { super.copy(sender) }
    }

    override func selectAll(_ sender: Any?) {
        if let documentSelectAllHandler { documentSelectAllHandler() }
        else { super.selectAll(sender) }
    }

    func characterIndex(screenX: CGFloat, fromBottom: Bool) -> Int {
        guard let window, let layoutManager, let textContainer else { return fromBottom ? (string as NSString).length : 0 }
        layoutManager.ensureLayout(for: textContainer)
        let windowPoint = window.convertPoint(fromScreen: NSPoint(x: screenX, y: 0))
        let localX = convert(windowPoint, from: nil).x - textContainerOrigin.x
        let used = layoutManager.usedRect(for: textContainer)
        let y = fromBottom ? max(used.maxY - 1, used.minY) : used.minY + 1
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: localX, y: y), in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }
}

struct NativeBlockTextView: NSViewRepresentable {
    let surfaceID: EditorSurfaceID
    let content: RichText
    let style: BlockTextStyle
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat
    let editor: BlockEditorModel

    func makeCoordinator() -> Coordinator {
        Coordinator(surfaceID: surfaceID, style: style, palette: palette, fontName: fontName, fontSize: fontSize, editor: editor)
    }

    func makeNSView(context: Context) -> WYSIWYGTextView {
        let view = WYSIWYGTextView(frame: .zero)
        view.delegate = context.coordinator
        view.commandHandler = context.coordinator.handleEditorCommand
        view.imageHandler = { [weak editor] source in
            editor?.insert(.image(ImageBlock(alt: "Image", source: source, title: nil)), after: surfaceID)
        }
        view.documentCopyHandler = { [weak editor] in editor?.copyDocumentSelection() ?? false }
        view.documentSelectAllHandler = { [weak editor] in editor?.selectAllDocument() }
        let selectionPan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSelectionPan(_:)))
        selectionPan.buttonMask = 0x1
        selectionPan.delaysPrimaryMouseButtonEvents = false
        selectionPan.delegate = context.coordinator
        view.addGestureRecognizer(selectionPan)
        view.isRichText = true
        view.importsGraphics = false
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainerInset = NSSize(width: 2, height: 3)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.allowsUndo = true
        context.coordinator.install(content, in: view)
        editor.focusRegistry.register(view, for: surfaceID)
        return view
    }

    func updateNSView(_ view: WYSIWYGTextView, context: Context) {
        context.coordinator.update(style: style, palette: palette, fontName: fontName, fontSize: fontSize)
        context.coordinator.updateIfNeeded(content, in: view)
    }

    static func dismantleNSView(_ view: WYSIWYGTextView, coordinator: Coordinator) {
        if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
        view.delegate = nil
        view.commandHandler = nil
        view.imageHandler = nil
        view.documentCopyHandler = nil
        view.documentSelectAllHandler = nil
        view.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.editor.focusRegistry.unregister(coordinator.surfaceID, view: view)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSGestureRecognizerDelegate {
        let surfaceID: EditorSurfaceID
        let editor: BlockEditorModel
        private var style: BlockTextStyle
        private var palette: NotePaletteColor
        private var fontName: String
        private var fontSize: CGFloat
        private var isInstalling = false
        private var lastContent: RichText?
        private static let mathRenderer = SwiftMathBridge()
        private static let syntaxHighlighter = HighlighterSwiftBridge(autoSwitchAppearance: true)

        init(surfaceID: EditorSurfaceID, style: BlockTextStyle, palette: NotePaletteColor, fontName: String, fontSize: CGFloat, editor: BlockEditorModel) {
            self.surfaceID = surfaceID
            self.style = style
            self.palette = palette
            self.fontName = fontName
            self.fontSize = fontSize
            self.editor = editor
        }

        func update(style: BlockTextStyle, palette: NotePaletteColor, fontName: String, fontSize: CGFloat) {
            self.style = style
            self.palette = palette
            self.fontName = fontName
            self.fontSize = fontSize
        }

        func install(_ content: RichText, in textView: NSTextView) {
            isInstalling = true
            textView.textStorage?.setAttributedString(attributedString(for: content))
            lastContent = content
            isInstalling = false
            textView.invalidateIntrinsicContentSize()
        }

        func updateIfNeeded(_ content: RichText, in textView: NSTextView) {
            guard content != lastContent, textView.window?.firstResponder !== textView else { return }
            install(content, in: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            editor.focusRegistry.clearSelections(except: surfaceID)
            editor.setSelected(surfaceID)
        }

        @objc func handleSelectionPan(_ recognizer: NSPanGestureRecognizer) {
            guard let textView = recognizer.view as? WYSIWYGTextView, let window = textView.window else { return }
            let currentPoint = recognizer.location(in: textView)
            switch recognizer.state {
            case .began:
                let translation = recognizer.translation(in: textView)
                let origin = NSPoint(x: currentPoint.x - translation.x, y: currentPoint.y - translation.y)
                editor.beginDocumentSelection(at: surfaceID, characterIndex: textView.characterIndexForInsertion(at: origin))
                fallthrough
            case .changed:
                let windowPoint = textView.convert(currentPoint, to: nil)
                editor.extendDocumentSelection(to: window.convertPoint(toScreen: windowPoint))
            case .ended:
                let windowPoint = textView.convert(currentPoint, to: nil)
                editor.extendDocumentSelection(to: window.convertPoint(toScreen: windowPoint))
                editor.finishDocumentSelection()
            case .cancelled, .failed:
                editor.finishDocumentSelection()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }

        func textDidChange(_ notification: Notification) {
            guard !isInstalling, let textView = notification.object as? NSTextView else { return }
            isInstalling = true
            restyle(textView)
            isInstalling = false
            let richText = model(from: textView.attributedString())
            lastContent = richText
            editor.update(richText, at: surfaceID)
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText(), textView.selectedRange().length == 0 else { return false }
            let range = textView.selectedRange()
            let length = (textView.string as NSString).length
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if case .code = style { return false }
                editor.split(surfaceID, at: range.location)
                return true
            case #selector(NSResponder.deleteBackward(_:)) where range.location == 0:
                return editor.mergeBackward(surfaceID)
            case #selector(NSResponder.moveLeft(_:)) where range.location == 0:
                editor.move(from: surfaceID, direction: .previous, screenX: nil)
                return true
            case #selector(NSResponder.moveRight(_:)) where range.location == length:
                editor.move(from: surfaceID, direction: .next, screenX: nil)
                return true
            case #selector(NSResponder.moveUp(_:)) where isOnBoundaryLine(textView, first: true):
                editor.move(from: surfaceID, direction: .up, screenX: caretScreenX(textView))
                return true
            case #selector(NSResponder.moveDown(_:)) where isOnBoundaryLine(textView, first: false):
                editor.move(from: surfaceID, direction: .down, screenX: caretScreenX(textView))
                return true
            default:
                return false
            }
        }

        func handleEditorCommand(_ command: EditorCommand, _ textView: NSTextView) -> Bool {
            switch command {
            case .formatBold: toggle(.blockBold, in: textView); return true
            case .formatItalic: toggle(.blockItalic, in: textView); return true
            case .formatStrikethrough: toggle(.blockStrike, in: textView); return true
            case .formatUnderline: toggle(.blockUnderline, in: textView); return true
            case .formatMonospaced: toggle(.blockCode, in: textView); return true
            case .formatTitle: editor.transformActiveBlock { .heading(level: 1, content: $0) }; return true
            case .formatHeading: editor.transformActiveBlock { .heading(level: 2, content: $0) }; return true
            case .formatSubheading: editor.transformActiveBlock { .heading(level: 3, content: $0) }; return true
            case .formatBody: editor.transformActiveBlock { .paragraph($0) }; return true
            case .formatBulletList: editor.transformActiveBlock(to: .unordered(marker: .bullet)); return true
            case .formatDashList: editor.transformActiveBlock(to: .unordered(marker: .dash)); return true
            case .formatNumberList: editor.transformActiveBlock(to: .ordered(start: 1)); return true
            case .formatCheckList, .toggleTask: editor.transformActiveBlockToTask(); return true
            case .insertInlineMath:
                insertInlineMath(in: textView); return true
            case .insertLink:
                applyLink(in: textView); return true
            case .insertCodeBlock:
                editor.insert(.code(CodeBlock(language: nil, code: "")), after: surfaceID); return true
            case .insertDisplayMath:
                editor.insert(.displayMath(DisplayMathBlock(latex: "x = y")), after: surfaceID); return true
            case .insertTable:
                let columns = [TableColumn(), TableColumn()]
                let table = TableBlock(
                    columns: columns,
                    header: TableRow(cells: columns.map { _ in TableCell(content: RichText(string: "Header")) }),
                    rows: [TableRow(cells: columns.map { _ in TableCell(content: RichText(string: "")) })]
                )
                editor.insert(.table(table), after: surfaceID); return true
            default: return false
            }
        }

        private func toggle(_ key: NSAttributedString.Key, in textView: NSTextView) {
            let range = textView.selectedRange()
            if range.length == 0 {
                var attributes = textView.typingAttributes
                attributes[key] = attributes[key] == nil ? true : nil
                textView.typingAttributes = attributes
                return
            }
            let hasValue = textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil) != nil
            if hasValue { textView.textStorage?.removeAttribute(key, range: range) }
            else { textView.textStorage?.addAttribute(key, value: true, range: range) }
            restyle(textView)
            textView.didChangeText()
            textView.setSelectedRange(range)
        }

        private func applyLink(in textView: NSTextView) {
            var range = textView.selectedRange()
            if range.length == 0 {
                textView.insertText("Link", replacementRange: range)
                range.length = 4
            }
            textView.textStorage?.addAttribute(.link, value: "https://", range: range)
            textView.didChangeText()
            textView.setSelectedRange(range)
        }

        private func insertInlineMath(in textView: NSTextView) {
            let attachment = mathAttachment(latex: "x")
            let value = NSMutableAttributedString(attachment: attachment)
            value.addAttribute(.blockMath, value: "x", range: NSRange(location: 0, length: value.length))
            textView.textStorage?.replaceCharacters(in: textView.selectedRange(), with: value)
            textView.didChangeText()
        }

        private func attributedString(for content: RichText) -> NSAttributedString {
            let result = NSMutableAttributedString(string: content.string, attributes: baseAttributes())
            let length = result.length
            for annotation in content.annotations {
                let range = NSIntersectionRange(annotation.range.nsRange, NSRange(location: 0, length: length))
                guard range.length > 0 else { continue }
                switch annotation.kind {
                case .bold: result.addAttribute(.blockBold, value: true, range: range)
                case .italic: result.addAttribute(.blockItalic, value: true, range: range)
                case .strikethrough: result.addAttribute(.blockStrike, value: true, range: range)
                case .underline: result.addAttribute(.blockUnderline, value: true, range: range)
                case .inlineCode: result.addAttribute(.blockCode, value: true, range: range)
                case .link(let destination, _): result.addAttribute(.link, value: destination, range: range)
                case .inlineMath(let latex):
                    let attachment = NSAttributedString(attachment: mathAttachment(latex: latex))
                    result.replaceCharacters(in: range, with: attachment)
                    result.addAttribute(.blockMath, value: latex, range: NSRange(location: range.location, length: 1))
                }
            }
            applyVisualAttributes(to: result)
            applyCodeHighlight(to: result)
            return result
        }

        private func model(from value: NSAttributedString) -> RichText {
            var annotations: [InlineAnnotation] = []
            let full = NSRange(location: 0, length: value.length)
            value.enumerateAttributes(in: full) { attributes, range, _ in
                if attributes[.blockBold] != nil { annotations.append(.init(range: .init(location: range.location, length: range.length), kind: .bold)) }
                if attributes[.blockItalic] != nil { annotations.append(.init(range: .init(location: range.location, length: range.length), kind: .italic)) }
                if attributes[.blockStrike] != nil { annotations.append(.init(range: .init(location: range.location, length: range.length), kind: .strikethrough)) }
                if attributes[.blockUnderline] != nil { annotations.append(.init(range: .init(location: range.location, length: range.length), kind: .underline)) }
                if attributes[.blockCode] != nil { annotations.append(.init(range: .init(location: range.location, length: range.length), kind: .inlineCode)) }
                if let destination = attributes[.link] as? String { annotations.append(.init(range: .init(location: range.location, length: range.length), kind: .link(destination: destination, title: nil))) }
                if let latex = attributes[.blockMath] as? String { annotations.append(.init(range: .init(location: range.location, length: range.length), kind: .inlineMath(latex: latex))) }
            }
            return RichText(string: value.string, annotations: annotations)
        }

        private func restyle(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            storage.addAttributes(baseAttributes(), range: NSRange(location: 0, length: storage.length))
            applyVisualAttributes(to: storage)
            applyCodeHighlight(to: storage)
        }

        private func applyVisualAttributes(to value: NSMutableAttributedString) {
            let full = NSRange(location: 0, length: value.length)
            value.enumerateAttributes(in: full) { attributes, range, _ in
                var font = baseFont()
                if attributes[.blockBold] != nil { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if attributes[.blockItalic] != nil { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if attributes[.blockCode] != nil { font = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) }
                value.addAttribute(.font, value: font, range: range)
                if attributes[.blockStrike] != nil { value.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
                if attributes[.blockUnderline] != nil { value.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
                if attributes[.blockCode] != nil { value.addAttribute(.backgroundColor, value: NSColor(palette.ink).withAlphaComponent(0.09), range: range) }
            }
        }

        private func applyCodeHighlight(to value: NSMutableAttributedString) {
            guard case .code(let language) = style,
                  let highlighted = Self.syntaxHighlighter.highlight(code: value.string, language: language),
                  highlighted.length == value.length else { return }
            highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attributes, range, _ in
                if let color = attributes[.foregroundColor] { value.addAttribute(.foregroundColor, value: color, range: range) }
                if let font = attributes[.font] { value.addAttribute(.font, value: font, range: range) }
            }
        }

        private func baseAttributes() -> [NSAttributedString.Key: Any] {
            [.font: baseFont(), .foregroundColor: NSColor(palette.ink)]
        }

        private func baseFont() -> NSFont {
            let size: CGFloat
            let weight: NSFont.Weight
            switch style {
            case .heading(let level): size = fontSize + CGFloat(max(7 - level, 1)) * 2; weight = level <= 2 ? .bold : .semibold
            case .code: size = fontSize; weight = .regular
            default: size = fontSize; weight = .regular
            }
            if case .code = style { return .monospacedSystemFont(ofSize: size, weight: weight) }
            return NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
        }

        private func mathAttachment(latex: String) -> NSTextAttachment {
            let attachment = NSTextAttachment()
            let ink = NSColor(palette.ink)
            let theme = MarkdownEditorTheme(latexLightModeText: ink, latexDarkModeText: ink)
            if let rendered = Self.mathRenderer.render(latex: latex, fontSize: fontSize, theme: theme) {
                attachment.image = rendered.image
                attachment.bounds = CGRect(origin: CGPoint(x: 0, y: rendered.baselineOffset), size: rendered.size)
            }
            return attachment
        }

        private func caretScreenX(_ textView: NSTextView) -> CGFloat? {
            var actual = NSRange()
            return textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: &actual).minX
        }

        private func isOnBoundaryLine(_ textView: NSTextView, first: Bool) -> Bool {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return true }
            let length = (textView.string as NSString).length
            if length == 0 { return true }
            let character = min(textView.selectedRange().location, max(length - 1, 0))
            let glyph = layout.glyphIndexForCharacter(at: character)
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let used = layout.usedRect(for: container)
            return first ? line.minY <= used.minY + 1 : line.maxY >= used.maxY - 1
        }
    }
}
