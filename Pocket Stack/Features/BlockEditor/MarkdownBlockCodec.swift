import Foundation
import Markdown

struct MarkdownBlockCodec {
    func parse(_ source: String) -> EditorDocument {
        var blocks: [NoteBlock] = []
        for segment in splitDisplayMath(source) {
            switch segment {
            case .math(let latex):
                blocks.append(NoteBlock(kind: .displayMath(DisplayMathBlock(latex: latex))))
            case .markdown(let markdown):
                let document = Document(parsing: markdown)
                for child in document.children { blocks.append(contentsOf: mapBlock(child)) }
            }
        }
        if blocks.isEmpty { blocks = [NoteBlock(kind: .paragraph(RichText(string: "")))] }
        return EditorDocument(blocks: blocks)
    }

    func serialize(_ document: EditorDocument) -> String {
        document.blocks.map(writeBlock).joined(separator: "\n\n")
    }

    private func mapBlock(_ node: Markup) -> [NoteBlock] {
        if let paragraph = node as? Paragraph {
            if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Markdown.Image {
                return [NoteBlock(kind: .image(ImageBlock(
                    alt: image.plainText,
                    source: image.source ?? "",
                    title: image.title
                )))]
            }
            return [NoteBlock(kind: .paragraph(mapInline(paragraph)))]
        }
        if let heading = node as? Heading {
            return [NoteBlock(kind: .heading(level: heading.level, content: mapInline(heading)))]
        }
        if let quote = node as? BlockQuote {
            let text = quote.children.compactMap { ($0 as? Paragraph).map(mapInline) }
                .reduce(RichText(string: "")) { value, next in
                    value.string.isEmpty ? next : value.appending(RichText(string: "\n")).appending(next)
                }
            return [NoteBlock(kind: .quote(text))]
        }
        if let code = node as? Markdown.CodeBlock {
            return [NoteBlock(kind: .code(CodeBlock(language: code.language, code: code.code)))]
        }
        if let ordered = node as? OrderedList {
            let items = Array(ordered.listItems.map { ListBlockItem(content: content(of: $0)) })
            return [NoteBlock(kind: .list(ListBlock(style: .ordered(start: Int(ordered.startIndex)), items: items)))]
        }
        if let unordered = node as? UnorderedList {
            var regular: [ListBlockItem] = []
            var result: [NoteBlock] = []
            func flush() {
                guard !regular.isEmpty else { return }
                result.append(NoteBlock(kind: .list(ListBlock(style: .unordered(marker: .dash), items: regular))))
                regular.removeAll()
            }
            for item in unordered.listItems {
                if let checkbox = item.checkbox {
                    flush()
                    result.append(NoteBlock(kind: .task(TaskBlock(
                        isCompleted: checkbox == .checked,
                        content: content(of: item)
                    ))))
                } else {
                    regular.append(ListBlockItem(content: content(of: item)))
                }
            }
            flush()
            return result
        }
        if let table = node as? Markdown.Table {
            let alignments = table.columnAlignments.map { alignment -> TableAlignment in
                switch alignment {
                case .left: .leading
                case .center: .center
                case .right: .trailing
                case nil: .none
                }
            }
            let columns = alignments.map { TableColumn(alignment: $0) }
            let header = TableRow(cells: table.head.children.compactMap { cell in
                (cell as? Markdown.Table.Cell).map { TableCell(content: mapInline($0)) }
            })
            let rows = Array(table.body.rows.map { row in
                TableRow(cells: row.children.compactMap { cell in
                    (cell as? Markdown.Table.Cell).map { TableCell(content: mapInline($0)) }
                })
            })
            var value = TableBlock(columns: columns, header: header, rows: rows)
            value.normalize()
            return [NoteBlock(kind: .table(value))]
        }
        if node is ThematicBreak { return [NoteBlock(kind: .thematicBreak)] }
        if let html = node as? HTMLBlock {
            return [NoteBlock(kind: .unsupported(rawMarkdown: html.rawHTML))]
        }
        return [NoteBlock(kind: .unsupported(rawMarkdown: node.format()))]
    }

