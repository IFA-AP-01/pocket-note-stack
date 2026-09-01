import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportFormat {
    case markdownFolder, textFolder, singleDocument, archive
}

@MainActor
enum NoteTransfer {
    static func export(_ format: ExportFormat, notes: [Note]) {
        switch format {
        case .markdownFolder, .textFolder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export"
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            let ext = format == .markdownFolder ? "md" : "txt"
            for note in notes {
                let safe = sanitized(note.displayTitle)
                let body = format == .markdownFolder ? NoteTask.toMarkdown(note.body) : note.body
                try? body.write(to: directory.appendingPathComponent("\(safe).\(ext)"), atomically: true, encoding: .utf8)
            }
        case .singleDocument:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "Pocket Stack Notes.txt"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let text = notes.map { "# \($0.displayTitle)\n\n\($0.body)" }.joined(separator: "\n\n---\n\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        case .archive:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Pocket Stack.stickies"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(notes).write(to: url, options: .atomic)
        }
    }

    static func importFiles(into model: AppModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json, .plainText, .text, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        var notes: [Note] = []
        for url in panel.urls {
            if url.pathExtension == "stickies" || url.pathExtension == "json",
               let data = try? Data(contentsOf: url),
               let archive = try? JSONDecoder().decode([Note].self, from: data) {
                notes.append(contentsOf: archive)
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                notes.append(Note(body: url.pathExtension == "md" ? NoteTask.fromMarkdown(text) : text))
            }
        }
        model.ingest(notes)
    }

    private static func sanitized(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let result = value.components(separatedBy: invalid).joined(separator: "-")
        return result.isEmpty ? "Untitled" : String(result.prefix(80))
    }
}
