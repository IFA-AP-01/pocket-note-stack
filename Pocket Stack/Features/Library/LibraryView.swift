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
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("All Notes")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: { /* Import action */ }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import...")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 12)

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search all notes", text: $query)
                        .textFieldStyle(.plain)
                    Text("\(model.notes.count) notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // Filter chips
                HStack(spacing: 12) {
                    ForEach(AppModel.FilterState.allCases) { state in
                        Text(state.rawValue)
                            .font(.subheadline)
                            .fontWeight(filter == state ? .medium : .regular)
                            .foregroundColor(filter == state ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(filter == state ? Color.secondary.opacity(0.15) : Color.clear, in: Capsule())
                            .onTapGesture { filter = state }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Note List
                List(selection: $selection) {
                    ForEach(model.search(query, filter: filter)) { note in
                        NoteRowView(note: note)
                            .tag(note.id)
                            .listRowSeparator(.hidden)
                            .contextMenu {
                                Button(note.isArchived ? "Restore" : "Archive") { model.setArchived(id: note.id, !note.isArchived) }
                                Button("Delete", role: .destructive) { model.delete(id: note.id) }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 500)
        } detail: {
            if let selection, let note = model.note(id: selection) {
                VStack(spacing: 0) {
                    // Detail Header
                    HStack {
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(NotePalette.swiftUIColor(for: note))
                                .frame(width: 8, height: 8)
                                .cornerRadius(2)
                            Text(note.isArchived ? "ARCHIVED - IN THE DECK" : "ACTIVE - IN THE DECK")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Mark complete") { /* TODO */ }
                            Button("Export...") { /* TODO */ }
                            Button("Delete") { model.delete(id: note.id) }
                                .foregroundColor(.red)
                        }
                        .buttonStyle(ToolbarButtonStyle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                    // Note Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Text(note.displayTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Color(NotePalette.color(note.colorIndex).ink))
                            Spacer()
                            Text("edited \(formatDate(note.modifiedAt))")
                                .font(.subheadline)
                                .foregroundColor(Color(NotePalette.color(note.colorIndex).ink).opacity(0.6))
                        }

                        TextEditor(text: $draft)
                            .font(.custom(AppPreferences.shared.noteFontName, size: 16))
                            .foregroundColor(Color(NotePalette.color(note.colorIndex).ink))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .onChange(of: draft) { _, value in model.updateBody(id: note.id, body: value) }

                        Divider()
                            .opacity(0.5)

                        Text("Created \(formatFullDate(note.createdAt)) • Updated \(relativeTime(note.modifiedAt)) ago")
                            .font(.caption)
                            .foregroundColor(Color(NotePalette.color(note.colorIndex).ink).opacity(0.6))
                    }
                    .padding(24)
                    .background(NotePalette.swiftUIColor(for: note), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    Spacer()
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .onAppear { draft = note.body }
                .onChange(of: selection) { _, _ in draft = model.note(id: selection)?.body ?? "" }
            } else {
                ContentUnavailableView("Select a note", systemImage: "note.text")
            }
        }
        .onAppear { filter = initialArchive ? .archived : .all }
        .frame(minWidth: 920, minHeight: 620)
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        return df.string(from: date)
    }

    private func formatFullDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy"
        return df.string(from: date)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        return "\(diff / 86400)d"
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .padding(.top, 4)

            Rectangle()
                .fill(NotePalette.swiftUIColor(for: note))
                .frame(width: 4)
                .cornerRadius(2)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(note.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(note.isArchived ? "ARCHIVED" : "ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    Text(relativeTime(note.modifiedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                Text(note.preview)
                    .font(.custom(AppPreferences.shared.noteFontName, size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        return "\(diff / 86400)d"
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
