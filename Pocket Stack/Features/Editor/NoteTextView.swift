import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import SwiftUI

struct NoteTextView: View {
    @Binding var text: String
    let noteID: UUID
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat
    var heightBehavior: MarkdownEditorConfiguration.HeightBehavior = .scrolls
    let onCommand: (EditorCommand) -> Void

    var body: some View {
        NativeTextViewWrapper(
            text: $text,
            configuration: configuration,
            fontName: fontName,
            fontSize: fontSize,
            documentId: noteID.uuidString,
            onPasteImage: pasteImage
        )
        .onExitCommand { onCommand(.escape) }
    }

    private var configuration: MarkdownEditorConfiguration {
        let ink = NSColor(palette.ink)
        let paper = NSColor(palette.paper)
        let accent = NSColor(palette.accent)
        let theme = MarkdownEditorTheme(
            bodyText: ink,
            mutedText: ink.withAlphaComponent(0.48),
            disabledText: ink.withAlphaComponent(0.3),
            headingMarker: accent,
            link: accent,
            incompleteLink: accent.withAlphaComponent(0.7),
            findMatchHighlight: accent.withAlphaComponent(0.28),
            findCurrentMatchHighlight: accent.withAlphaComponent(0.5),
            latexLightModeText: ink,
            latexDarkModeText: ink,
            strikethroughColor: ink.withAlphaComponent(0.55),
            highlightColor: accent.withAlphaComponent(0.24)
        )
        return MarkdownEditorConfiguration(
            theme: theme,
            services: PocketStackMarkdownServices.value(ink: ink, paper: paper),
            textInsets: TextInsets(horizontal: 16, vertical: 14),
            heightBehavior: heightBehavior,
            extensions: [HighlightExtension(), StrikethroughExtension()]
        )
    }

    private func pasteImage(from pasteboard: NSPasteboard) -> String? {
        if let url = PasteboardImageReader.imageFileURL(from: pasteboard),
           let filename = AttachmentManager.shared.saveFile(from: url) {
            return "![Image](\(filename))"
        }
        if let data = PasteboardImageReader.imageData(from: pasteboard),
           let image = NSImage(data: data),
           let filename = AttachmentManager.shared.saveImage(image) {
            return "![Image](\(filename))"
        }
        return nil
    }
}

private enum PocketStackMarkdownServices {
    private static let lightHighlighter = HighlighterSwiftBridge(autoSwitchAppearance: false)
    private static let darkHighlighter = HighlighterSwiftBridge(
        lightTheme: "atom-one-dark",
        autoSwitchAppearance: false
    )

    static func value(ink: NSColor, paper: NSColor) -> MarkdownEditorServices {
        let usesDarkCodeTheme = paper.relativeLuminance < 0.5
        let highlighter = PaletteSyntaxHighlighter(
            base: usesDarkCodeTheme ? darkHighlighter : lightHighlighter,
            background: ink.withAlphaComponent(usesDarkCodeTheme ? 0.16 : 0.1)
        )
        return MarkdownEditorServices(
            images: PocketStackImageProvider(fingerprintValue: colorKey(ink: ink, paper: paper)),
            syntaxHighlighter: highlighter,
            latex: SwiftMathBridge()
        )
    }

    private static func colorKey(ink: NSColor, paper: NSColor) -> String {
        [ink, paper]
            .compactMap { $0.usingColorSpace(.sRGB) }
            .map { color in
                String(format: "%.4f,%.4f,%.4f,%.4f", color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
            }
            .joined(separator: "|")
    }
}

private struct PocketStackImageProvider: EmbeddedImageProvider, @unchecked Sendable {
    let fingerprintValue: String

    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        AttachmentManager.shared.loadImage(named: reference.name)
    }

    func fingerprint() -> AnyHashable { fingerprintValue }
}

private struct PaletteSyntaxHighlighter: SyntaxHighlighter, @unchecked Sendable {
    let base: HighlighterSwiftBridge
    let background: NSColor

    func codeFont(size: CGFloat) -> NSFont {
        base.codeFont(size: size)
    }

    func backgroundColor() -> NSColor {
        background
    }

    func highlight(code: String, language: String?) -> NSAttributedString? {
        base.highlight(code: code, language: language)
    }

    var appearanceDidChangeNotification: Notification.Name? { nil }
}

private extension NSColor {
    var relativeLuminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
    }
}

enum EditorCommand {
    case escape, toggleTask, togglePin, cycleColor, delete, archive, increaseFont, decreaseFont
    case formatTitle, formatHeading, formatSubheading, formatBody, formatMonospaced
    case formatBold, formatItalic, formatStrikethrough, formatUnderline
    case formatBulletList, formatDashList, formatNumberList, formatCheckList
    case insertTable, insertImage, insertLink, insertCodeBlock, insertInlineMath, insertDisplayMath
}
