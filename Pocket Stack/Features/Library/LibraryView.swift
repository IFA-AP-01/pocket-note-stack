import SwiftUI
import UniformTypeIdentifiers
import MarkdownEngine

struct LibraryView: View {
    let model: AppModel
    let initialArchive: Bool
    @State private var filter: AppModel.FilterState = .all
    @State private var query = ""
    @State private var selection: UUID?
    @State private var draft = ""
    @State private var bridge = EditorBridge()

    private var notes: [Note] {
        model.search(query, filter: filter)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(notes) { note in
                    LibraryNoteRow(note: note)
                        .tag(note.id)
                        .contextMenu {
                            Button(note.isArchived ? "Restore" : "Archive") {
                                model.setArchived(id: note.id, !note.isArchived)
                            }
                            Button("Delete", role: .destructive) {
                                model.delete(id: note.id)
                            }
                        }
                }
            }
            .navigationTitle(initialArchive ? "Archive" : "All Notes")
            .searchable(text: $query, prompt: "Search notes")
            .toolbar {
                ToolbarItemGroup {
                    Picker("Filter", selection: $filter) {
                        ForEach(AppModel.FilterState.allCases) { state in
                            Text(state.rawValue).tag(state)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        NoteTransfer.importFiles(into: model)
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
            .onChange(of: notes) { _, newNotes in
                if selection == nil || !newNotes.contains(where: { $0.id == selection }) {
                    selection = newNotes.first?.id
                }
            }
        } detail: {
            if let selection, let note = model.note(id: selection) {
                noteDetail(note)
            } else {
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "note.text",
                    description: Text("Choose a note from the list to view and edit it.")
                )
            }
        }
        .onAppear {
            filter = initialArchive ? .archived : .all
            if selection == nil {
                selection = model.search(query, filter: initialArchive ? .archived : .all).first?.id
            }
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    private func noteDetail(_ note: Note) -> some View {
        let palette = NotePalette.color(for: note)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            note.isArchived ? "Archived" : "Active",
                            systemImage: note.isArchived ? "archivebox.fill" : "square.stack.3d.up.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(note.modifiedAt, style: .relative)
                            .font(.subheadline)
                            .foregroundStyle(palette.ink.opacity(0.65))
                    }

                    Divider()

                    Text(note.displayTitle)
                        .font(.title2.bold())

                    NoteTextView(
                        text: $draft,
                        noteID: note.id,
                        palette: palette,
                        fontName: AppPreferences.shared.noteFontName,
                        fontSize: AppPreferences.shared.noteFontSize,
                        heightBehavior: .fitsContent,
                        onCommand: { handleCommand($0, for: note) }
                    )
                    .onChange(of: draft) { _, value in
                        model.updateBody(id: note.id, body: value)
                    }
                }
                .padding(20)
                .foregroundStyle(palette.ink)
                .background(palette.paper, in: RoundedRectangle(cornerRadius: 14))

                GroupBox("Details") {
                    VStack(spacing: 10) {
                        LabeledContent("Status", value: note.isArchived ? "Archived" : "Active")
                        Divider()
                        LabeledContent("Created", value: note.createdAt.formatted(date: .long, time: .shortened))
                        Divider()
                        LabeledContent("Modified", value: note.modifiedAt.formatted(date: .long, time: .shortened))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(note.displayTitle)
        .toolbar {
            ToolbarItemGroup {
                Button(note.isArchived ? "Restore" : "Archive") {
                    model.setArchived(id: note.id, !note.isArchived)
                }

                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("Markdown Folder…") {
                        NoteTransfer.export(.markdownFolder, notes: [note])
                    }
                    Button("Text Folder…") {
                        NoteTransfer.export(.textFolder, notes: [note])
                    }
                    Button("Single Document…") {
                        NoteTransfer.export(.singleDocument, notes: [note])
                    }
                    Button("Pocket Stack Archive…") {
                        NoteTransfer.export(.archive, notes: [note])
                    }
                }

                Button("Delete", role: .destructive) {
                    model.delete(id: note.id)
                    selection = nil
                }
            }
        }
        .onAppear {
            draft = note.body
        }
        .onChange(of: selection) { _, selectedID in
            draft = selectedID.flatMap { model.note(id: $0)?.body } ?? ""
        }
    }

    private func handleCommand(_ command: EditorCommand, for note: Note) {
        switch command {
        case .escape: break
        case .toggleTask: bridge.toggleTask()
        case .togglePin: model.togglePin(id: note.id)
        case .cycleColor: model.cycleColor(id: note.id)
        case .delete:
            model.delete(id: note.id)
            selection = nil
        case .archive:
            model.setArchived(id: note.id, !note.isArchived)
        case .increaseFont: AppPreferences.shared.noteFontSize = min(30, AppPreferences.shared.noteFontSize + 1.5)
        case .decreaseFont: AppPreferences.shared.noteFontSize = max(10, AppPreferences.shared.noteFontSize - 1.5)
        case .formatTitle: bridge.togglePrefix("# ")
        case .formatHeading: bridge.togglePrefix("## ")
        case .formatSubheading: bridge.togglePrefix("### ")
        case .formatBody: bridge.togglePrefix("")
        case .formatMonospaced: bridge.applyWrap(prefix: "`", suffix: "`")
        case .formatBold: bridge.applyWrap(prefix: "**", suffix: "**")
        case .formatItalic: bridge.applyWrap(prefix: "*", suffix: "*")
        case .formatStrikethrough: bridge.applyWrap(prefix: "~~", suffix: "~~")
        case .formatUnderline: bridge.applyWrap(prefix: "<u>", suffix: "</u>")
        case .formatBulletList: bridge.togglePrefix("* ")
        case .formatDashList: bridge.togglePrefix("- ")
        case .formatNumberList: bridge.togglePrefix("1. ")
        case .formatCheckList: bridge.toggleTask()
        case .insertTable:
            bridge.insertText("\n| Header 1 | Header 2 |\n| -------- | -------- |\n| Cell 1   | Cell 2   |\n")
        case .insertImage:
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Choose an image to add to this note"
            if panel.runModal() == .OK, let url = panel.url, let filename = AttachmentManager.shared.saveFile(from: url) {
                bridge.insertText("![Image](\(filename))")
            }
        case .insertLink: bridge.applyWrap(prefix: "[", suffix: "](https://)")
        case .insertCodeBlock: bridge.applyWrap(prefix: "```\n", suffix: "\n```")
        case .insertInlineMath: bridge.applyWrap(prefix: "$", suffix: "$")
        case .insertDisplayMath: bridge.applyWrap(prefix: "$$\n", suffix: "\n$$")
        }
    }
}

private struct LibraryNoteRow: View {
    let note: Note

    var body: some View {
        let palette = NotePalette.color(for: note)

        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                if !note.preview.isEmpty {
                    Text(note.preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Text(note.isArchived ? "Archived" : "Active")
                    Spacer()
                    Text(note.modifiedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
