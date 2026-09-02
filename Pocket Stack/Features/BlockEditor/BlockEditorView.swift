import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

struct BlockEditorView: View {
    @Binding private var markdown: String
    @State private var editor: BlockEditorModel
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat
    let scrolls: Bool

    init(markdown: Binding<String>, palette: NotePaletteColor, fontName: String, fontSize: CGFloat, scrolls: Bool = true) {
        _markdown = markdown
        self.palette = palette
        self.fontName = fontName
        self.fontSize = fontSize
        self.scrolls = scrolls
        let binding = markdown
        _editor = State(initialValue: BlockEditorModel(markdown: markdown.wrappedValue) { binding.wrappedValue = $0 })
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if scrolls { ScrollView { blockStack } }
                else { blockStack }
            }
            .onChange(of: editor.selectedSurface) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(target.blockID, anchor: .center) }
            }
        }
        .onChange(of: markdown) { _, value in editor.reloadIfChanged(markdown: value) }
        .onAppear { editor.activate() }
        .onDisappear {
            editor.flush()
            editor.deactivate()
        }
    }

    private var blockStack: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(editor.renderedBlocks) { block in
                BlockRow(block: block, editor: editor, palette: palette, fontName: fontName, fontSize: fontSize)
                    .id(block.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct BlockRow: View {
    let block: NoteBlock
    let editor: BlockEditorModel
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat

    @ViewBuilder
    var body: some View {
        switch block.kind {
        case .paragraph(let content): text(content, style: .body)
        case .heading(let level, let content): text(content, style: .heading(level))
        case .quote(let content):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(palette.accent).frame(width: 3)
                text(content, style: .quote)
            }
        case .list(let list): ListBlockView(blockID: block.id, list: list, editor: editor, palette: palette, fontName: fontName, fontSize: fontSize)
        case .task(let task): TaskBlockView(blockID: block.id, task: task, editor: editor, palette: palette, fontName: fontName, fontSize: fontSize)
        case .code(let code):
            VStack(alignment: .leading, spacing: 5) {
                Text(code.language ?? "code").font(.caption2.monospaced()).foregroundStyle(palette.ink.opacity(0.55))
                NativeBlockTextView(surfaceID: .block(block.id), content: RichText(string: code.code), style: .code(language: code.language), palette: palette, fontName: fontName, fontSize: fontSize, editor: editor)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(palette.ink.opacity(0.07)))
        case .displayMath(let math): DisplayMathView(blockID: block.id, math: math, editor: editor, palette: palette, fontSize: fontSize)
        case .image(let image): ImageBlockView(image: image, palette: palette)
        case .table(let table): TableBlockView(blockID: block.id, table: table, editor: editor, palette: palette, fontName: fontName, fontSize: fontSize)
        case .thematicBreak: Divider().overlay(palette.ink.opacity(0.25)).padding(.vertical, 6)
        case .unsupported(let source):
            Text(source).font(.system(size: fontSize, design: .monospaced)).foregroundStyle(palette.ink.opacity(0.7)).textSelection(.enabled)
        }
    }

    private func text(_ content: RichText, style: BlockTextStyle) -> some View {
        NativeBlockTextView(surfaceID: .block(block.id), content: content, style: style, palette: palette, fontName: fontName, fontSize: fontSize, editor: editor)
    }
}

private struct ListBlockView: View {
    let blockID: UUID
    let list: ListBlock
    let editor: BlockEditorModel
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 4) {
                    Text(marker(at: index))
                        .font(.system(size: fontSize))
                        .frame(minWidth: 16, alignment: .trailing)
                        .foregroundStyle(palette.ink.opacity(0.65))
                        .padding(.top, 3)
                    NativeBlockTextView(
                        surfaceID: .listItem(blockID: blockID, itemID: item.id),
                        content: item.content,
                        style: .list,
                        palette: palette,
                        fontName: fontName,
                        fontSize: fontSize,
                        editor: editor
                    )
                }
            }
        }
    }

    private func marker(at index: Int) -> String {
        switch list.style {
        case .unordered(.bullet): "•"
        case .unordered(.dash): "–"
        case .unordered(.plus): "+"
        case .ordered(let start): "\(start + index)."
        }
    }
}

