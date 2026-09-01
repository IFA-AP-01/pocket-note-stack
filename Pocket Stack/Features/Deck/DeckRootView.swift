import SwiftUI

struct DeckRootView: View {
    let model: AppModel
    let preferences: AppPreferences
    let state: DeckViewState
    unowned let controller: DeckController
    @State private var hoveredNoteID: UUID?

    private var onRight: Bool { preferences.edge == .right }
    private var visibleNotes: [Note] { state.showAll ? model.activeNotes : Array(model.activeNotes.prefix(5)) }

    var body: some View {
        ZStack(alignment: onRight ? .trailing : .leading) {
            if state.state == .rest {
                RestPill(notes: model.activeNotes)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                activeDeck
                    .padding(onRight ? .trailing : .leading, 3)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: onRight ? .trailing : .leading)
        .animation(.spring(response: 0.30, dampingFraction: 0.88), value: state.fanVisible)
    }

    private var fan: some View {
        NoteFan(notes: visibleNotes,
                hiddenCount: state.showAll ? 0 : max(0, model.activeNotes.count - 5),
                openID: state.state.expandedID,
                revealTick: state.revealTick,
                style: preferences.style,
                labelFontName: preferences.noteFontName,
                edge: preferences.edge,
                openOnHover: preferences.openOnHover,
                onOpen: controller.expand,
                onReorder: model.reorder,
                onShowAll: { state.showAll = true },
                onCreate: controller.createNote,
                onHoverNote: { hoveredNoteID = $0 })
    }

    @ViewBuilder private var activeDeck: some View {
        if onRight {
            HStack(spacing: 10) {
                sideContent
                fan
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        } else {
            HStack(spacing: 10) {
                fan
                sideContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var sideContent: some View {
        if let id = state.state.expandedID, model.note(id: id) != nil {
            NoteEditorView(noteID: id,
                           model: model,
                           preferences: preferences,
                           bridge: state.editorBridge,
                           onClose: controller.closeExpanded,
                           onMicrophone: { controller.toggleDictation(noteID: id) },
                           dictationState: state.dictationState)
                .frame(width: preferences.noteSize.width, height: preferences.noteSize.height)
                .transition(.modifier(active: NotePullTransition(hidden: true, onRight: onRight),
                                      identity: NotePullTransition(hidden: false, onRight: onRight)))
                .id(id)
        } else if let hoveredNoteID, let note = model.note(id: hoveredNoteID) {
            HoverNotePreview(note: note)
                .transition(.modifier(active: NotePullTransition(hidden: true, onRight: onRight),
                                      identity: NotePullTransition(hidden: false, onRight: onRight)))
                .allowsHitTesting(false)
        }
    }
}

private struct RestPill: View {
    let notes: [Note]

    var body: some View {
        VStack(spacing: 5) {
            if notes.isEmpty { dash(.secondary.opacity(0.5)) }
            ForEach(notes.prefix(14)) { note in dash(NotePalette.color(for: note).accent) }
        }
        .padding(.vertical, 8)
        .frame(width: 14)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.68))
                .shadow(color: .black.opacity(0.24), radius: 5, x: -2, y: 1)
        )
    }

    private func dash(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: 7, height: 16)
    }
}

private struct NoteFan: View {
    let notes: [Note]
    let hiddenCount: Int
    let openID: UUID?
    let revealTick: Int
    let style: DeckStyle
    let labelFontName: String
    let edge: DeckEdge
    let openOnHover: Bool
    let onOpen: (UUID) -> Void
    let onReorder: (UUID, UUID?) -> Void
    let onShowAll: () -> Void
    let onCreate: () -> Void
    let onHoverNote: (UUID?) -> Void

    @State private var revealed = false
    @State private var hoveredID: UUID?
    @State private var hoverTask: Task<Void, Never>?
    private var onRight: Bool { edge == .right }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if stateNeedsScroll {
                    ScrollView(.vertical, showsIndicators: false) { tabs.padding(.vertical, 4) }
                        .frame(maxHeight: 720)
                        .scrollClipDisabled()
                } else {
                    tabs
                }
            }

            if hiddenCount > 0 {
                MoreTab(count: hiddenCount, edge: edge, action: onShowAll)
                    .staged(index: notes.count, revealed: revealed, onRight: onRight)
            }

            AddNoteButton(action: onCreate)
                .staged(index: notes.count + 1, revealed: revealed, onRight: onRight)
        }
        .frame(width: 56)
        .onAppear { revealed = true }
        .onChange(of: revealTick) { _, _ in
            revealed = false
            DispatchQueue.main.async { revealed = true }
        }
        .onDisappear {
            hoverTask?.cancel()
            onHoverNote(nil)
        }
    }

    private var stateNeedsScroll: Bool { notes.count > 5 }

    private var tabs: some View {
        VStack(spacing: style == .labelled ? -66 : 7) {
            if notes.isEmpty {
                EmptyNoteTab(edge: edge, action: onCreate)
                    .staged(index: 0, revealed: revealed, onRight: onRight)
            }
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                NoteTab(note: note,
                        labelled: style == .labelled,
                        fontName: labelFontName.isEmpty ? "Noteworthy-Light" : labelFontName,
                        edge: edge,
                        isOpen: openID == note.id,
                        isHovered: hoveredID == note.id,
                        onHoverChange: { updateHover(note: note, inside: $0) },
                        action: { onOpen(note.id) })
                    .draggable(note.id.uuidString)
                    .dropDestination(for: String.self) { values, _ in
                        guard let source = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                        onReorder(source, note.id)
                        return true
                    }
                    .zIndex(hoveredID == note.id ? 500 : 0)
                    .staged(index: index, revealed: revealed, onRight: onRight)
            }
        }
    }

    private func updateHover(note: Note, inside: Bool) {
        hoverTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) { hoveredID = inside ? note.id : nil }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            onHoverNote(inside ? note.id : nil)
        }
        guard inside, openOnHover, openID != note.id else { return }
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, hoveredID == note.id else { return }
            onOpen(note.id)
        }
    }
}

