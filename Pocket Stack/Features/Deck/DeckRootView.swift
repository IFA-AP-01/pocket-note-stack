import SwiftUI

struct DeckRootView: View {
    let model: AppModel
    let preferences: AppPreferences
    let state: DeckViewState
    unowned let controller: DeckController

    private var edge: DeckEdge { preferences.edge }
    private var window: DeckTabWindow {
        DeckTabWindow(startIndex: state.tabWindowStart, noteCount: model.activeNotes.count)
    }
    private var visibleNotes: [Note] { Array(model.activeNotes[window.visibleRange]) }

    var body: some View {
        ZStack(alignment: edge.rootAlignment) {
            if state.state == .rest {
                RestPill(notes: model.activeNotes, edge: edge)
                    .transition(.move(edge: edge.transitionEdge))
            } else {
                activeDeck
                    .offset(
                        x: state.isCollapsing ? edge.collapseOffset(noteSize: preferences.noteSize).width : 0,
                        y: state.isCollapsing ? edge.collapseOffset(noteSize: preferences.noteSize).height : 0
                    )
                    .transition(.move(edge: edge.transitionEdge))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.rootAlignment)
        .ignoresSafeArea()
        .onChange(of: model.activeNotes.map(\.id)) { _, ids in
            state.tabWindowStart = DeckTabWindow(
                startIndex: state.tabWindowStart,
                noteCount: ids.count
            ).startIndex
            controller.updateLayout()
        }
    }

    private var fan: some View {
        NoteFan(
            notes: visibleNotes,
            hasNavigation: model.activeNotes.count > DeckTabWindow.capacity,
            canMovePrevious: window.canMovePrevious,
            canMoveNext: window.canMoveNext,
            openID: state.state.expandedID,
            revealTick: state.revealTick,
            style: preferences.style,
            labelFontName: preferences.noteFontName,
            edge: edge,
            openOnHover: preferences.openOnHover,
            onOpen: controller.expand,
            onReorder: model.reorder,
            onPrevious: { state.tabWindowStart = window.movingPrevious().startIndex },
            onNext: { state.tabWindowStart = window.movingNext().startIndex },
            onCreate: controller.createNote,
            onInteractionChange: controller.fanInteractionChanged
        )
    }

    @ViewBuilder private var activeDeck: some View {
        switch edge {
        case .left:
            HStack(spacing: 0) { fan; sideContent }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .right:
            HStack(spacing: 0) { sideContent; fan }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        case .bottom:
            VStack(spacing: 0) { sideContent; fan }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder private var sideContent: some View {
        if let id = state.state.expandedID, model.note(id: id) != nil {
            NoteEditorView(
                noteID: id,
                model: model,
                preferences: preferences,
                bridge: state.editorBridge,
                onClose: controller.closeExpanded,
                onMicrophone: { controller.toggleDictation(noteID: id) },
                dictationState: state.dictationState
            )
            .frame(width: preferences.noteSize.width, height: preferences.noteSize.height)
            .transition(.modifier(
                active: NotePullTransition(hidden: true, edge: edge),
                identity: NotePullTransition(hidden: false, edge: edge)
            ))
            .id(id)
        }
    }
}

private struct RestPill: View {
    let notes: [Note]
    let edge: DeckEdge

    var body: some View {
        (edge == .bottom ? AnyLayout(HStackLayout(spacing: 5)) : AnyLayout(VStackLayout(spacing: 5))) {
            if notes.isEmpty { dash(.secondary.opacity(0.5)) }
            ForEach(notes.prefix(14)) { note in dash(NotePalette.color(for: note).accent) }
        }
        .padding(edge == .bottom ? .horizontal : .vertical, 8)
        .frame(width: edge == .bottom ? nil : 14, height: edge == .bottom ? 14 : nil)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.68))
                .shadow(
                    color: .black.opacity(0.24), radius: 5,
                    x: edge == .right ? -2 : (edge == .left ? 2 : 0),
                    y: edge == .bottom ? -2 : 1
                )
        )
    }