private struct TaskBlockView: View {
    let blockID: UUID
    let task: TaskBlock
    let editor: BlockEditorModel
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button { editor.toggleTask(blockID: blockID) } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.isCompleted ? palette.accent : palette.ink.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
            NativeBlockTextView(surfaceID: .block(blockID), content: task.content, style: .task, palette: palette, fontName: fontName, fontSize: fontSize, editor: editor)
                .opacity(task.isCompleted ? 0.6 : 1)
        }
    }
}

private struct TableBlockView: View {
    let blockID: UUID
    let table: TableBlock
    let editor: BlockEditorModel
    let palette: NotePaletteColor
    let fontName: String
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                row(table.header, header: true)
                ForEach(table.rows) { value in row(value, header: false) }
            }
            .background(RoundedRectangle(cornerRadius: 7).stroke(palette.ink.opacity(0.18)))
            HStack(spacing: 12) {
                Button("Add row") { editor.addTableRow(blockID: blockID) }
                Button("Add column") { editor.addTableColumn(blockID: blockID) }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(palette.accent)
        }
    }

    private func row(_ row: TableRow, header: Bool) -> some View {
        GridRow {
            ForEach(Array(zip(table.columns, row.cells)), id: \.1.id) { column, cell in
                NativeBlockTextView(
                    surfaceID: .tableCell(blockID: blockID, rowID: row.id, columnID: column.id),
                    content: cell.content,
                    style: .tableCell(header: header),
                    palette: palette,
                    fontName: fontName,
                    fontSize: fontSize,
                    editor: editor
                )
                .padding(6)
                .frame(minWidth: 90)
                .background(header ? palette.ink.opacity(0.07) : .clear)
                .overlay(Rectangle().stroke(palette.ink.opacity(0.12), lineWidth: 0.5))
            }
        }
    }
}

private struct DisplayMathView: View {
    let blockID: UUID
    let math: DisplayMathBlock
    let editor: BlockEditorModel
    let palette: NotePaletteColor
    let fontSize: CGFloat
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var formulaFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.system(size: fontSize, design: .monospaced))
                    .frame(minHeight: 54)
                    .focused($formulaFocused)
                    .onChange(of: draft) { _, value in editor.updateMath(blockID: blockID, latex: value) }
            } else {
                LatexPreview(latex: math.latex, color: NSColor(palette.ink), fontSize: fontSize + 3)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = math.latex
                        isEditing = true
                        DispatchQueue.main.async { formulaFocused = true }
                    }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.ink.opacity(0.045)))
        .onExitCommand { isEditing = false }
        .onChange(of: formulaFocused) { _, focused in
            if !focused { isEditing = false }
        }
    }
}

private struct LatexPreview: View {
    private static let renderer = SwiftMathBridge()
    let latex: String
    let color: NSColor
    let fontSize: CGFloat

    var body: some View {
        if let result = Self.renderer.render(
            latex: latex,
            fontSize: fontSize,
            theme: MarkdownEditorTheme(latexLightModeText: color, latexDarkModeText: color)
        ) {
            Image(nsImage: result.image).resizable().scaledToFit().frame(maxHeight: max(result.size.height, 26))
        } else {
            Text(latex).font(.system(size: fontSize, design: .monospaced)).foregroundStyle(Color(nsColor: color))
        }
    }
}

private struct ImageBlockView: View {
    let image: ImageBlock
    let palette: NotePaletteColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value = AttachmentManager.shared.loadImage(named: image.source) {
                Image(nsImage: value).resizable().scaledToFit().frame(maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(palette.ink.opacity(0.55))
            }
            if !image.alt.isEmpty { Text(image.alt).font(.caption).foregroundStyle(palette.ink.opacity(0.55)) }
        }
    }
}
