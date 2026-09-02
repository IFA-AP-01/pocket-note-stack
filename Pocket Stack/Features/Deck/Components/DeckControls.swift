import SwiftUI

enum DeckNavigationDirection { case previous, next }

struct DeckNavigationButton: View {
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
                .font(.system(size: DeckMetrics.Navigation.iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? DeckMetrics.Navigation.opacityEnabled : DeckMetrics.Navigation.opacityDisabled))
                .frame(width: DeckMetrics.Navigation.buttonSize, height: DeckMetrics.Navigation.buttonSize)
                .background(
                    Group {
                        if #available(macOS 12.0, *) {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        } else {
                            Circle().fill(Color.black.opacity(enabled ? DeckMetrics.Navigation.backgroundOpacityEnabled : DeckMetrics.Navigation.backgroundOpacityDisabled))
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(direction == .previous ? "Previous note" : "Next note")
    }
}

struct EmptyNoteTab: View {
    let edge: DeckEdge
    let action: () -> Void

    var body: some View {
        Button("NEW NOTE", action: action)
            .font(.system(size: DeckMetrics.EmptyTab.fontSize, weight: .semibold))
            .frame(width: edge == .bottom ? DeckMetrics.EmptyTab.length : DeckMetrics.EmptyTab.depth, height: edge == .bottom ? DeckMetrics.EmptyTab.depth : DeckMetrics.EmptyTab.length)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DeckMetrics.EmptyTab.cornerRadius))
            .buttonStyle(.plain)
    }
}

struct AddNoteButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: DeckMetrics.AddButton.iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(DeckMetrics.AddButton.iconOpacity))
                .frame(width: DeckMetrics.AddButton.size, height: DeckMetrics.AddButton.size)
                .background(Circle().fill(Color.black.opacity(DeckMetrics.AddButton.backgroundOpacity)))
                .scaleEffect(hovering ? DeckMetrics.AddButton.hoverScale : 1)
                .shadow(color: .black.opacity(0.24), radius: DeckMetrics.AddButton.shadowRadius, y: DeckMetrics.AddButton.shadowY)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: DeckMetrics.Animation.hoverDuration), value: hovering)
        .help("New note")
    }
}
