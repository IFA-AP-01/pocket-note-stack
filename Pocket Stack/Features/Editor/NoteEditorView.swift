import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteCardArrowShape: Shape {
    let edge: DeckEdge
    let offset: CGFloat
    let width: CGFloat = 24
    let height: CGFloat = 8.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let halfW = width / 2

        switch edge {
        case .bottom:
            let y = rect.maxY
            let x = offset
            path.move(to: CGPoint(x: x - halfW - 2, y: y - 1))
            path.addQuadCurve(
                to: CGPoint(x: x - halfW * 0.5, y: y + height * 0.35),
                control: CGPoint(x: x - halfW * 0.9, y: y + 0.5)
            )
            path.addQuadCurve(
                to: CGPoint(x: x, y: y + height),
                control: CGPoint(x: x - halfW * 0.2, y: y + height * 0.9)
            )
            path.addQuadCurve(
                to: CGPoint(x: x + halfW * 0.5, y: y + height * 0.35),
                control: CGPoint(x: x + halfW * 0.2, y: y + height * 0.9)
            )
            path.addQuadCurve(
                to: CGPoint(x: x + halfW + 2, y: y - 1),
                control: CGPoint(x: x + halfW * 0.9, y: y + 0.5)
            )
            path.closeSubpath()

        case .right:
            let x = rect.maxX
            let y = offset
            path.move(to: CGPoint(x: x - 1, y: y - halfW - 2))
            path.addQuadCurve(
                to: CGPoint(x: x + height * 0.35, y: y - halfW * 0.5),
                control: CGPoint(x: x + 0.5, y: y - halfW * 0.9)
            )
            path.addQuadCurve(
                to: CGPoint(x: x + height, y: y),
                control: CGPoint(x: x + height * 0.9, y: y - halfW * 0.2)
            )
            path.addQuadCurve(
                to: CGPoint(x: x + height * 0.35, y: y + halfW * 0.5),
                control: CGPoint(x: x + height * 0.9, y: y + halfW * 0.2)
            )
            path.addQuadCurve(
                to: CGPoint(x: x - 1, y: y + halfW + 2),
                control: CGPoint(x: x + 0.5, y: y + halfW * 0.9)
            )
            path.closeSubpath()

        case .left:
            let x = rect.minX
            let y = offset
            path.move(to: CGPoint(x: x + 1, y: y - halfW - 2))
            path.addQuadCurve(
                to: CGPoint(x: x - height * 0.35, y: y - halfW * 0.5),
                control: CGPoint(x: x - 0.5, y: y - halfW * 0.9)
            )
            path.addQuadCurve(
                to: CGPoint(x: x - height, y: y),
                control: CGPoint(x: x - height * 0.9, y: y - halfW * 0.2)
            )
            path.addQuadCurve(
                to: CGPoint(x: x - height * 0.35, y: y + halfW * 0.5),
                control: CGPoint(x: x - height * 0.9, y: y + halfW * 0.2)
            )
            path.addQuadCurve(
                to: CGPoint(x: x + 1, y: y + halfW + 2),
                control: CGPoint(x: x - 0.5, y: y + halfW * 0.9)
            )
            path.closeSubpath()
        }

        return path
    }
}

private final class NativeThemeFrameProxy: NSObject {
    weak var targetView: NSView?
    init(targetView: NSView) { self.targetView = targetView }
    @objc func window() -> NSWindow? { targetView?.window ?? NSApp.windows.first }
}

private final class NativeCloseWidgetHelper {
    static var key: UInt8 = 0

