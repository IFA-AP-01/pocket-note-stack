import CoreGraphics

struct NoteWindowAnchor: Equatable {
    let displayID: CGDirectDisplayID
    let edge: DeckEdge
    let tabFrame: CGRect
}