    private func content(of item: ListItem) -> RichText {
        guard let paragraph = item.children.first(where: { $0 is Paragraph }) as? Paragraph else {
            return RichText(string: "")
        }
        return mapInline(paragraph)
    }

    private func mapInline(_ container: Markup) -> RichText {
        var builder = InlineBuilder()
        builder.visitChildren(of: container, marks: [])
        return RichText(string: builder.output, annotations: builder.annotations)
    }

    private func writeBlock(_ block: NoteBlock) -> String {
        switch block.kind {
        case .paragraph(let text): return writeInline(text)
        case .heading(let level, let text): return String(repeating: "#", count: min(max(level, 1), 6)) + " " + writeInline(text)
        case .quote(let text): return writeInline(text).components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n")
        case .list(let list):
            return list.items.enumerated().map { index, item in
                let marker: String
                switch list.style {
                case .unordered(let value): marker = value.rawValue
                case .ordered(let start): marker = "\(start + index)."
                }
                return marker + " " + writeInline(item.content)
            }.joined(separator: "\n")
        case .task(let task): return "- [\(task.isCompleted ? "x" : " ")] " + writeInline(task.content)
        case .code(let code):
            let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: code.code) + 1))
            return fence + (code.language ?? "") + "\n" + code.code + (code.code.hasSuffix("\n") ? "" : "\n") + fence
        case .displayMath(let math): return "$$\n" + math.latex + "\n$$"
        case .image(let image):
            let title = image.title.map { " \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? ""
            return "![\(escapeLabel(image.alt))](\(image.source)\(title))"
        case .table(let table): return writeTable(table)
        case .thematicBreak: return "---"
        case .unsupported(let source): return source
        }
    }

    private func writeTable(_ table: TableBlock) -> String {
        let header = "| " + table.header.cells.map { escapeTable(writeInline($0.content)) }.joined(separator: " | ") + " |"
        let separator = "| " + table.columns.map {
            switch $0.alignment {
            case .none: "---"
            case .leading: ":---"
            case .center: ":---:"
            case .trailing: "---:"
            }
        }.joined(separator: " | ") + " |"
        let rows = table.rows.map { row in
            "| " + row.cells.map { escapeTable(writeInline($0.content)) }.joined(separator: " | ") + " |"
        }
        return ([header, separator] + rows).joined(separator: "\n")
    }

    private func writeInline(_ richText: RichText) -> String {
        let source = richText.string as NSString
        guard source.length > 0 else { return "" }
        var output = ""
        var index = 0
        while index < source.length {
            let math = richText.annotations.first { annotation in
                guard annotation.range.location == index else { return false }
                if case .inlineMath = annotation.kind { return true }
                return false
            }
            if let math, case .inlineMath(let latex) = math.kind {
                output += "$\(latex)$"
                index += max(math.range.length, 1)
                continue
            }
            let active = richText.annotations.filter { $0.range.location <= index && $0.range.upperBound > index }
            let nextBoundary = min(active.map(\.range.upperBound).min() ?? source.length,
                                   richText.annotations.filter { $0.range.location > index }.map(\.range.location).min() ?? source.length)
            var chunk = escapeInline(source.substring(with: NSRange(location: index, length: max(nextBoundary - index, 1))))
            let kinds = active.map(\.kind)
            if kinds.contains(.inlineCode) { chunk = "`" + chunk.replacingOccurrences(of: "`", with: "\\`") + "`" }
            if kinds.contains(.bold) { chunk = "**" + chunk + "**" }
            if kinds.contains(.italic) { chunk = "*" + chunk + "*" }
            if kinds.contains(.strikethrough) { chunk = "~~" + chunk + "~~" }
            if kinds.contains(.underline) { chunk = "<u>" + chunk + "</u>" }
            if let link = kinds.first(where: { if case .link = $0 { true } else { false } }),
               case .link(let destination, let title) = link {
                chunk = "[\(chunk)](\(destination)\(title.map { " \"\($0)\"" } ?? ""))"
            }
            output += chunk
            index = max(nextBoundary, index + 1)
        }
        return output
    }

    private func escapeInline(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private func escapeLabel(_ value: String) -> String { value.replacingOccurrences(of: "]", with: "\\]") }
    private func escapeTable(_ value: String) -> String { value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>") }

    private func longestBacktickRun(in value: String) -> Int {
        var longest = 0
        var current = 0
        for character in value {
            if character == "`" { current += 1; longest = max(longest, current) }
            else { current = 0 }
        }
        return longest
    }

    private enum SourceSegment { case markdown(String), math(String) }

    private func splitDisplayMath(_ source: String) -> [SourceSegment] {
        let lines = source.components(separatedBy: .newlines)
        var segments: [SourceSegment] = []
        var markdown: [String] = []
        var math: [String]? = nil
        var inFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if !inFence && trimmed == "$$" {
                if let formula = math {
                    segments.append(.math(formula.joined(separator: "\n")))
                    math = nil
                } else {
                    if !markdown.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(.markdown(markdown.joined(separator: "\n")))
                    }
                    markdown.removeAll()
                    math = []
                }
            } else if math != nil {
                math?.append(line)
            } else {
                markdown.append(line)
            }
        }
        if let formula = math {
            markdown.append("$$")
            markdown.append(contentsOf: formula)
        }
        if !markdown.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.markdown(markdown.joined(separator: "\n")))
        }
        return segments
    }
}

