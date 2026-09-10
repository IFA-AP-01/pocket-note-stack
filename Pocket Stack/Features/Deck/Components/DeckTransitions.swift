import SwiftUI

struct NotePullTransition: ViewModifier {
    let hidden: Bool
    let edge: DeckEdge

    func body(content: Content) -> some View {
        content
            .offset(
                x: hidden ? edge.hiddenTransitionOffset.width : 0,
                y: hidden ? edge.hiddenTransitionOffset.height : 0
            )
            .opacity(hidden ? 0 : 1)
    }
}

struct StagedTabModifier: ViewModifier {
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
                .easeOut(duration: 0.3).delay(Double(index) * DeckMetrics.Animation.stageStaggerDelay),
                value: revealed
            )
    }
}

extension View {
    func staged(index: Int, revealed: Bool, edge: DeckEdge) -> some View {
        modifier(StagedTabModifier(index: index, revealed: revealed, edge: edge))
    }
}

struct TabPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: DeckMetrics.Animation.pressDuration), value: configuration.isPressed)
    }
}

enum DeckMainAxis {
    case horizontal
    case vertical

    func size(length: CGFloat, depth: CGFloat) -> CGSize {
        switch self {
        case .horizontal:
            CGSize(width: length, height: depth)
        case .vertical:
            CGSize(width: depth, height: length)
        }
    }

    func depth(of size: CGSize) -> CGFloat {
        switch self {
        case .horizontal:
            size.height
        case .vertical:
            size.width
        }
    }

    func length(of size: CGSize) -> CGFloat {
        switch self {
        case .horizontal:
            size.width
        case .vertical:
            size.height
        }
    }

}

enum DeckStackOrder {
    case higherIndexOnTop
    case lowerIndexOnTop

    func zIndex(for index: Int, count: Int) -> Double {
        switch self {
        case .higherIndexOnTop:
            Double(index)
        case .lowerIndexOnTop:
            Double(count - index)
        }
    }

    func visibleAlignment(on axis: DeckMainAxis) -> Alignment {
        switch (axis, self) {
        case (.horizontal, .higherIndexOnTop):
            .leading
        case (.horizontal, .lowerIndexOnTop):
            .trailing
        case (.vertical, .higherIndexOnTop):
            .top
        case (.vertical, .lowerIndexOnTop):
            .bottom
        }
    }
}

extension DeckEdge {
    var mainAxis: DeckMainAxis {
        switch self {
        case .bottom:
            .horizontal
        case .left, .right:
            .vertical
        }
    }

    var stackOrder: DeckStackOrder {
        switch self {
        case .left, .bottom, .right:
            .higherIndexOnTop
        }
    }

    var stackVisibleAlignment: Alignment {
        stackOrder.visibleAlignment(on: mainAxis)
    }

    var titleRotation: Angle {
        switch self {
        case .left, .right:
            .degrees(90)
        case .bottom:
            .zero
        }
    }

    var cardSpineAlignment: Alignment {
        switch self {
        case .left: .trailing
        case .right: .leading
        case .bottom: .top
        }
    }

    func stackZIndex(for index: Int, count: Int) -> Double {
        stackOrder.zIndex(for: index, count: count)
    }

    func stackLayout(spacing: CGFloat) -> AnyLayout {
        switch self {
        case .left:
            AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        case .right:
            AnyLayout(VStackLayout(alignment: .trailing, spacing: spacing))
        case .bottom:
            AnyLayout(HStackLayout(alignment: .bottom, spacing: spacing))
        }
    }

    var rootAlignment: Alignment {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        }
    }

    var stagedOffset: CGSize {
        switch self {
        case .left: CGSize(width: -DeckMetrics.Transitions.stagedOffset, height: 0)
        case .right: CGSize(width: DeckMetrics.Transitions.stagedOffset, height: 0)
        case .bottom: CGSize(width: 0, height: DeckMetrics.Transitions.stagedOffset)
        }
    }

    var hiddenTransitionOffset: CGSize {
        switch self {
        case .left: CGSize(width: -DeckMetrics.Transitions.hiddenOffset, height: 0)
        case .right: CGSize(width: DeckMetrics.Transitions.hiddenOffset, height: 0)
        case .bottom: CGSize(width: 0, height: DeckMetrics.Transitions.hiddenOffset)
        }
    }

    var shadowOffset: CGSize {
        switch self {
        case .left: CGSize(width: DeckMetrics.Transitions.shadowOffsetLength, height: DeckMetrics.Transitions.shadowOffsetDepth)
        case .right: CGSize(width: -DeckMetrics.Transitions.shadowOffsetLength, height: DeckMetrics.Transitions.shadowOffsetDepth)
        case .bottom: CGSize(width: 0, height: -DeckMetrics.Transitions.shadowOffsetLength)
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

    var tabSlant: CGFloat {
        switch self {
        case .right, .left: 4.0
        case .bottom: 0.0
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
        case .left: CGSize(width: -(noteSize.width + DeckMetrics.Transitions.collapseAdditionalOffset), height: 0)
        case .right: CGSize(width: noteSize.width + DeckMetrics.Transitions.collapseAdditionalOffset, height: 0)
        case .bottom: CGSize(width: 0, height: noteSize.height + DeckMetrics.Transitions.collapseAdditionalOffset)
        }
    }
}
