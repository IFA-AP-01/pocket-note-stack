import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

                Button { handleCommand(.toggleTask) } label: { Image(systemName: "checklist") }
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

            PocketNoteEditorView(
                text: $draft,
                palette: palette,
                fontSize: preferences.noteFontSize,
                fontName: preferences.noteFontName,
                bridge: bridge,
                onExit: close
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
            let initialBody = note?.body ?? ""
            draft = initialBody
            titleDraft = editableTitle
            usesCustomTitle = note?.customTitle != nil
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
        if !bridge.isDictating, bridge.performBlockCommand(command) { return }
        switch command {
        case .escape:
            if bridge.isDictating { onMicrophone() } else { close() }
        case .togglePin:
            if !bridge.isDictating { model.togglePin(id: noteID) }
        case .cycleColor:
            if !bridge.isDictating { model.cycleColor(id: noteID) }
        case .delete:
            guard !bridge.isDictating else { return }
            model.delete(id: noteID)
            onClose()
        case .archive:
            guard !bridge.isDictating else { return }
            model.setArchived(id: noteID, true)
            onClose()
        case .increaseFont:
            preferences.noteFontSize = min(30, preferences.noteFontSize + 1.5)
        case .decreaseFont:
            preferences.noteFontSize = max(10, preferences.noteFontSize - 1.5)
        case .insertImage:
            insertImage()
        default:
            break
        }
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to add to this note"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let filename = AttachmentManager.shared.saveFile(from: url) else { return }
        bridge.insertImageBlock(filename)
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
                Button("Title") { onCommand(.formatTitle) }.font(.system(size: 18, weight: .bold))
                Button("Heading") { onCommand(.formatHeading) }.font(.system(size: 15, weight: .bold))
                Button("Subheading") { onCommand(.formatSubheading) }.font(.system(size: 14, weight: .semibold))
                Button("Body") { onCommand(.formatBody) }.font(.system(size: 13, weight: .regular))
                Button("Monostyled") { onCommand(.formatMonospaced) }.font(.system(size: 12, weight: .regular, design: .monospaced))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button("• Bulleted List") { onCommand(.formatBulletList) }
                Button("– Dashed List") { onCommand(.formatDashList) }
                Button("1. Numbered List") { onCommand(.formatNumberList) }
                Button("◯ Checklist") { onCommand(.formatCheckList) }
                Button("▍ Block Quote") { onCommand(.formatBlockQuote) }
            }
            Divider()
            HStack(spacing: 16) {
                Button { onCommand(.formatBold) } label: { Image(systemName: "bold") }.help("Bold (⌘B)")
                Button { onCommand(.formatItalic) } label: { Image(systemName: "italic") }.help("Italic (⌘I)")
                Button { onCommand(.formatUnderline) } label: { Image(systemName: "underline") }.help("Underline (⌘U)")
                Button { onCommand(.formatStrikethrough) } label: { Image(systemName: "strikethrough") }.help("Strikethrough (⇧⌘X)")
                Divider().frame(height: 16)
                Button { onCommand(.insertImage) } label: { Image(systemName: "photo") }.help("Insert Image")
            }
        }
        .padding(16)
        .background(palette.paper)
        .foregroundStyle(palette.ink)
        .buttonStyle(.plain)
    }
}