private struct NoteTab: View {
    let note: Note
    let labelled: Bool
    let fontName: String
    let edge: DeckEdge
    let isOpen: Bool
    let isHovered: Bool
    let onHoverChange: (Bool) -> Void
    let action: () -> Void

    private var palette: NotePaletteColor { NotePalette.color(for: note) }
    private var onRight: Bool { edge == .right }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                edgeShape
                    .fill(palette.paper)
                    .overlay {
                        if isOpen { edgeShape.stroke(palette.accent, lineWidth: 2) }
                    }
                    .shadow(color: .black.opacity(isOpen || isHovered ? 0.30 : 0.20),
                            radius: isOpen || isHovered ? 9 : 5,
                            x: onRight ? -3 : 3, y: 2)

                if labelled {
                    Text(note.displayTitle.uppercased())
                        .font(.custom(fontName, size: 11))
                        .tracking(0.15)
                        .foregroundStyle(palette.ink.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 104, height: 52)
                        .rotationEffect(.degrees(onRight ? 90 : -90))
                        // rotationEffect changes drawing, not layout. Constrain
                        // the rotated label to the exposed shingle strip so it
                        // cannot paint over the next tab.
                        .frame(width: 52, height: 112, alignment: .top)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(palette.accent)
                        .frame(width: 10, height: 20).padding(.top, 7)
                }
            }
            .frame(width: labelled ? 54 : 28, height: labelled ? 180 : 34)
            .scaleEffect(isHovered ? 1.025 : 1, anchor: onRight ? .trailing : .leading)
            .offset(x: isHovered ? (onRight ? -10 : 10) : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressButtonStyle())
        .overlay(alignment: onRight ? .topTrailing : .topLeading) {
            if note.isPinned { Circle().fill(palette.accent).frame(width: 6, height: 6).padding(8) }
        }
        .onHover(perform: onHoverChange)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOpen)
        .help(note.displayTitle)
    }

    private var edgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: onRight ? 11 : 0,
                               bottomLeadingRadius: onRight ? 11 : 0,
                               bottomTrailingRadius: onRight ? 0 : 11,
                               topTrailingRadius: onRight ? 0 : 11,
                               style: .continuous)
    }
}

private struct HoverNotePreview: View {
    let note: Note
    private var palette: NotePaletteColor { NotePalette.color(for: note) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(palette.accent).frame(width: 9, height: 9)
                Text(note.displayTitle).font(.headline).lineLimit(1)
                Spacer()
                if note.isPinned { Image(systemName: "pin.fill").font(.caption) }
            }
            Divider().overlay(palette.ink.opacity(0.18))
            Text(note.body.isEmpty ? "Empty note" : note.body)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(palette.ink.opacity(0.82))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(width: 280, height: 210)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 14, y: 5)
    }
}

private struct MoreTab: View {
    let count: Int
    let edge: DeckEdge
    let action: () -> Void
    private var onRight: Bool { edge == .right }

    var body: some View {
        Button("+\(count)", action: action)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
            .frame(width: 48, height: 38)
            .background(edgeShape.fill(Color.black.opacity(0.38)))
            .buttonStyle(.plain)
    }

    private var edgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: onRight ? 9 : 0,
                               bottomLeadingRadius: onRight ? 9 : 0,
                               bottomTrailingRadius: onRight ? 0 : 9,
                               topTrailingRadius: onRight ? 0 : 9)
    }
}

private struct EmptyNoteTab: View {
    let edge: DeckEdge
    let action: () -> Void
    var body: some View {
        Button("NEW NOTE", action: action)
            .font(.system(size: 9, weight: .semibold))
            .frame(width: 52, height: 150)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .buttonStyle(.plain)
    }
}

private struct AddNoteButton: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.44)))
                .scaleEffect(hovering ? 1.08 : 1)
                .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help("New note")
    }
}

private struct NotePullTransition: ViewModifier {
    let hidden: Bool
    let onRight: Bool
    func body(content: Content) -> some View {
        content
            .offset(x: hidden ? (onRight ? 38 : -38) : 0)
            .scaleEffect(hidden ? 0.975 : 1, anchor: onRight ? .trailing : .leading)
            .opacity(hidden ? 0 : 1)
    }
}

private struct StagedTabModifier: ViewModifier {
    let index: Int
    let revealed: Bool
    let onRight: Bool
    func body(content: Content) -> some View {
        content
            .offset(x: revealed ? 0 : (onRight ? 74 : -74))
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.36, dampingFraction: 0.82).delay(Double(index) * 0.045), value: revealed)
    }
}

private extension View {
    func staged(index: Int, revealed: Bool, onRight: Bool) -> some View {
        modifier(StagedTabModifier(index: index, revealed: revealed, onRight: onRight))
    }
}

private struct TabPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}
