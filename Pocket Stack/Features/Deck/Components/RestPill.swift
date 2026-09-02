import SwiftUI

struct RestPill: View {
    let notes: [Note]
    let edge: DeckEdge

    var body: some View {
        (edge == .bottom ? AnyLayout(HStackLayout(spacing: DeckMetrics.RestPill.spacing)) : AnyLayout(VStackLayout(spacing: DeckMetrics.RestPill.spacing))) {
            if notes.isEmpty { dash(.secondary.opacity(0.5)) }
            ForEach(notes.prefix(DeckMetrics.RestPill.maxNotes)) { note in dash(NotePalette.color(for: note).accent) }
        }
        .padding(edge == .bottom ? .horizontal : .vertical, DeckMetrics.RestPill.padding)
        .frame(width: edge == .bottom ? nil : DeckMetrics.RestPill.crossAxisSize, height: edge == .bottom ? DeckMetrics.RestPill.crossAxisSize : nil)
        .background(
            RoundedRectangle(cornerRadius: DeckMetrics.RestPill.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(DeckMetrics.RestPill.backgroundOpacity))
                .shadow(
                    color: .black.opacity(DeckMetrics.RestPill.shadowOpacity), radius: DeckMetrics.RestPill.shadowRadius,
                    x: edge == .right ? -DeckMetrics.Transitions.shadowOffsetDepth : (edge == .left ? DeckMetrics.Transitions.shadowOffsetDepth : 0),
                    y: edge == .bottom ? -DeckMetrics.Transitions.shadowOffsetDepth : 1
                )
        )
    }

    private func dash(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: DeckMetrics.RestPill.dashCornerRadius, style: .continuous)
            .fill(color)
            .frame(width: edge == .bottom ? DeckMetrics.RestPill.dashLength : DeckMetrics.RestPill.dashThickness, height: edge == .bottom ? DeckMetrics.RestPill.dashThickness : DeckMetrics.RestPill.dashLength)
    }
}
