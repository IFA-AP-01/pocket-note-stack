import Foundation

struct Note: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var colorIndex: Int
    var customColorHex: String?
    var createdAt: Date
    var modifiedAt: Date
    var isArchived: Bool
    var isPinned: Bool
    var sortOrder: Double

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        colorIndex: Int = 0,
        customColorHex: String? = nil,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        isArchived: Bool = false,
        isPinned: Bool = false,
        sortOrder: Double = 0
    ) {
        self.id = id
        self.title = title.isEmpty ? Self.derivedTitle(from: body) : title
        self.body = body
        self.colorIndex = colorIndex
        self.customColorHex = customColorHex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.sortOrder = sortOrder
    }

    var displayTitle: String { title.isEmpty ? "New note" : title }

    var preview: String {
        let lines = body.split(whereSeparator: \Character.isNewline).map(String.init)
        let text = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return text.count > 120 ? String(text.prefix(120)) + "…" : text
    }

    var taskProgress: (done: Int, total: Int)? {
        var done = 0
        var total = 0
        for line in body.split(whereSeparator: \Character.isNewline) {
            if line.first == NoteTask.open || line.first == NoteTask.done {
                total += 1
                if line.first == NoteTask.done { done += 1 }
            }
        }
        return total == 0 ? nil : (done, total)
    }

    static func derivedTitle(from body: String) -> String {
        var value = body.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? ""
        value = value.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        value = NoteTask.stripped(value)
        return value.count > 60 ? String(value.prefix(60)) + "…" : value
    }
}

enum NoteTask {
    static let open: Character = "☐"
    static let done: Character = "☑"
    static let openPrefix = "☐ "
    static let donePrefix = "☑ "

    static func stripped(_ line: String) -> String {
        guard line.first == open || line.first == done else { return line }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    static func toggle(line: String) -> String {
        if line.hasPrefix(openPrefix) { return donePrefix + line.dropFirst(openPrefix.count) }
        if line.hasPrefix(donePrefix) { return String(line.dropFirst(donePrefix.count)) }
        return openPrefix + line
    }

    static func fromMarkdown(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(?m)^(\\s*)[-*]\\s+\\[ \\]\\s+",
            with: "$1" + openPrefix,
            options: .regularExpression
        ).replacingOccurrences(
            of: "(?m)^(\\s*)[-*]\\s+\\[[xX]\\]\\s+",
            with: "$1" + donePrefix,
            options: .regularExpression
        )
    }

    static func toMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: openPrefix, with: "- [ ] ")
            .replacingOccurrences(of: donePrefix, with: "- [x] ")
    }
}
