import SwiftUI

struct NoteTabFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct NoteTab: View {
    let note: Note
    let labelled: Bool
    let fontName: String
    let edge: DeckEdge
    let isOpen: Bool
    let isHovered: Bool
    let isPreviewed: Bool
    var isDictating: Bool = false
    var audioLevel: Float = 0.0
    let onHoverChange: (Bool) -> Void
    let action: () -> Void
    let onDelete: () -> Void
    var onStopDictation: (() -> Void)? = nil

    private var palette: NotePaletteColor { NotePalette.color(for: note) }
    private var isExpanded: Bool { isPreviewed && !isOpen }
    private var closedDepth: CGFloat { labelled ? DeckMetrics.Tab.closedDepthLabelled : DeckMetrics.Tab.closedDepthUnlabelled }
    private var closedLength: CGFloat { labelled ? DeckMetrics.Tab.closedLengthLabelled : DeckMetrics.Tab.closedLengthUnlabelled }
    private var hoverDepth: CGFloat { closedDepth + (isHovered && !isOpen && !isExpanded ? DeckMetrics.Tab.hoverDepthIncrease : 0) }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: edge.rootAlignment) {
                edgeShape
                    .fill(palette.paper)
                    .overlay {
                        if isOpen { edgeShape.stroke(palette.accent, lineWidth: DeckMetrics.Tab.borderLineWidth) }
                    }
                    .shadow(
                        color: .black.opacity(isOpen || isHovered ? DeckMetrics.Tab.shadowOpacityActive : DeckMetrics.Tab.shadowOpacityIdle),
                        radius: isOpen || isHovered ? DeckMetrics.Tab.shadowRadiusActive : DeckMetrics.Tab.shadowRadiusIdle,
                        x: edge.shadowOffset.width,
                        y: edge.shadowOffset.height
                    )

                if isExpanded { previewContent } else { closedContent }
            }
            .frame(
                width: isExpanded ? DeckMetrics.Tab.expandedWidth : (edge == .bottom ? closedLength : hoverDepth),
                height: isExpanded ? DeckMetrics.Tab.expandedHeight : (edge == .bottom ? hoverDepth : closedLength),
                alignment: edge.rootAlignment
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressButtonStyle())
        .overlay(alignment: edge.pinAlignment) {
            if note.isPinned { Circle().fill(palette.accent).frame(width: DeckMetrics.Tab.pinIndicatorSize, height: DeckMetrics.Tab.pinIndicatorSize).padding(DeckMetrics.Tab.pinIndicatorPadding) }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: NoteTabFramesPreferenceKey.self,
                    value: [note.id: geo.frame(in: .named("DeckContainer"))]
                )
            }
        }
        .contextMenu {
            if isDictating {
                Button {
                    onStopDictation?()
                } label: {
                    Label("Stop Dictation", systemImage: "stop.fill")
                }
                Divider()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .onHover(perform: onHoverChange)
        .animation(.spring(response: DeckMetrics.Animation.expandSpringResponse, dampingFraction: DeckMetrics.Animation.expandSpringDamping), value: isExpanded)
        .animation(.easeOut(duration: DeckMetrics.Animation.hoverDuration), value: isHovered)
        .animation(.spring(response: DeckMetrics.Animation.openSpringResponse, dampingFraction: DeckMetrics.Animation.openSpringDamping), value: isOpen)
        .help(note.displayTitle)
    }

    @ViewBuilder private var closedContent: some View {
        if labelled {
            titleStrip
        } else {
            RoundedRectangle(cornerRadius: DeckMetrics.Tab.closedContentCornerRadius)
                .fill(palette.accent)
                .frame(width: edge == .bottom ? DeckMetrics.Tab.closedContentLength : DeckMetrics.Tab.closedContentThickness, height: edge == .bottom ? DeckMetrics.Tab.closedContentThickness : DeckMetrics.Tab.closedContentLength)
        }
    }

    @ViewBuilder private var previewContent: some View {
        switch edge {
        case .left:
            HStack(spacing: 0) { previewStrip; verticalDivider; mainContent }
        case .right:
            HStack(spacing: 0) { mainContent; verticalDivider; previewStrip }
        case .bottom:
            VStack(spacing: 0) { mainContent; horizontalDivider; previewStrip }
        }
    }

    @ViewBuilder private var previewStrip: some View {
        if labelled {
            titleStrip
        } else {
            palette.accent
                .frame(width: edge == .bottom ? nil : DeckMetrics.Tab.previewStripThickness, height: edge == .bottom ? DeckMetrics.Tab.previewStripThickness : nil)
        }
    }

    private var titleStrip: some View {
        Group {
            if edge == .bottom {
                Text(note.displayTitle.uppercased())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(note.displayTitle.uppercased())
                    .frame(width: DeckMetrics.Tab.verticalTitleLength, height: DeckMetrics.Tab.closedDepthLabelled)
                    .rotationEffect(.degrees(edge == .right ? -90 : 90))
                    .frame(width: DeckMetrics.Tab.closedDepthLabelled, height: DeckMetrics.Tab.closedLengthLabelled)
                    .clipped()
            }
        }
        .font(.custom(fontName, size: DeckMetrics.Tab.titleFontSize))
        .tracking(DeckMetrics.Tab.titleTracking)
        .foregroundStyle(palette.ink.opacity(0.86))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: edge == .bottom ? nil : DeckMetrics.Tab.closedDepthLabelled, height: edge == .bottom ? DeckMetrics.Tab.closedDepthLabelled : nil)
    }

    private var verticalDivider: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: DeckMetrics.Tab.expandedHeight))
        }
        .stroke(palette.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 1, height: DeckMetrics.Tab.expandedHeight)
    }

    private var horizontalDivider: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: DeckMetrics.Tab.expandedWidth, y: 0))
        }
        .stroke(palette.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: DeckMetrics.Tab.expandedWidth, height: 1)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.displayTitle)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                Spacer()
                if isDictating {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Dictating")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12), in: Capsule())
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.ink.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Delete note")
            }

            if isDictating {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)

                    Text("Voice input active…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.ink.opacity(0.8))

                    Spacer()

                    WaveSoundBar(level: audioLevel, color: palette.accent)
                        .frame(width: 36, height: 14)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.accent.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(palette.accent.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            Text(note.body.isEmpty ? "Empty note" : note.body)
                .font(.custom(fontName, size: DeckMetrics.Tab.bodyFontSize))
                .foregroundStyle(palette.ink.opacity(0.9))
                .lineSpacing(DeckMetrics.Tab.bodyLineSpacing)
                .lineLimit(DeckMetrics.Tab.bodyLineLimit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(DeckMetrics.Tab.contentPadding)
    }

    private var edgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: edge == .right || edge == .bottom ? DeckMetrics.Tab.cornerRadius : 0,
            bottomLeadingRadius: edge == .right ? DeckMetrics.Tab.cornerRadius : 0,
            bottomTrailingRadius: edge == .left ? DeckMetrics.Tab.cornerRadius : 0,
            topTrailingRadius: edge == .left || edge == .bottom ? DeckMetrics.Tab.cornerRadius : 0,
            style: .continuous
        )
    }
}
