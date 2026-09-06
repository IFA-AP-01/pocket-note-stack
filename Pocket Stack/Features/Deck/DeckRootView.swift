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

    @State private var activeTabFrame: CGRect? = nil
    private var cardGap: CGFloat { 10 }

    private var fan: some View {
        NoteFan(
            notes: visibleNotes,
            hasNavigation: model.activeNotes.count > DeckTabWindow.capacity,
            canMovePrevious: window.canMovePrevious,
            canMoveNext: window.canMoveNext,
            openID: state.state.expandedID,
            dictatingNoteID: state.dictatingNoteID,
            audioLevel: state.audioLevel,
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
            onDelete: controller.deleteNote,
            onStopDictation: { id in controller.toggleDictation(noteID: id) },
            onInteractionChange: controller.fanInteractionChanged
        )
        .onHover { isHovering in
            if isHovering {
                NSCursor.arrow.set()
            }
        }
    }

    @ViewBuilder private var activeDeck: some View {
        deckLayout
            .coordinateSpace(name: "DeckContainer")
            .onPreferenceChange(ActiveTabFramePreferenceKey.self) { frame in
                activeTabFrame = frame
            }
    }

    @ViewBuilder private var deckLayout: some View {
        switch edge {
        case .left:
            HStack(spacing: cardGap) { fan; sideContent }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .right:
            HStack(spacing: cardGap) { sideContent; fan }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        case .bottom:
            VStack(spacing: cardGap) { sideContent; fan }
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
                activeTabFrame: activeTabFrame,
                onClose: controller.closeExpanded,
                onMicrophone: { controller.toggleDictation(noteID: id) },
                dictationState: state.dictationState,
                audioLevel: state.audioLevel
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
