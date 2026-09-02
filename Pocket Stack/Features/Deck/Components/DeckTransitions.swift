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

extension DeckEdge {
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
