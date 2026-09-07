import SwiftUI

struct DeckRootView: View {
    let model: AppModel
    let preferences: AppPreferences
    let noteWindows: NoteWindowCoordinator
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
            openIDs: noteWindows.openNoteIDs,
            dictatingNoteID: noteWindows.dictatingNoteID,
            audioLevel: noteWindows.audioLevel,
            revealTick: state.revealTick,
            style: preferences.style,
            labelFontName: preferences.noteFontName,
            edge: edge,
            openOnHover: preferences.openOnHover,
            onOpen: controller.openNote,
            onReorder: model.reorder,
            onPrevious: { state.tabWindowStart = window.movingPrevious().startIndex },
            onNext: { state.tabWindowStart = window.movingNext().startIndex },
            onCreate: controller.createNote,
            onDelete: controller.deleteNote,
            onStopDictation: { _ in noteWindows.stopDictation() },
            onInteractionChange: controller.fanInteractionChanged
        )
        .onHover { isHovering in
            if isHovering {
                NSCursor.arrow.set()
            }
        }
    }

    @ViewBuilder private var activeDeck: some View {
        fan
            .coordinateSpace(name: "DeckContainer")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.rootAlignment)
            .onPreferenceChange(NoteTabFramesPreferenceKey.self) { frames in
                controller.updateTabFrames(frames)
            }
    }
}