    static func setup(button: NSButton) {
        // 1. Subclass button to disable layer update (forcing cell.draw), attach tracking area, and handle hover
        let btnSubclassName = "PocketHoverThemeCloseWidget"
        var btnCustomClass: AnyClass? = objc_getClass(btnSubclassName) as? AnyClass
        if btnCustomClass == nil {
            btnCustomClass = objc_allocateClassPair(type(of: button), btnSubclassName, 0)

            // wantsUpdateLayer -> false ensures AppKit calls drawRect: -> cell.draw(withFrame:in:)
            let wulBlock: @convention(block) (NSButton) -> Bool = { _ in false }
            class_addMethod(btnCustomClass, NSSelectorFromString("wantsUpdateLayer"), imp_implementationWithBlock(wulBlock), "B@:")

            // updateTrackingAreas -> installs tracking area covering full button bounds
            let utaBlock: @convention(block) (NSButton) -> Void = { b in
                b.trackingAreas.forEach(b.removeTrackingArea)
                let area = NSTrackingArea(
                    rect: b.bounds,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: b
                )
                b.addTrackingArea(area)
            }
            class_addMethod(btnCustomClass, NSSelectorFromString("updateTrackingAreas"), imp_implementationWithBlock(utaBlock), "v@:")

            // mouseEntered -> mark hovered (triggers 'x' glyph)
            let meBlock: @convention(block) (NSButton, AnyObject) -> Void = { b, _ in
                NativeCloseWidgetHelper.setHovered(true, on: b)
                NSCursor.arrow.set()
            }
            class_addMethod(btnCustomClass, NSSelectorFromString("mouseEntered:"), imp_implementationWithBlock(meBlock), "v@:@")

            // mouseExited -> unmark hovered
            let mxBlock: @convention(block) (NSButton, AnyObject) -> Void = { b, _ in
                NativeCloseWidgetHelper.setHovered(false, on: b)
            }
            class_addMethod(btnCustomClass, NSSelectorFromString("mouseExited:"), imp_implementationWithBlock(mxBlock), "v@:@")

            // resetCursorRects -> add arrow cursor rect
            let rcrBlock: @convention(block) (NSButton) -> Void = { b in
                b.discardCursorRects()
                b.addCursorRect(b.bounds, cursor: .arrow)
            }
            class_addMethod(btnCustomClass, NSSelectorFromString("resetCursorRects"), imp_implementationWithBlock(rcrBlock), "v@:")

            objc_registerClassPair(btnCustomClass!)
        }
        object_setClass(button, btnCustomClass!)

        // 2. Subclass cell to provide macOS CoreTheme hover state (4 = rollover with 'x' icon) and scaleFactor proxy
        guard let cell = button.cell else { return }
        let cellSubclassName = "PocketHoverThemeCloseCell"
        var cellCustomClass: AnyClass? = objc_getClass(cellSubclassName) as? AnyClass
        if cellCustomClass == nil {
            cellCustomClass = objc_allocateClassPair(type(of: cell), cellSubclassName, 0)
            let block: @convention(block) (AnyObject) -> Int = { obj in
                let isPressed = (obj as? NSCell)?.isHighlighted ?? false
                if isPressed { return 2 }
                let isHovered = objc_getAssociatedObject(obj, &NativeCloseWidgetHelper.key) as? Bool ?? false
                return isHovered ? 4 : 0
            }
            let imp = imp_implementationWithBlock(block)
            class_addMethod(cellCustomClass, NSSelectorFromString("_bezelInteractionState"), imp, "q@:")

            // Provide real window scale factor to eliminate CoreUI 'scaleFactor == 0.000000' warnings
            let frameBlock: @convention(block) (AnyObject, AnyObject) -> AnyObject? = { _, view in
                guard let v = view as? NSView else { return nil }
                return NativeThemeFrameProxy(targetView: v)
            }
            class_addMethod(cellCustomClass, NSSelectorFromString("_containingThemeFrameFromView:"), imp_implementationWithBlock(frameBlock), "@@:@")

            objc_registerClassPair(cellCustomClass!)
        }
        object_setClass(cell, cellCustomClass!)
        button.updateTrackingAreas()
    }

    static func setHovered(_ hovered: Bool, on button: NSButton) {
        guard let cell = button.cell else { return }
        let current = objc_getAssociatedObject(cell, &NativeCloseWidgetHelper.key) as? Bool ?? false
        guard current != hovered else { return }
        objc_setAssociatedObject(cell, &NativeCloseWidgetHelper.key, hovered, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        button.needsDisplay = true
    }
}

struct NativeWindowCloseButton: NSViewRepresentable {
    let action: () -> Void
    var isHovered: Bool = false
    var disabled: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        guard let button = NSWindow.standardWindowButton(.closeButton, for: [.titled, .closable]) else {
            return NSButton()
        }
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked)
        button.isEnabled = !disabled
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        NativeCloseWidgetHelper.setup(button: button)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
        nsView.target = context.coordinator
        nsView.action = #selector(Coordinator.buttonClicked)
        nsView.isEnabled = !disabled
        NativeCloseWidgetHelper.setHovered(isHovered, on: nsView)
        nsView.updateTrackingAreas()
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonClicked() {
            action()
        }
    }
}

