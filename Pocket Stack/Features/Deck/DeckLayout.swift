import AppKit

struct DeckTabWindow: Equatable {
    static let capacity = 5

    let startIndex: Int
    let noteCount: Int

    init(startIndex: Int = 0, noteCount: Int) {
        self.noteCount = max(0, noteCount)
        self.startIndex = min(max(0, startIndex), max(0, self.noteCount - Self.capacity))
    }

    var visibleRange: Range<Int> {
        startIndex..<min(noteCount, startIndex + Self.capacity)
    }

    var canMovePrevious: Bool { startIndex > 0 }
    var canMoveNext: Bool { visibleRange.upperBound < noteCount }

    func movingPrevious() -> Self {
        Self(startIndex: startIndex - 1, noteCount: noteCount)
    }

    func movingNext() -> Self {
        Self(startIndex: startIndex + 1, noteCount: noteCount)
    }

    func clamped(to noteCount: Int) -> Self {
        Self(startIndex: startIndex, noteCount: noteCount)
    }
}

enum DeckLayout {
    static func panelFrame(
        state: DeckState,
        edge: DeckEdge,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        noteSize: CGSize,
        noteCount: Int,
        edgeWidth: CGFloat
    ) -> NSRect {
        switch (state, edge) {
        case (.rest, .bottom):
            let width = min(visibleFrame.width, restLength(noteCount: noteCount))
            return NSRect(
                x: clampedCenterOrigin(center: screenFrame.midX, length: width, bounds: visibleFrame.minX...visibleFrame.maxX),
                y: visibleFrame.minY,
                width: width,
                height: max(14, edgeWidth)
            )

        case (.rest, .left), (.rest, .right):
            let width = max(14, edgeWidth)
            let height = min(visibleFrame.height, restLength(noteCount: noteCount))
            let x = edge == .right ? screenFrame.maxX - width : screenFrame.minX
            return NSRect(x: x, y: visibleFrame.midY - height / 2, width: width, height: height)

        case (.fan, .bottom), (.expanded, .bottom):
            let width = min(visibleFrame.width, max(noteSize.width + 84, 880))
            let height = min(visibleFrame.height, noteSize.height + 84)
            return NSRect(
                x: clampedCenterOrigin(center: visibleFrame.midX, length: width, bounds: visibleFrame.minX...visibleFrame.maxX),
                y: visibleFrame.minY,
                width: width,
                height: height
            )

        case (.fan, .left), (.expanded, .left), (.fan, .right), (.expanded, .right):
            let width = min(visibleFrame.width, noteSize.width + 84)
            let x = edge == .right ? screenFrame.maxX - width : screenFrame.minX
            return NSRect(x: x, y: visibleFrame.minY, width: width, height: visibleFrame.height)
        }
    }

    private static func restLength(noteCount: Int) -> CGFloat {
        min(420, max(54, CGFloat(min(max(noteCount, 1), 14)) * 21 + 11))
    }

    private static func clampedCenterOrigin(
        center: CGFloat,
        length: CGFloat,
        bounds: ClosedRange<CGFloat>
    ) -> CGFloat {
        min(max(center - length / 2, bounds.lowerBound), bounds.upperBound - length)
    }
}