    private func dash(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: edge == .bottom ? 16 : 7, height: edge == .bottom ? 7 : 16)
    }
}

private struct NoteFan: View {
    let notes: [Note]
    let hasNavigation: Bool
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let openID: UUID?
    let revealTick: Int
    let style: DeckStyle
    let labelFontName: String
    let edge: DeckEdge
    let openOnHover: Bool
    let onOpen: (UUID) -> Void
    let onReorder: (UUID, UUID?) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCreate: () -> Void
    let onInteractionChange: (Bool) -> Void

    @State private var revealed = false
    @State private var hoveredID: UUID?
    @State private var previewedID: UUID?
    @State private var hoverTask: Task<Void, Never>?
    @State private var fanSurfaceHovered = false

    var body: some View {
        fanLayout {
            if hasNavigation {
                DeckNavigationButton(direction: .previous, edge: edge, enabled: canMovePrevious, action: onPrevious)
                    .staged(index: 0, revealed: revealed, edge: edge)
            }

            tabs

            if hasNavigation {
                DeckNavigationButton(direction: .next, edge: edge, enabled: canMoveNext, action: onNext)
                    .staged(index: notes.count + 1, revealed: revealed, edge: edge)
            }

            AddNoteButton(action: onCreate)
                .staged(index: notes.count + 2, revealed: revealed, edge: edge)
        }
        .frame(
            width: edge == .bottom ? nil : 46,
            height: edge == .bottom ? 46 : nil,
            alignment: edge.rootAlignment
        )
        .onAppear { revealed = true }
        .onChange(of: revealTick) { _, _ in
            revealed = false
            DispatchQueue.main.async { revealed = true }
        }
        .onHover { inside in
            fanSurfaceHovered = inside
            onInteractionChange(inside || hoveredID != nil)
        }
        .onDisappear {
            cancelHover()
            onInteractionChange(false)
        }
    }

    private func fanLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        (edge == .bottom
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
            : AnyLayout(VStackLayout(alignment: edge == .right ? .trailing : .leading, spacing: 12))
        ) {
            content()
        }
    }

    private var tabs: some View {
        (edge == .bottom
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: style == .labelled ? -66 : 7))
            : AnyLayout(VStackLayout(
                    alignment: edge == .right ? .trailing : .leading,
                    spacing: style == .labelled ? -66 : 7
                ))
        ) {
            if notes.isEmpty {
                EmptyNoteTab(edge: edge, action: onCreate)
                    .staged(index: 0, revealed: revealed, edge: edge)
            }

            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                NoteTab(
                    note: note,
                    labelled: style == .labelled,
                    fontName: labelFontName.isEmpty ? "Noteworthy-Light" : labelFontName,
                    edge: edge,
                    isOpen: openID == note.id,
                    isHovered: hoveredID == note.id,
                    isPreviewed: previewedID == note.id,
                    onHoverChange: { updateHover(note: note, inside: $0) },
                    action: { open(note.id) }
                )
                .draggable(note.id.uuidString)
                .dropDestination(for: String.self) { values, _ in
                    guard let source = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                    onReorder(source, note.id)
                    return true
                }
                .zIndex(hoveredID == note.id ? 500 : Double(index))
                .staged(index: index + (hasNavigation ? 1 : 0), revealed: revealed, edge: edge)
            }
        }
    }

    private func updateHover(note: Note, inside: Bool) {
        if inside {
            onInteractionChange(true)
            hoverTask?.cancel()
            withAnimation(.easeOut(duration: 0.14)) {
                hoveredID = note.id
                previewedID = nil
            }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, hoveredID == note.id else { return }
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    previewedID = note.id
                }

                guard openOnHover else { return }
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled, hoveredID == note.id, previewedID == note.id else { return }
                open(note.id)
            }
        } else if hoveredID == note.id {
            cancelHover()
        }
    }

    private func open(_ id: UUID) {
        hoverTask?.cancel()
        hoverTask = nil
        withAnimation(.easeOut(duration: 0.12)) {
            previewedID = nil
            hoveredID = nil
        }
        onOpen(id)
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
        withAnimation(.easeOut(duration: 0.14)) {
            hoveredID = nil
            previewedID = nil
        }
        onInteractionChange(fanSurfaceHovered)
    }
}

