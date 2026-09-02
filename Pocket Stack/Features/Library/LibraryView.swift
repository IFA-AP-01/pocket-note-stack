import SwiftUI

struct LibraryView: View {
    let model: AppModel
    let initialArchive: Bool
    @State private var filter: AppModel.FilterState = .all
    @State private var query = ""
    @State private var selection: UUID?
    @State private var draft = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.search(query, filter: filter)) { note in
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
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
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
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    private func noteDetail(_ note: Note) -> some View {
        Form {
            Section("Note") {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 360)
                    .onChange(of: draft) { _, value in
                        model.updateBody(id: note.id, body: value)
                    }
            }

            Section("Details") {
                LabeledContent("Status", value: note.isArchived ? "Archived" : "Active")
                LabeledContent("Created", value: note.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("Modified", value: note.modifiedAt.formatted(date: .long, time: .shortened))
            }
        }
        .formStyle(.grouped)
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
}

private struct LibraryNoteRow: View {
    let note: Note

    var body: some View {
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
        .padding(.vertical, 3)
    }
}
