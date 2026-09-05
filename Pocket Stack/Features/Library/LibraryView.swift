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
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        model.setArchived(id: note.id, !note.isArchived)
                                    }
                                }
                                Button("Delete", role: .destructive) {
                                    deleteNote(id: note.id)
                                }
                            }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: notes.map(\.id))
                .onDeleteCommand {
                    if let selection {
                        deleteNote(id: selection)
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
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if filter == .archived {
                                filter = .all
                            }
                            let newNote = model.create()
                            selection = newNote.id
                        }
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New note (⌘N)")

                    Button {
                        NoteTransfer.importFiles(into: model)
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
            .onChange(of: notes) { oldNotes, newNotes in
                if let cur = selection, !newNotes.contains(where: { $0.id == cur }) {
                    if let oldIndex = oldNotes.firstIndex(where: { $0.id == cur }) {
                        let nextIndex = min(oldIndex, newNotes.count - 1)
                        selection = nextIndex >= 0 ? newNotes[nextIndex].id : nil
                    } else {
                        selection = newNotes.first?.id
                    }
                } else if selection == nil, !newNotes.isEmpty {
                    selection = newNotes.first?.id
                }
            }
        } detail: {
            if let selection, let note = model.note(id: selection) {
                LibraryNoteDetail(note: note, model: model) {
                    deleteNote(id: note.id)
                }
                .id(note.id)
            } else {
                ContentUnavailableView {
                    Label("Select a note", systemImage: "note.text")
                } description: {
                    Text("Choose a note from the list or create a new one.")
                } actions: {
                    Button("Create Note") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if filter == .archived { filter = .all }
                            let newNote = model.create()
                            selection = newNote.id
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
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

    private func deleteNote(id: UUID) {
        let currentNotes = notes
        let nextSelection: UUID?
        if selection == id {
            if let index = currentNotes.firstIndex(where: { $0.id == id }) {
                if index + 1 < currentNotes.count {
                    nextSelection = currentNotes[index + 1].id
                } else if index > 0 {
                    nextSelection = currentNotes[index - 1].id
                } else {
                    nextSelection = nil
                }
            } else {
                nextSelection = nil
            }
        } else {
            nextSelection = selection
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            selection = nextSelection
            model.delete(id: id)
        }
    }
}

private struct LibraryNoteDetail: View {
    let noteID: UUID
    let model: AppModel
    let onDelete: () -> Void
    @State private var draft: String
    @State private var bridge = EditorBridge()
    @State private var isDeleted = false

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
                EditorFormattingBar(onCommand: handleCommand)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(note?.displayTitle ?? "Note").font(.title2.bold())
                        PocketNoteEditorView(
                            text: $draft,
                            palette: palette,
                            fontSize: AppPreferences.shared.noteFontSize,
                            fontName: AppPreferences.shared.noteFontName,
                            bridge: bridge,
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
        .onChange(of: draft) { _, value in
            guard !isDeleted else { return }
            model.updateBody(id: noteID, body: value)
        }
        .onDisappear {
            guard !isDeleted else { return }
            model.updateBody(id: noteID, body: draft)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(
                note?.isArchived == true ? "Archived" : "Active",
                systemImage: note?.isArchived == true ? "archivebox.fill" : "square.stack.3d.up.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
            if let note {
                Text(note.modifiedAt, style: .relative)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
                handleDelete()
            }
        }
    }

    private func handleDelete() {
        guard !isDeleted else { return }
        isDeleted = true
        onDelete()
    }

    private func handleCommand(_ command: EditorCommand) {
        if bridge.performBlockCommand(command) { return }
        switch command {
        case .escape: break
        case .togglePin: model.togglePin(id: noteID)
        case .cycleColor: model.cycleColor(id: noteID)
        case .delete:
            handleDelete()
        case .archive:
            guard let note else { return }
            model.setArchived(id: noteID, !note.isArchived)
        case .increaseFont: AppPreferences.shared.noteFontSize = min(30, AppPreferences.shared.noteFontSize + 1.5)
        case .decreaseFont: AppPreferences.shared.noteFontSize = max(10, AppPreferences.shared.noteFontSize - 1.5)
        case .insertImage:
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Choose an image to add to this note"
            if panel.runModal() == .OK, let url = panel.url, let filename = AttachmentManager.shared.saveFile(from: url) {
                bridge.insertImageBlock(filename)
            }
        default:
            break
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