struct NoteEditorView: View {
    let noteID: UUID
    let model: AppModel
    let preferences: AppPreferences
    let bridge: EditorBridge
    var activeTabFrame: CGRect? = nil
    let onClose: () -> Void
    let onMicrophone: () -> Void
    let dictationState: DictationState
    var audioLevel: Float = 0.0

    @State private var draft = ""
    @State private var titleDraft = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var usesCustomTitle = false
    @State private var showsColorChooser = false
    @State private var showsFormatChooser = false
    @State private var isCloseHovered = false
    @State private var cardFrame: CGRect = .zero
    @FocusState private var titleFocused: Bool

    private var note: Note? { model.note(id: noteID) }
    private var palette: NotePaletteColor { note.map(NotePalette.color(for:)) ?? NotePalette.color(0) }
    private var editableTitle: String { note?.customTitle ?? note?.title ?? "" }

    private var arrowOffset: CGFloat {
        let cornerRadius: CGFloat = 14
        let arrowMargin: CGFloat = 20
        guard let tabFrame = activeTabFrame, cardFrame.width > 0, cardFrame.height > 0 else {
            return preferences.edge == .bottom ? preferences.noteSize.width / 2 : preferences.noteSize.height / 2
        }
        switch preferences.edge {
        case .bottom:
            let rawX = tabFrame.midX - cardFrame.minX
            return min(max(rawX, cornerRadius + arrowMargin), cardFrame.width - cornerRadius - arrowMargin)
        case .left, .right:
            let rawY = tabFrame.midY - cardFrame.minY
            return min(max(rawY, cornerRadius + arrowMargin), cardFrame.height - cornerRadius - arrowMargin)
        }
    }

    var body: some View {
        ZStack {
            NoteCardArrowShape(edge: preferences.edge, offset: arrowOffset)
                .fill(palette.paper)

            editorContent
                .background(palette.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(palette.ink)
        .shadow(
            color: .black.opacity(0.18),
            radius: 12,
            x: preferences.edge == .right ? -5 : (preferences.edge == .left ? 5 : 0),
            y: preferences.edge == .bottom ? -5 : 5
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardFrame = geo.frame(in: .named("DeckContainer")) }
                    .onChange(of: geo.frame(in: .named("DeckContainer"))) { _, newFrame in
                        cardFrame = newFrame
                    }
            }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: arrowOffset)
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
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                NativeWindowCloseButton(action: close, isHovered: isCloseHovered, disabled: false)
                    .frame(width: 14, height: 16)
                    .onHover { isCloseHovered = $0 }

                TextField("New note", text: $titleDraft)
                    .font(.headline)
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 80, maxWidth: .infinity, minHeight: 26)
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

                if dictationState != .idle {
                    WaveSoundBar(level: audioLevel, color: palette.accent)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.6).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                                removal: .scale(scale: 0.6).combined(with: .opacity).combined(with: .move(edge: .trailing))
                            )
                        )
                }

                Button(action: onMicrophone) {
                    ZStack(alignment: .center) {
                        if dictationState == .preparing {
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 22, height: 22)

                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.65)
                        } else if dictationState == .idle {
                            Image(systemName: "mic")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.ink.opacity(0.8))
                        } else {
                            // Listening / Finalizing: perfectly concentric geometric stop indicator
                            Circle()
                                .stroke(Color.red.opacity(0.32), lineWidth: 1.5)
                                .frame(width: 22, height: 22)

                            Circle()
                                .fill(Color.red)
                                .frame(width: 14, height: 14)

                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                    .frame(width: 24, height: 24, alignment: .center)
                }
                .buttonStyle(.plain)
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
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: dictationState != .idle)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.arrow.set()
                }
            }

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
            if focused {
                bridge.activeTextView?.hasUserPlacedCursor = false
            } else {
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
        if dictationState != .idle {
            onMicrophone()
        }
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
