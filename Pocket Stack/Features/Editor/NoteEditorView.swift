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
    @State private var titleDraft = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var usesCustomTitle = false
    @State private var showsColorChooser = false
    @State private var showsFormatChooser = false
    @FocusState private var titleFocused: Bool

    private var note: Note? { model.note(id: noteID) }
    private var palette: NotePaletteColor { note.map(NotePalette.color(for:)) ?? NotePalette.color(0) }
    private var editableTitle: String { note?.customTitle ?? note?.title ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.red.opacity(0.88)))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(bridge.isDictating)
                .help("Close note")

                TextField("New note", text: $titleDraft)
                    .font(.headline)
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 90, maxWidth: .infinity, minHeight: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.ink.opacity(titleFocused ? 0.09 : 0.045))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(titleFocused ? palette.accent.opacity(0.7) : .clear, lineWidth: 1)
                    }
                    .focused($titleFocused)
                    .disabled(bridge.isDictating)
                    .onSubmit { saveContent() }
                    .onExitCommand(perform: close)
                    .layoutPriority(1)
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
            topLeadingRadius: preferences.edge == .right || preferences.edge == .bottom ? 12 : 0,
            bottomLeadingRadius: preferences.edge == .right ? 12 : 0,
            bottomTrailingRadius: preferences.edge == .left ? 12 : 0,
            topTrailingRadius: preferences.edge == .left || preferences.edge == .bottom ? 12 : 0,
            style: .continuous
        ))
        .shadow(
            color: .black.opacity(0.18),
            radius: 12,
            x: preferences.edge == .right ? -5 : (preferences.edge == .left ? 5 : 0),
            y: preferences.edge == .bottom ? -5 : 5
        )
        .onAppear {
            draft = note?.body ?? ""
            titleDraft = editableTitle
            usesCustomTitle = note?.customTitle != nil
            Task { @MainActor in bridge.focus() }
        }
        .onChange(of: draft) { _, _ in
            guard !bridge.isDictating else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                persistContent()
            }
        }
        .onChange(of: titleDraft) { _, value in
            guard titleFocused else { return }
            usesCustomTitle = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                persistContent()
            }
        }
        .onChange(of: editableTitle) { _, value in
            guard !titleFocused else { return }
            titleDraft = value
            usesCustomTitle = note?.customTitle != nil
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused {
                saveContent()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            saveContent()
        }
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
        saveContent()
        onClose()
    }

    private func saveContent() {
        saveTask?.cancel()
        persistContent()
    }

    private func persistContent() {
        model.updateContent(
            id: noteID,
            body: draft,
            customTitle: usesCustomTitle ? titleDraft : nil
        )
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
