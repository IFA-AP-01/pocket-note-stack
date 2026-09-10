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
    private var currentSlant: CGFloat {
        isExpanded ? 0 : edge.tabSlant
    }
    private var closedDepth: CGFloat {
        labelled
            ? DeckMetrics.Tab.closedDepthLabelled(on: edge.mainAxis)
            : DeckMetrics.Tab.closedDepthUnlabelled
    }
    private var closedLength: CGFloat {
        labelled
            ? DeckMetrics.Tab.closedLengthLabelled(on: edge.mainAxis)
            : DeckMetrics.Tab.closedLengthUnlabelled
    }
    private var closedSize: CGSize { edge.mainAxis.size(length: closedLength, depth: closedDepth) }
    private var previewSize: CGSize { DeckMetrics.Tab.previewSize(on: edge.mainAxis) }
    private var currentSize: CGSize {
        CGSize(
            width: isExpanded ? previewSize.width : closedSize.width,
            height: isExpanded ? previewSize.height : closedSize.height
        )
    }
    private var closedContentSize: CGSize {
        edge.mainAxis.size(
            length: DeckMetrics.Tab.closedContentLength,
            depth: DeckMetrics.Tab.closedContentThickness
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: edge.cardSpineAlignment) {
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

                if labelled {
                    cardContent
                        .frame(
                            width: currentSize.width,
                            height: currentSize.height,
                            alignment: edge.cardSpineAlignment
                        )
                        .clipped()
                } else {
                    unlabelledContent
                }
            }
            .frame(
                width: currentSize.width,
                height: currentSize.height,
                alignment: edge.rootAlignment
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressButtonStyle())
        .overlay(alignment: edge.pinAlignment) {
            if note.isPinned {
                Circle()
                    .fill(palette.accent)
                    .frame(width: DeckMetrics.Tab.pinIndicatorSize, height: DeckMetrics.Tab.pinIndicatorSize)
                    .padding(DeckMetrics.Tab.pinIndicatorPadding)
            }
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
        .animation(.spring(response: DeckMetrics.Animation.expandSpringResponse, dampingFraction: DeckMetrics.Animation.expandSpringDamping), value: isHovered)
        .animation(.spring(response: DeckMetrics.Animation.openSpringResponse, dampingFraction: DeckMetrics.Animation.openSpringDamping), value: isOpen)
        .help(note.displayTitle)
    }

    @ViewBuilder private var cardContent: some View {
        switch edge {
        case .left:
            HStack(spacing: 0) {
                mainContent
                    .frame(width: max(0, previewSize.width - closedDepth), height: previewSize.height)
                    .clipped()
                verticalTitleStrip
            }
            .frame(width: previewSize.width, height: previewSize.height)
        case .right:
            HStack(spacing: 0) {
                verticalTitleStrip
                mainContent
                    .frame(width: max(0, previewSize.width - closedDepth), height: previewSize.height)
                    .clipped()
            }
            .frame(width: previewSize.width, height: previewSize.height)
        case .bottom:
            VStack(spacing: 0) {
                horizontalTitleStrip
                mainContent
                    .frame(width: previewSize.width, height: max(0, previewSize.height - closedDepth))
                    .clipped()
            }
            .frame(width: previewSize.width, height: previewSize.height)
        }
    }

    private var displayTabTitle: String {
        let maxChars = edge.mainAxis == .vertical ? 9 : 18
        return Self.formatTabTitle(note.displayTitle, maxCharacters: maxChars)
    }

    static func formatTabTitle(_ title: String, maxCharacters: Int) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count > maxCharacters else { return clean }

        let words = clean.split(separator: " ").map(String.init)
        if words.count > 1 {
            var result = ""
            for word in words {
                let candidate = result.isEmpty ? word : "\(result) \(word)"
                if candidate.count <= maxCharacters {
                    result = candidate
                } else {
                    break
                }
            }
            if !result.isEmpty {
                return result
            }
        }

        return String(clean.prefix(maxCharacters))
    }

    private var verticalTitleStrip: some View {
        ZStack(alignment: .top) {
            Text(displayTabTitle)
                .font(.system(size: DeckMetrics.Tab.titleFontSize, weight: .semibold, design: .default))
                .tracking(DeckMetrics.Tab.titleTracking)
                .foregroundStyle(palette.ink.opacity(0.60))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 2)
                .frame(
                    width: DeckMetrics.Tab.exposedLengthLabelled(on: .vertical) - 8,
                    height: closedDepth,
                    alignment: .leading
                )
                .clipped()
                .rotationEffect(edge.titleRotation)
                .frame(
                    width: closedDepth,
                    height: DeckMetrics.Tab.exposedLengthLabelled(on: .vertical) - 8,
                    alignment: .center
                )
                .padding(.top, 8)

            Path { path in
                let xTop = edge == .right ? closedDepth - 4 : 4
                let xBottom = edge == .right ? closedDepth - 4 + currentSlant : 4 - currentSlant
                path.move(to: CGPoint(x: xTop, y: 0))
                path.addLine(to: CGPoint(x: xBottom, y: previewSize.height))
            }
            .stroke(palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1.0, dash: [2.5, 2.5]))
        }
        .frame(width: closedDepth, height: previewSize.height, alignment: .top)
    }

    private var horizontalTitleStrip: some View {
        ZStack(alignment: .leading) {
            Text(displayTabTitle)
                .font(.system(size: DeckMetrics.Tab.titleFontSize, weight: .semibold, design: .default))
                .tracking(DeckMetrics.Tab.titleTracking)
                .foregroundStyle(palette.ink.opacity(0.60))
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 12)
                .frame(width: DeckMetrics.Tab.exposedLengthLabelled(on: .horizontal) - 16, alignment: .leading)
                .clipped()

            Path { path in
                path.move(to: CGPoint(x: 0, y: closedDepth - 4))
                path.addLine(to: CGPoint(x: previewSize.width, y: closedDepth - 4))
            }
            .stroke(palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1.0, dash: [2.5, 2.5]))
        }
        .frame(width: previewSize.width, height: closedDepth, alignment: .leading)
    }

    @ViewBuilder private var unlabelledContent: some View {
        if isExpanded {
            switch edge {
            case .left:
                HStack(spacing: 0) {
                    mainContent
                    palette.accent.frame(width: DeckMetrics.Tab.previewStripThickness)
                }
            case .right:
                HStack(spacing: 0) {
                    palette.accent.frame(width: DeckMetrics.Tab.previewStripThickness)
                    mainContent
                }
            case .bottom:
                VStack(spacing: 0) {
                    palette.accent.frame(height: DeckMetrics.Tab.previewStripThickness)
                    mainContent
                }
            }
        } else {
            RoundedRectangle(cornerRadius: DeckMetrics.Tab.closedContentCornerRadius)
                .fill(palette.accent)
                .frame(width: closedContentSize.width, height: closedContentSize.height)
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.displayTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
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
                        .foregroundStyle(palette.ink.opacity(0.5))
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
                .foregroundStyle(palette.ink.opacity(0.88))
                .lineSpacing(DeckMetrics.Tab.bodyLineSpacing)
                .lineLimit(DeckMetrics.Tab.bodyLineLimit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(DeckMetrics.Tab.contentPadding)
    }

    private var edgeShape: SlantedTabShape {
        SlantedTabShape(
            cornerRadius: DeckMetrics.Tab.cornerRadius,
            slant: currentSlant,
            edge: edge
        )
    }
}

struct SlantedTabShape: Shape {
    var cornerRadius: CGFloat
    var slant: CGFloat
    var edge: DeckEdge

    var animatableData: CGFloat {
        get { slant }
        set { slant = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)

        switch edge {
        case .right:
            let topLeading = CGPoint(x: 0, y: 0)
            let bottomLeading = CGPoint(x: slant, y: rect.height)
            let bottomTrailing = CGPoint(x: rect.width, y: rect.height)
            let topTrailing = CGPoint(x: rect.width, y: 0)

            path.move(to: topTrailing)
            path.addLine(to: CGPoint(x: topLeading.x + r, y: topLeading.y))
            path.addQuadCurve(
                to: CGPoint(x: topLeading.x, y: topLeading.y + r),
                control: topLeading
            )
            path.addLine(to: CGPoint(x: bottomLeading.x, y: bottomLeading.y - r))
            path.addQuadCurve(
                to: CGPoint(x: bottomLeading.x + r, y: bottomLeading.y),
                control: bottomLeading
            )
            path.addLine(to: bottomTrailing)
            path.closeSubpath()

        case .left:
            let topLeading = CGPoint(x: 0, y: 0)
            let bottomLeading = CGPoint(x: 0, y: rect.height)
            let bottomTrailing = CGPoint(x: rect.width - slant, y: rect.height)
            let topTrailing = CGPoint(x: rect.width, y: 0)

            path.move(to: topLeading)
            path.addLine(to: bottomLeading)
            path.addLine(to: CGPoint(x: bottomTrailing.x - r, y: bottomTrailing.y))
            path.addQuadCurve(
                to: CGPoint(x: bottomTrailing.x, y: bottomTrailing.y - r),
                control: bottomTrailing
            )
            path.addLine(to: CGPoint(x: topTrailing.x, y: topTrailing.y + r))
            path.addQuadCurve(
                to: CGPoint(x: topTrailing.x - r, y: topTrailing.y),
                control: topTrailing
            )
            path.closeSubpath()

        case .bottom:
            path.move(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
            path.addLine(to: CGPoint(x: rect.width - r, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: r), control: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.closeSubpath()
        }

        return path
    }
}
