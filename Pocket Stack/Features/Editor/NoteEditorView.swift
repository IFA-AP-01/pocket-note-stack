import SwiftUI

struct NoteEditorView: View {
    let noteID: UUID
    let model: AppModel
    let preferences: AppPreferences
    let bridge: EditorBridge
    let onClose: () -> Void
    let onMicrophone: () -> Void
    let dictationState: DictationState

    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showsColorChooser = false
    @State private var showsFormatChooser = false

    private var note: Note? { model.note(id: noteID) }
    private var palette: NotePaletteColor { note.map(NotePalette.color(for:)) ?? NotePalette.color(0) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(note?.displayTitle ?? "New note")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if dictationState != .idle {
                    Text(dictationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: onMicrophone) {
                    Image(systemName: dictationState == .idle ? "mic" : "stop.circle.fill")
                }
                .help(dictationState == .idle ? "Start dictation" : "Stop dictation")
                Button { bridge.toggleTask() } label: { Image(systemName: "checklist") }
                    .disabled(bridge.isDictating)
                
                Button { showsFormatChooser.toggle() } label: {
                    Image(systemName: "textformat.alt")
                }
                .disabled(bridge.isDictating)
                .help("Formatting")
                .popover(isPresented: $showsFormatChooser, arrowEdge: .bottom) {
                    FormattingChooserView(palette: palette, onCommand: { cmd in
                        handleCommand(cmd)
                        showsFormatChooser = false
                    })
                }

                Button { model.togglePin(id: noteID) } label: {
                    Image(systemName: note?.isPinned == true ? "pin.fill" : "pin")
                }
                .disabled(bridge.isDictating)
                Button { showsColorChooser.toggle() } label: {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(palette.accent)
                }
                    .disabled(bridge.isDictating)
                    .help("Choose note colour")
                    .popover(isPresented: $showsColorChooser, arrowEdge: .top) {
                        NoteColorChooser(noteID: noteID, note: note, model: model, palette: palette)
                    }
                Button(action: close) { Image(systemName: "xmark") }
                    .disabled(bridge.isDictating)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider().overlay(palette.accent.opacity(0.45))
            NoteTextView(
                text: $draft,
                bridge: bridge,
                palette: palette,
                fontName: preferences.noteFontName,
                fontSize: preferences.noteFontSize,
                markdown: preferences.markdownStyling,
                onCommand: handleCommand
            )
        }
        .background(palette.paper)
        .foregroundStyle(palette.ink)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: preferences.edge == .right ? 12 : 0,
            bottomLeadingRadius: preferences.edge == .right ? 12 : 0,
            bottomTrailingRadius: preferences.edge == .right ? 0 : 12,
            topTrailingRadius: preferences.edge == .right ? 0 : 12,
            style: .continuous
        ))
        .shadow(color: .black.opacity(0.18), radius: 12, x: preferences.edge == .right ? -5 : 5, y: 5)
        .onAppear { draft = note?.body ?? ""; Task { @MainActor in bridge.focus() } }
        .onChange(of: draft) { _, value in
            guard !bridge.isDictating else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                model.updateBody(id: noteID, body: value)
            }
        }
        .onDisappear { saveTask?.cancel(); model.updateBody(id: noteID, body: draft) }
    }

    private var dictationLabel: String {
        switch dictationState {
        case .idle: ""
        case .preparing: "Preparing…"
        case .listening: "Listening…"
        case .finalizing: "Finishing…"
        case .failed(let message): message
        }
    }

    private func close() {
        saveTask?.cancel()
        model.updateBody(id: noteID, body: draft)
        onClose()
    }

    private func handleCommand(_ command: EditorCommand) {
        switch command {
        case .escape:
            if bridge.isDictating { onMicrophone() } else { close() }
        case .toggleTask: if !bridge.isDictating { bridge.toggleTask() }
        case .togglePin: if !bridge.isDictating { model.togglePin(id: noteID) }
        case .cycleColor: if !bridge.isDictating { model.cycleColor(id: noteID) }
        case .delete:
            guard !bridge.isDictating else { return }
            model.delete(id: noteID); onClose()
        case .archive:
            guard !bridge.isDictating else { return }
            model.setArchived(id: noteID, true); onClose()
        case .increaseFont: preferences.noteFontSize = min(30, preferences.noteFontSize + 1.5)
        case .decreaseFont: preferences.noteFontSize = max(10, preferences.noteFontSize - 1.5)
        
        case .formatTitle: bridge.togglePrefix("# ")
        case .formatHeading: bridge.togglePrefix("## ")
        case .formatSubheading: bridge.togglePrefix("### ")
        case .formatBody: bridge.togglePrefix("")
        case .formatMonospaced: bridge.applyWrap(prefix: "`", suffix: "`")
        
        case .formatBold: bridge.applyWrap(prefix: "**", suffix: "**")
        case .formatItalic: bridge.applyWrap(prefix: "*", suffix: "*")
        case .formatStrikethrough: bridge.applyWrap(prefix: "~~", suffix: "~~")
        case .formatUnderline: bridge.applyWrap(prefix: "<u>", suffix: "</u>")
        
        case .formatBulletList: bridge.togglePrefix("* ")
        case .formatDashList: bridge.togglePrefix("- ")
        case .formatNumberList: bridge.togglePrefix("1. ")
        case .formatCheckList: bridge.toggleTask()
        
        case .insertTable:
            bridge.insertText("\n| Header 1 | Header 2 |\n| -------- | -------- |\n| Cell 1   | Cell 2   |\n")
        case .insertImage:
            // Handled via paste or drop natively in FirstMouseTextView, but we could show a file picker here.
            // For now, let's keep it simple.
            break
        }
    }
}

