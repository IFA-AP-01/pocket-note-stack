import SwiftUI

struct NoteFan: View {
    let notes: [Note]
    let hasNavigation: Bool
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let openIDs: Set<UUID>
    var dictatingNoteID: UUID? = nil
    var audioLevel: Float = 0.0
    let revealTick: Int
    let style: DeckStyle
    let labelFontName: String
    let edge: DeckEdge
    let openOnHover: Bool
    let onOpen: (UUID) -> Void
    let onFrameChange: (UUID, CGRect?) -> Void
    let onReorder: (UUID, UUID?) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCreate: () -> Void
    let onDelete: (UUID) -> Void
    var onStopDictation: ((UUID) -> Void)? = nil
    let onInteractionChange: (Bool) -> Void

    @State private var revealed = false
    @State private var hoveredID: UUID?
    @State private var previewedID: UUID?
    @State private var hoverTask: Task<Void, Never>?
    @State private var fanSurfaceHovered = false
    @State private var lastMouseLocation: CGPoint = .zero
    @State private var lastMouseTime: Date = Date()
    @State private var mouseVelocity: CGFloat = 0

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
        .onContinuousHover(coordinateSpace: .local) { phase in
            let now = Date()
            if case .active(let location) = phase {
                let timeSince = now.timeIntervalSince(lastMouseTime)
                if timeSince > 0 && timeSince < 0.2 {
                    let distance = hypot(location.x - lastMouseLocation.x, location.y - lastMouseLocation.y)
                    let currentVelocity = distance / CGFloat(timeSince)
                    mouseVelocity = mouseVelocity * 0.5 + currentVelocity * 0.5
                } else if timeSince >= 0.2 {
                    mouseVelocity = 0
                }
                lastMouseLocation = location
            }
            lastMouseTime = now
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
                    isOpen: openIDs.contains(note.id),
                    isHovered: hoveredID == note.id,
                    isPreviewed: previewedID == note.id,
                    isDictating: dictatingNoteID == note.id,
                    audioLevel: audioLevel,
                    onHoverChange: { updateHover(note: note, inside: $0) },
                    onFrameChange: { onFrameChange(note.id, $0) },
                    action: { open(note.id) },
                    onDelete: { onDelete(note.id) },
                    onStopDictation: { onStopDictation?(note.id) }
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
                let enterTime = Date()
                while true {
                    let now = Date()
                    let timeSinceEnter = now.timeIntervalSince(enterTime)
                    let timeSinceLastMove = now.timeIntervalSince(lastMouseTime)
                    
                    let effectiveVelocity = timeSinceLastMove > 0.1 ? 0 : mouseVelocity
                    
                    if timeSinceEnter >= DeckMetrics.Animation.hoverPreviewDelay {
                        if effectiveVelocity <= DeckMetrics.Animation.hoverVelocityThreshold {
                            break
                        }
                    }
                    
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    guard !Task.isCancelled, hoveredID == note.id else { return }
                }

                withAnimation(.easeOut(duration: 0.25)) {
                    previewedID = note.id
                }

                guard openOnHover else { return }
                try? await Task.sleep(nanoseconds: UInt64(DeckMetrics.Animation.hoverOpenDelay * 1_000_000_000))
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
