import Foundation

struct EditorDocument: Hashable, Sendable {
    var blocks: [NoteBlock]
    var revision: UInt64 = 0
}

struct NoteBlock: Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: BlockKind
}

enum BlockKind: Hashable, Sendable {
    case paragraph(RichText)
    case heading(level: Int, content: RichText)
    case quote(RichText)
    case list(ListBlock)
    case task(TaskBlock)
    case code(CodeBlock)
    case displayMath(DisplayMathBlock)
    case image(ImageBlock)
    case table(TableBlock)
    case thematicBreak
    case unsupported(rawMarkdown: String)
}

struct RichText: Hashable, Sendable {
    var string: String
    var annotations: [InlineAnnotation] = []

    var utf16Length: Int { (string as NSString).length }

    func split(at offset: Int) -> (RichText, RichText) {
        let clamped = min(max(offset, 0), utf16Length)
        let source = string as NSString
        let left = source.substring(with: NSRange(location: 0, length: clamped))
        let right = source.substring(from: clamped)
        var leftAnnotations: [InlineAnnotation] = []
        var rightAnnotations: [InlineAnnotation] = []

        for annotation in annotations {
            let start = annotation.range.location
            let end = annotation.range.upperBound
            if start < clamped {
                let length = min(end, clamped) - start
                if length > 0 {
                    leftAnnotations.append(.init(range: .init(location: start, length: length), kind: annotation.kind))
                }
            }
            if end > clamped {
                let newStart = max(start, clamped) - clamped
                let length = end - max(start, clamped)
                if length > 0 {
                    rightAnnotations.append(.init(range: .init(location: newStart, length: length), kind: annotation.kind))
                }
            }
        }
        return (
            RichText(string: left, annotations: leftAnnotations),
            RichText(string: right, annotations: rightAnnotations)
        )
    }

    func appending(_ other: RichText) -> RichText {
        let offset = utf16Length
        let shifted = other.annotations.map {
            InlineAnnotation(
                range: .init(location: $0.range.location + offset, length: $0.range.length),
                kind: $0.kind
            )
        }
        return RichText(string: string + other.string, annotations: annotations + shifted)
    }
}

struct InlineAnnotation: Hashable, Sendable {
    var range: TextRange
    var kind: InlineAnnotationKind
}

struct TextRange: Hashable, Sendable {
    var location: Int
    var length: Int
    var upperBound: Int { location + length }

    var nsRange: NSRange { NSRange(location: location, length: length) }
}

enum InlineAnnotationKind: Hashable, Sendable {
    case bold
    case italic
    case strikethrough
    case underline
    case inlineCode
    case link(destination: String, title: String?)
    case inlineMath(latex: String)
}

struct ListBlock: Hashable, Sendable {
    var style: ListStyle
    var items: [ListBlockItem]
}

enum ListStyle: Hashable, Sendable {
    case unordered(marker: UnorderedMarker)
    case ordered(start: Int)
}

enum UnorderedMarker: String, Hashable, Sendable {
    case bullet = "*"
    case dash = "-"
    case plus = "+"
}

struct ListBlockItem: Identifiable, Hashable, Sendable {
    var id = UUID()
    var content: RichText
}

struct TaskBlock: Hashable, Sendable {
    var isCompleted: Bool
    var content: RichText
}

struct CodeBlock: Hashable, Sendable {
    var language: String?
    var code: String
}

struct DisplayMathBlock: Hashable, Sendable {
    var latex: String
}

struct ImageBlock: Hashable, Sendable {
    var alt: String
    var source: String
    var title: String?
}

struct TableBlock: Hashable, Sendable {
    var columns: [TableColumn]
    var header: TableRow
    var rows: [TableRow]

    mutating func normalize() {
        if columns.isEmpty { columns = [TableColumn()] }
        header.normalize(columnCount: columns.count)
        for index in rows.indices { rows[index].normalize(columnCount: columns.count) }
    }
}

struct TableColumn: Identifiable, Hashable, Sendable {
    var id = UUID()
    var alignment: TableAlignment = .none
}

enum TableAlignment: Hashable, Sendable {
    case none, leading, center, trailing
}

struct TableRow: Identifiable, Hashable, Sendable {
    var id = UUID()
    var cells: [TableCell]

    mutating func normalize(columnCount: Int) {
        if cells.count > columnCount { cells.removeLast(cells.count - columnCount) }
        while cells.count < columnCount { cells.append(TableCell(content: RichText(string: ""))) }
    }
}

struct TableCell: Identifiable, Hashable, Sendable {
    var id = UUID()
    var content: RichText
}

enum EditorSurfaceID: Hashable, Sendable {
    case block(UUID)
    case listItem(blockID: UUID, itemID: UUID)
    case tableCell(blockID: UUID, rowID: UUID, columnID: UUID)

    var blockID: UUID {
        switch self {
        case .block(let id): id
        case .listItem(let id, _), .tableCell(let id, _, _): id
        }
    }
}

enum BlockTextStyle: Hashable {
    case body, heading(Int), quote, list, task, tableCell(header: Bool), code(language: String?)
}

enum FocusDirection: Equatable { case previous, next, up, down }
enum CaretAnchor { case start, end, index(Int), horizontal(CGFloat, fromBottom: Bool) }
