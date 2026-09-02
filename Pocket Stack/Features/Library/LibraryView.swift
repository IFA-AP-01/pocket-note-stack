import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let model: AppModel
    let initialArchive: Bool
    @State private var filter: AppModel.FilterState = .all
    @State private var query = ""
    @State private var selection: UUID?

    private var notes: [Note] {
        model.search(query, filter: filter)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search notes", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .padding(10)

                Divider()

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
            }
            .navigationTitle(initialArchive ? "Archive" : "All Notes")
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
                LibraryNoteDetail(note: note, model: model) {
                    self.selection = nil
                }
                .id(note.id)
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

}

private struct LibraryNoteDetail: View {
    let noteID: UUID
    let model: AppModel
    let onDelete: () -> Void
    @State private var draft: String
    @State private var bridge = EditorBridge()

    init(note: Note, model: AppModel, onDelete: @escaping () -> Void) {
        noteID = note.id
        self.model = model
        self.onDelete = onDelete
        _draft = State(initialValue: note.body)
    }

    private var note: Note? { model.note(id: noteID) }
    private var palette: NotePaletteColor { note.map(NotePalette.color(for:)) ?? NotePalette.color(0) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                header
                EditorFormattingBar(palette: palette, onCommand: handleCommand)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(palette.ink)
            .background(palette.paper)

            Divider().overlay(palette.accent.opacity(0.35))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                    Text(note?.displayTitle ?? "Note").font(.title2.bold())
                        BlockEditorView(
                            markdown: $draft,
                            palette: palette,
                            fontName: AppPreferences.shared.noteFontName,
                            fontSize: AppPreferences.shared.noteFontSize,
                            scrolls: false
                        )
                    }
                    .padding(20)
                    .foregroundStyle(palette.ink)
                    .background(palette.paper, in: RoundedRectangle(cornerRadius: 14))

                    if let note {
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
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: draft) { _, value in model.updateBody(id: noteID, body: value) }
        .onDisappear { model.updateBody(id: noteID, body: draft) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(
                note?.isArchived == true ? "Archived" : "Active",
                systemImage: note?.isArchived == true ? "archivebox.fill" : "square.stack.3d.up.fill"
            )
            .font(.subheadline.weight(.semibold))
            Spacer()
            if let note { Text(note.modifiedAt, style: .relative).font(.subheadline).foregroundStyle(palette.ink.opacity(0.65)) }
            Button(note?.isArchived == true ? "Restore" : "Archive") {
                guard let note else { return }
                model.setArchived(id: noteID, !note.isArchived)
            }
            Menu("Export", systemImage: "square.and.arrow.up") {
                if let note {
                    Button("Markdown Folder…") { NoteTransfer.export(.markdownFolder, notes: [note]) }
                    Button("Text Folder…") { NoteTransfer.export(.textFolder, notes: [note]) }
                    Button("Single Document…") { NoteTransfer.export(.singleDocument, notes: [note]) }
                    Button("Pocket Stack Archive…") { NoteTransfer.export(.archive, notes: [note]) }
                }
            }
            Button("Delete", role: .destructive) {
                model.delete(id: noteID)
                onDelete()
            }
        }
    }

    private func handleCommand(_ command: EditorCommand) {
        if bridge.performBlockCommand(command) { return }
        switch command {
        case .escape: break
        case .toggleTask: bridge.toggleTask()
        case .togglePin: model.togglePin(id: noteID)
        case .cycleColor: model.cycleColor(id: noteID)
        case .delete:
            model.delete(id: noteID)
            onDelete()
        case .archive:
            guard let note else { return }
            model.setArchived(id: noteID, !note.isArchived)
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
                if !bridge.insertImageBlock(filename) { bridge.insertText("![Image](\(filename))") }
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
