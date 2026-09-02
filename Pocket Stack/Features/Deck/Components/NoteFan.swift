import SwiftUI

struct NoteFan: View {
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
            width: edge == .bottom ? nil : DeckMetrics.Fan.crossAxisSize,
            height: edge == .bottom ? DeckMetrics.Fan.crossAxisSize : nil,
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
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: DeckMetrics.Fan.layoutSpacing))
            : AnyLayout(VStackLayout(alignment: edge == .right ? .trailing : .leading, spacing: DeckMetrics.Fan.layoutSpacing))
        ) {
            content()
        }
    }

    private var tabs: some View {
        (edge == .bottom
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: style == .labelled ? DeckMetrics.Fan.tabSpacingLabelled : DeckMetrics.Fan.tabSpacingUnlabelled))
            : AnyLayout(VStackLayout(
                    alignment: edge == .right ? .trailing : .leading,
                    spacing: style == .labelled ? DeckMetrics.Fan.tabSpacingLabelled : DeckMetrics.Fan.tabSpacingUnlabelled
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
            withAnimation(.easeOut(duration: DeckMetrics.Animation.hoverDuration)) {
                hoveredID = note.id
                previewedID = nil
            }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: DeckMetrics.Animation.hoverPreviewDelay)
                guard !Task.isCancelled, hoveredID == note.id else { return }
                withAnimation(.spring(response: DeckMetrics.Animation.previewSpringResponse, dampingFraction: DeckMetrics.Animation.previewSpringDamping)) {
                    previewedID = note.id
                }

                guard openOnHover else { return }
                try? await Task.sleep(for: DeckMetrics.Animation.hoverOpenDelay)
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
        withAnimation(.easeOut(duration: DeckMetrics.Animation.openDuration)) {
            previewedID = nil
            hoveredID = nil
        }
        onOpen(id)
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
        withAnimation(.easeOut(duration: DeckMetrics.Animation.hoverDuration)) {
            hoveredID = nil
            previewedID = nil
        }
        onInteractionChange(fanSurfaceHovered)
    }
}
