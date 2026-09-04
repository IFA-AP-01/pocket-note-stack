import SwiftUI

struct EditorFormattingBar: View {
    var palette: NotePaletteColor? = nil
    let onCommand: (EditorCommand) -> Void

    init(palette: NotePaletteColor? = nil, onCommand: @escaping (EditorCommand) -> Void) {
        self.palette = palette
        self.onCommand = onCommand
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                commandText("T", help: "Body", .formatBody)
                commandText("H1", help: "Title", .formatTitle)
                commandText("H2", help: "Heading", .formatHeading)
                commandText("H3", help: "Subheading", .formatSubheading)
                separator
                commandIcon("bold", help: "Bold", .formatBold)
                commandIcon("italic", help: "Italic", .formatItalic)
                commandIcon("underline", help: "Underline", .formatUnderline)
                commandIcon("strikethrough", help: "Strikethrough", .formatStrikethrough)
                commandIcon("chevron.left.forwardslash.chevron.right", help: "Inline code", .formatMonospaced)
                separator
                commandIcon("list.bullet", help: "Bulleted list", .formatBulletList)
                commandText("–", help: "Dashed list", .formatDashList)
                commandIcon("list.number", help: "Numbered list", .formatNumberList)
                commandIcon("checklist", help: "Checklist", .formatCheckList)
                separator
                commandIcon("link", help: "Insert link", .insertLink)
                commandIcon("curlybraces", help: "Insert code block", .insertCodeBlock)
                commandIcon("function", help: "Insert inline math", .insertInlineMath)
                commandText("∑", help: "Insert display math", .insertDisplayMath)
                commandIcon("tablecells", help: "Insert table", .insertTable)
                commandIcon("photo", help: "Insert image", .insertImage)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(palette?.ink.opacity(0.045) ?? Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .buttonStyle(.plain)
        .foregroundStyle(palette?.ink ?? Color.primary)
    }

    private var separator: some View {
        Divider().frame(height: 18).padding(.horizontal, 2)
    }

    private func commandIcon(_ name: String, help: String, _ command: EditorCommand) -> some View {
        Button { onCommand(command) } label: {
            Image(systemName: name).frame(width: 22, height: 22)
        }
        .help(help)
    }

    private func commandText(_ title: String, help: String, _ command: EditorCommand) -> some View {
        Button { onCommand(command) } label: {
            Text(title).font(.system(size: 12, weight: .semibold)).frame(minWidth: 22, minHeight: 22)
        }
        .help(help)
    }
}