private struct NoteTab: View {
    let note: Note
    let labelled: Bool
    let fontName: String
    let edge: DeckEdge
    let isOpen: Bool
    let isHovered: Bool
    let isPreviewed: Bool
    let onHoverChange: (Bool) -> Void
    let action: () -> Void

    private var palette: NotePaletteColor { NotePalette.color(for: note) }
    private var isExpanded: Bool { isPreviewed && !isOpen }
    private var closedDepth: CGFloat { labelled ? 46 : 24 }
    private var closedLength: CGFloat { labelled ? 180 : 34 }
    private var hoverDepth: CGFloat { closedDepth + (isHovered && !isOpen && !isExpanded ? 6 : 0) }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: edge.rootAlignment) {
                edgeShape
                    .fill(palette.paper)
                    .overlay {
                        if isOpen { edgeShape.stroke(palette.accent, lineWidth: 2) }
                    }
                    .shadow(
                        color: .black.opacity(isOpen || isHovered ? 0.30 : 0.20),
                        radius: isOpen || isHovered ? 9 : 5,
                        x: edge.shadowOffset.width,
                        y: edge.shadowOffset.height
                    )

                if isExpanded { previewContent } else { closedContent }
            }
            .frame(
                width: isExpanded ? 260 : (edge == .bottom ? closedLength : hoverDepth),
                height: isExpanded ? 180 : (edge == .bottom ? hoverDepth : closedLength),
                alignment: edge.rootAlignment
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressButtonStyle())
        .overlay(alignment: edge.pinAlignment) {
            if note.isPinned { Circle().fill(palette.accent).frame(width: 6, height: 6).padding(8) }
        }
        .onHover(perform: onHoverChange)
        .animation(.spring(response: 0.30, dampingFraction: 0.76), value: isExpanded)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isOpen)
        .help(note.displayTitle)
    }

    @ViewBuilder private var closedContent: some View {
        if labelled {
            titleStrip
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.accent)
                .frame(width: edge == .bottom ? 20 : 10, height: edge == .bottom ? 10 : 20)
        }
    }

    @ViewBuilder private var previewContent: some View {
        switch edge {
        case .left:
            HStack(spacing: 0) { previewStrip; verticalDivider; mainContent }
        case .right:
            HStack(spacing: 0) { mainContent; verticalDivider; previewStrip }
        case .bottom:
            VStack(spacing: 0) { mainContent; horizontalDivider; previewStrip }
        }
    }

    @ViewBuilder private var previewStrip: some View {
        if labelled {
            titleStrip
        } else {
            palette.accent
                .frame(width: edge == .bottom ? nil : 12, height: edge == .bottom ? 12 : nil)
        }
    }

    private var titleStrip: some View {
        Group {
            if edge == .bottom {
                Text(note.displayTitle.uppercased())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(note.displayTitle.uppercased())
                    .frame(width: 104, height: 46)
                    .rotationEffect(.degrees(edge == .right ? -90 : 90))
                    .frame(width: 46, height: 180)
                    .clipped()
            }
        }
        .font(.custom(fontName, size: 11))
        .tracking(0.15)
        .foregroundStyle(palette.ink.opacity(0.86))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: edge == .bottom ? nil : 46, height: edge == .bottom ? 46 : nil)
    }

    private var verticalDivider: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: 180))
        }
        .stroke(palette.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 1, height: 180)
    }

    private var horizontalDivider: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 260, y: 0))
        }
        .stroke(palette.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 260, height: 1)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.displayTitle)
                .font(.headline)
                .foregroundStyle(palette.ink)
            Text(note.body.isEmpty ? "Empty note" : note.body)
                .font(.custom(fontName, size: 15))
                .foregroundStyle(palette.ink.opacity(0.9))
                .lineSpacing(2)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
    }

    private var edgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: edge == .right || edge == .bottom ? 11 : 0,
            bottomLeadingRadius: edge == .right ? 11 : 0,
            bottomTrailingRadius: edge == .left ? 11 : 0,
            topTrailingRadius: edge == .left || edge == .bottom ? 11 : 0,
            style: .continuous
        )
    }
}

