import SwiftUI

struct LibraryView: View {
    let model: AppModel
    let initialArchive: Bool
    @State private var archive = false
    @State private var query = ""
    @State private var selection: UUID?
    @State private var draft = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Picker("Collection", selection: $archive) {
                    Text("All Notes").tag(false)
                    Text("Archive").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                ForEach(model.search(query, archived: archive)) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.displayTitle).font(.headline).lineLimit(1)
                        Text(note.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let progress = note.taskProgress {
                            Text("\(progress.done)/\(progress.total) tasks").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tag(note.id)
                    .contextMenu {
                        Button(note.isArchived ? "Restore" : "Archive") { model.setArchived(id: note.id, !note.isArchived) }
                        Button("Delete", role: .destructive) { model.delete(id: note.id) }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle(archive ? "Archive" : "All Notes")
            .toolbar {
                Button { selection = model.create().id } label: { Image(systemName: "plus") }
            }
        } detail: {
            if let selection, let note = model.note(id: selection) {
                VStack(spacing: 0) {
                    HStack {
                        Text(note.displayTitle).font(.headline)
                        Spacer()
                        Button(note.isArchived ? "Restore" : "Archive") { model.setArchived(id: note.id, !note.isArchived) }
                    }
                    .padding()
                    TextEditor(text: $draft)
                        .font(.system(size: 14))
                        .padding(8)
                        .onChange(of: draft) { _, value in model.updateBody(id: note.id, body: value) }
                }
                .background(NotePalette.color(note.colorIndex).paper.opacity(0.55))
                .onAppear { draft = note.body }
                .onChange(of: selection) { _, _ in draft = model.note(id: selection)?.body ?? "" }
            } else {
                ContentUnavailableView("Select a note", systemImage: "note.text")
            }
        }
        .onAppear { archive = initialArchive }
        .frame(minWidth: 760, minHeight: 480)
    }
}
