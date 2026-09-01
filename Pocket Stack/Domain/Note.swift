import Foundation

struct Note: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var customTitle: String?
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
        customTitle: String? = nil,
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
        self.customTitle = Self.normalizedCustomTitle(customTitle)
        self.body = body
        self.colorIndex = colorIndex
        self.customColorHex = customColorHex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.sortOrder = sortOrder
    }

    var displayTitle: String {
        let value = customTitle ?? title
        return value.isEmpty ? "New note" : value
    }

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
        var insideCodeFence = false
        for rawLine in body.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.range(of: "^(```|~~~)", options: .regularExpression) != nil {
                insideCodeFence.toggle()
                continue
            }
            guard !insideCodeFence else { continue }

            line = strippingBlockPrefix(from: line)
            guard !line.isEmpty, !isStandaloneNonText(line) else { continue }

            let value = markdownPlainText(line)
            guard value.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            return value.count > 60 ? String(value.prefix(60)) + "…" : value
        }
        return ""
    }

    private static func normalizedCustomTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }

    private static func strippingBlockPrefix(from value: String) -> String {
        var result = value
        let patterns = [
            "^\\s{0,3}#{1,6}\\s+",
            "^\\s{0,3}>+\\s*",
            "^\\s{0,3}[-+*]\\s+",
            "^\\s{0,3}\\d+[.)]\\s+",
            "^\\s*[☐☑]\\s*",
            "^\\s*\\[[ xX]\\]\\s+",
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func isStandaloneNonText(_ value: String) -> Bool {
        let patterns = [
            "^!?\\[[^]]*\\]\\([^)]*\\)\\s*$",
            "^!?\\[[^]]*\\]\\[[^]]*\\]\\s*$",
            "^<?https?://\\S+>?$",
            "^<\\s*(img|video|audio|iframe|source|figure|picture|a)\\b",
            "^@\\w+\\s*[(:\\[]",
            "^[-*_]{3,}$",
            "^\\|?\\s*:?-{3,}",
        ]
        return patterns.contains {
            value.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func markdownPlainText(_ value: String) -> String {
        var result = value
        let removals = [
            "!\\[[^]]*\\]\\([^)]*\\)",
            "!\\[[^]]*\\]\\[[^]]*\\]",
            "<(img|video|audio|iframe|source|figure|picture)\\b[^>]*>.*?</\\1>",
            "<(img|video|audio|iframe|source)\\b[^>]*/?>",
            "<https?://[^>]+>",
        ]
        for pattern in removals {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(
            of: "(?<!!)\\[([^]]+)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?<!!)\\[([^]]+)\\]\\[[^]]*\\]",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\\\([`*_{}\\[\\]()#+\\-.!>])",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "[`*_~]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