private struct NoteColorChooser: View {
    let noteID: UUID
    let note: Note?
    let model: AppModel
    let palette: NotePaletteColor

    private var customBinding: Binding<Color> {
        Binding(
            get: { note.map(NotePalette.swiftUIColor(for:)) ?? NotePalette.color(0).paper },
            set: { color in
                guard let hex = NotePalette.hex(color) else { return }
                model.setCustomColor(id: noteID, hex: hex)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note colour").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 9), count: 4), spacing: 9) {
                ForEach(Array(NotePalette.colors.enumerated()), id: \.offset) { index, color in
                    Button { model.setColor(id: noteID, index: index) } label: {
                        ZStack {
                            Circle().fill(color.paper)
                            Circle().stroke(color.accent, lineWidth: note?.customColorHex == nil && note?.colorIndex == index ? 3 : 1)
                            if note?.customColorHex == nil && note?.colorIndex == index {
                                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(color.ink)
                            }
                        }
                        .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                }
            }
            Divider()
            ColorPicker("Custom colour", selection: customBinding, supportsOpacity: false)
        }
        .padding(14)
        .frame(width: 190)
        .background(palette.paper)
        .foregroundStyle(palette.ink)
    }
}

private struct FormattingChooserView: View {
    let palette: NotePaletteColor
    let onCommand: (EditorCommand) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Button("Title") { onCommand(.formatTitle) }.font(.title.bold())
                Button("Heading") { onCommand(.formatHeading) }.font(.title2.weight(.semibold))
                Button("Subheading") { onCommand(.formatSubheading) }.font(.title3.weight(.medium))
                Button("Body") { onCommand(.formatBody) }.font(.body)
                Button("Monostyled") { onCommand(.formatMonospaced) }.font(.system(.body, design: .monospaced))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button("• Bulleted List") { onCommand(.formatBulletList) }
                Button("- Dashed List") { onCommand(.formatDashList) }
                Button("1. Numbered List") { onCommand(.formatNumberList) }
                Button("☑ Checklist") { onCommand(.formatCheckList) }
            }
            Divider()
            HStack(spacing: 16) {
                Button { onCommand(.formatBold) } label: { Image(systemName: "bold") }.help("Bold")
                Button { onCommand(.formatItalic) } label: { Image(systemName: "italic") }.help("Italic")
                Button { onCommand(.formatUnderline) } label: { Image(systemName: "underline") }.help("Underline")
                Button { onCommand(.formatStrikethrough) } label: { Image(systemName: "strikethrough") }.help("Strikethrough")
                Divider().frame(height: 16)
                Button { onCommand(.insertTable) } label: { Image(systemName: "tablecells") }.help("Insert Table")
                Button { onCommand(.insertImage) } label: { Image(systemName: "photo") }.help("Insert Image")
            }
        }
        .padding(16)
        .background(palette.paper)
        .foregroundStyle(palette.ink)
        .buttonStyle(.plain)
    }
}
