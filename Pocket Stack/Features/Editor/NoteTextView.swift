import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import SwiftUI

struct NoteTextView: View {
    @Binding var text: String
    let noteID: UUID
    let bridge: EditorBridge
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat
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
        .background(EditorWindowLocator(bridge: bridge))
        .onExitCommand { onCommand(.escape) }
    }

    private var configuration: MarkdownEditorConfiguration {
        let ink = NSColor(palette.ink)
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
            services: PocketStackMarkdownServices.value,
            textInsets: TextInsets(horizontal: 16, vertical: 14),
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
    static let value = MarkdownEditorServices(
        images: PocketStackImageProvider(),
        syntaxHighlighter: HighlighterSwiftBridge(),
        latex: SwiftMathBridge()
    )
}

private struct PocketStackImageProvider: EmbeddedImageProvider, @unchecked Sendable {
    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        AttachmentManager.shared.loadImage(named: reference.name)
    }

    func fingerprint() -> AnyHashable { 0 }
}

private struct EditorWindowLocator: NSViewRepresentable {
    let bridge: EditorBridge

    func makeNSView(context: Context) -> WindowLocatorView {
        let view = WindowLocatorView()
        view.onWindowChange = { [weak bridge] window in
            bridge?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowLocatorView, context: Context) {
        nsView.onWindowChange = { [weak bridge] window in
            bridge?.attach(to: window)
        }
        bridge.attach(to: nsView.window)
    }
}

private final class WindowLocatorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

enum EditorCommand {
    case escape, toggleTask, togglePin, cycleColor, delete, archive, increaseFont, decreaseFont
    case formatTitle, formatHeading, formatSubheading, formatBody, formatMonospaced
    case formatBold, formatItalic, formatStrikethrough, formatUnderline
    case formatBulletList, formatDashList, formatNumberList, formatCheckList
    case insertTable, insertImage, insertLink, insertCodeBlock, insertInlineMath, insertDisplayMath
}