private struct InlineBuilder {
    var output = ""
    var annotations: [InlineAnnotation] = []
    private var underlined = false

    mutating func visitChildren(of node: Markup, marks: [InlineAnnotationKind]) {
        for child in node.children { visit(child, marks: marks) }
    }

    private mutating func visit(_ node: Markup, marks: [InlineAnnotationKind]) {
        if let html = node as? InlineHTML {
            let tag = html.rawHTML.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if tag == "<u>" { underlined = true }
            else if tag == "</u>" { underlined = false }
            return
        }
        if let text = node as? Markdown.Text { appendMathAware(text.string, marks: marks); return }
        if let code = node as? InlineCode { append(code.code, marks: marks + [.inlineCode]); return }
        if node is SoftBreak { append(" ", marks: marks); return }
        if node is LineBreak { append("\n", marks: marks); return }
        if node is Strong { visitChildren(of: node, marks: marks + [.bold]); return }
        if node is Emphasis { visitChildren(of: node, marks: marks + [.italic]); return }
        if node is Strikethrough { visitChildren(of: node, marks: marks + [.strikethrough]); return }
        if let link = node as? Link {
            visitChildren(of: node, marks: marks + [.link(destination: link.destination ?? "", title: link.title)])
            return
        }
        visitChildren(of: node, marks: marks)
    }

    private mutating func appendMathAware(_ value: String, marks: [InlineAnnotationKind]) {
        var cursor = value.startIndex
        while cursor < value.endIndex,
              let open = value[cursor...].firstIndex(of: "$"),
              let close = value[value.index(after: open)...].firstIndex(of: "$") {
            append(String(value[cursor..<open]), marks: marks)
            let latex = String(value[value.index(after: open)..<close])
            append("\u{FFFC}", marks: marks + [.inlineMath(latex: latex)])
            cursor = value.index(after: close)
        }
        if cursor < value.endIndex { append(String(value[cursor...]), marks: marks) }
    }

    private mutating func append(_ value: String, marks: [InlineAnnotationKind]) {
        guard !value.isEmpty else { return }
        let start = (output as NSString).length
        output += value
        let range = TextRange(location: start, length: (value as NSString).length)
        for mark in marks + (underlined ? [.underline] : []) {
            annotations.append(InlineAnnotation(range: range, kind: mark))
        }
    }
}
