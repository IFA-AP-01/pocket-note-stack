import SwiftUI

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
    let onFrameChange: (CGRect?) -> Void
    let action: () -> Void
    let onDelete: () -> Void
    var onStopDictation: (() -> Void)? = nil

    private var palette: NotePaletteColor { NotePalette.color(for: note) }
    private var isExpanded: Bool { isPreviewed && !isOpen }
    private var closedDepth: CGFloat { labelled ? DeckMetrics.Tab.closedDepthLabelled : DeckMetrics.Tab.closedDepthUnlabelled }
    private var closedLength: CGFloat {
        labelled
            ? DeckMetrics.Tab.closedLengthLabelled(on: edge.mainAxis)
            : DeckMetrics.Tab.closedLengthUnlabelled
    }
    private var hoverDepth: CGFloat { closedDepth + (isHovered && !isOpen && !isExpanded ? DeckMetrics.Tab.hoverDepthIncrease : 0) }
    private var closedSize: CGSize { edge.mainAxis.size(length: closedLength, depth: hoverDepth) }
    private var previewSize: CGSize { DeckMetrics.Tab.previewSize }
    private var titleStripLength: CGFloat {
        edge.mainAxis.length(of: isExpanded ? previewSize : closedSize)
    }
    private var closedContentSize: CGSize {
        edge.mainAxis.size(
            length: DeckMetrics.Tab.closedContentLength,
            depth: DeckMetrics.Tab.closedContentThickness
        )
    }

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

                tabContent
            }
            .frame(
                width: isExpanded ? previewSize.width : closedSize.width,
                height: isExpanded ? previewSize.height : closedSize.height,
                alignment: edge.rootAlignment
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressButtonStyle())
        .overlay(alignment: edge.pinAlignment) {
            if note.isPinned { Circle().fill(palette.accent).frame(width: DeckMetrics.Tab.pinIndicatorSize, height: DeckMetrics.Tab.pinIndicatorSize).padding(DeckMetrics.Tab.pinIndicatorPadding) }
        }
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("DeckContainer"))
        } action: { frame in
            onFrameChange(frame)
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
        .onDisappear { onFrameChange(nil) }
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
                .frame(width: closedContentSize.width, height: closedContentSize.height)
        }
    }

    @ViewBuilder private var tabContent: some View {
        if labelled {
            labelledContent
        } else if isExpanded {
            previewContent
        } else {
            closedContent
        }
    }

    @ViewBuilder private var labelledContent: some View {
        switch edge {
        case .left:
            HStack(spacing: 0) {
                titleStrip
                if isExpanded { verticalDivider; mainContent.transition(.opacity) }
            }
        case .right:
            HStack(spacing: 0) {
                if isExpanded { mainContent.transition(.opacity); verticalDivider }
                titleStrip
            }
        case .bottom:
            VStack(spacing: 0) {
                if isExpanded { mainContent.transition(.opacity); horizontalDivider }
                titleStrip
            }
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
            switch edge.mainAxis {
            case .horizontal:
                palette.accent.frame(height: DeckMetrics.Tab.previewStripThickness)
            case .vertical:
                palette.accent.frame(width: DeckMetrics.Tab.previewStripThickness)
            }
        }
    }

    private var titleStrip: some View {
        Group {
            switch edge.mainAxis {
            case .horizontal:
                titleText
                    .frame(
                        width: titleStripLength,
                        height: DeckMetrics.Tab.closedDepthLabelled,
                        alignment: edge.stackVisibleAlignment
                    )
            case .vertical:
                titleText
                    .rotationEffect(edge.titleRotation)
                    .frame(
                        width: DeckMetrics.Tab.closedDepthLabelled,
                        height: DeckMetrics.Tab.exposedLengthLabelled
                    )
                    .frame(
                        width: DeckMetrics.Tab.closedDepthLabelled,
                        height: titleStripLength,
                        alignment: edge.stackVisibleAlignment
                    )
                    .clipped()
            }
        }
        .font(.custom(fontName, size: DeckMetrics.Tab.titleFontSize))
        .tracking(DeckMetrics.Tab.titleTracking)
        .foregroundStyle(palette.ink.opacity(0.86))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var titleText: some View {
        Text(note.displayTitle.uppercased())
            .padding(.horizontal, DeckMetrics.Tab.titleInset)
            .frame(
                width: DeckMetrics.Tab.exposedLengthLabelled,
                height: DeckMetrics.Tab.closedDepthLabelled,
                alignment: .leading
            )
    }

    private var verticalDivider: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: previewSize.height))
        }
        .stroke(palette.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 1, height: previewSize.height)
    }

    private var horizontalDivider: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: previewSize.width, y: 0))
        }
        .stroke(palette.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: previewSize.width, height: 1)
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