private enum DeckNavigationDirection { case previous, next }

private struct DeckNavigationButton: View {
    let direction: DeckNavigationDirection
    let edge: DeckEdge
    let enabled: Bool
    let action: () -> Void

    private var symbol: String {
        switch (edge, direction) {
        case (.bottom, .previous): "chevron.left"
        case (.bottom, .next): "chevron.right"
        case (_, .previous): "chevron.up"
        case (_, .next): "chevron.down"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.86 : 0.28))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(enabled ? 0.42 : 0.20)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(direction == .previous ? "Previous note" : "Next note")
    }
}

private struct EmptyNoteTab: View {
    let edge: DeckEdge
    let action: () -> Void

    var body: some View {
        Button("NEW NOTE", action: action)
            .font(.system(size: 9, weight: .semibold))
            .frame(width: edge == .bottom ? 150 : 46, height: edge == .bottom ? 46 : 150)
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
    let edge: DeckEdge

    func body(content: Content) -> some View {
        content
            .offset(
                x: hidden ? edge.hiddenTransitionOffset.width : 0,
                y: hidden ? edge.hiddenTransitionOffset.height : 0
            )
            .scaleEffect(hidden ? 0.975 : 1, anchor: edge.scaleAnchor)
            .opacity(hidden ? 0 : 1)
    }
}

private struct StagedTabModifier: ViewModifier {
    let index: Int
    let revealed: Bool
    let edge: DeckEdge

    func body(content: Content) -> some View {
        content
            .offset(
                x: revealed ? 0 : edge.stagedOffset.width,
                y: revealed ? 0 : edge.stagedOffset.height
            )
            .opacity(revealed ? 1 : 0)
            .animation(
                .spring(response: 0.36, dampingFraction: 0.82).delay(Double(index) * 0.045),
                value: revealed
            )
    }
}

private extension View {
    func staged(index: Int, revealed: Bool, edge: DeckEdge) -> some View {
        modifier(StagedTabModifier(index: index, revealed: revealed, edge: edge))
    }
}

private struct TabPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

private extension DeckEdge {
    var rootAlignment: Alignment {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        }
    }

    var stagedOffset: CGSize {
        switch self {
        case .left: CGSize(width: -74, height: 0)
        case .right: CGSize(width: 74, height: 0)
        case .bottom: CGSize(width: 0, height: 74)
        }
    }

    var hiddenTransitionOffset: CGSize {
        switch self {
        case .left: CGSize(width: -38, height: 0)
        case .right: CGSize(width: 38, height: 0)
        case .bottom: CGSize(width: 0, height: 38)
        }
    }

    var shadowOffset: CGSize {
        switch self {
        case .left: CGSize(width: 3, height: 2)
        case .right: CGSize(width: -3, height: 2)
        case .bottom: CGSize(width: 0, height: -3)
        }
    }

    var scaleAnchor: UnitPoint {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        }
    }

    var pinAlignment: Alignment {
        switch self {
        case .left: .topTrailing
        case .right: .topLeading
        case .bottom: .topTrailing
        }
    }

    var transitionEdge: Edge {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        }
    }

    func collapseOffset(noteSize: CGSize) -> CGSize {
        switch self {
        case .left: CGSize(width: -(noteSize.width + 84), height: 0)
        case .right: CGSize(width: noteSize.width + 84, height: 0)
        case .bottom: CGSize(width: 0, height: noteSize.height + 84)
        }
    }
}
