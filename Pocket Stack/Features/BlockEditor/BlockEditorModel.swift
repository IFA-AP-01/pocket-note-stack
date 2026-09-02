import AppKit
import Observation

@MainActor
@Observable
final class BlockEditorModel {
    @ObservationIgnored private(set) var document: EditorDocument
    private(set) var renderRevision: UInt64 = 0
    private(set) var selectedSurface: EditorSurfaceID?

    @ObservationIgnored let focusRegistry = FocusRegistry()
    @ObservationIgnored private let codec = MarkdownBlockCodec()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var onMarkdownChange: (String) -> Void
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var focusGeneration: UInt64 = 0
    @ObservationIgnored private var synchronizedMarkdown: String

    init(markdown: String, onMarkdownChange: @escaping (String) -> Void) {
        document = codec.parse(markdown)
        synchronizedMarkdown = markdown
        self.onMarkdownChange = onMarkdownChange
        focusRegistry.orderedSurfacesProvider = { [weak self] in self?.orderedSurfaces() ?? [] }
    }

    var renderedBlocks: [NoteBlock] {
        _ = renderRevision
        return document.blocks
    }

    func activate() { isActive = true }

    func deactivate() {
        isActive = false
        focusGeneration &+= 1
        saveTask?.cancel()
        focusRegistry.resignAll()
    }

    func flush() {
        saveTask?.cancel()
        let markdown = codec.serialize(document)
        synchronizedMarkdown = markdown
        onMarkdownChange(markdown)
    }

    func update(_ content: RichText, at surface: EditorSurfaceID) {
        mutate(invalidateView: false) { document in Self.set(content, at: surface, in: &document) }
    }

    func updateCode(blockID: UUID, code: String) {
        mutate { document in
            guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
                  case .code(var block) = document.blocks[index].kind else { return }
            block.code = code
            document.blocks[index].kind = .code(block)
        }
    }

    func updateMath(blockID: UUID, latex: String) {
        mutate { document in
            guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return }
            document.blocks[index].kind = .displayMath(DisplayMathBlock(latex: latex))
        }
    }

    func toggleTask(blockID: UUID) {
        mutate { document in
            guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
                  case .task(var task) = document.blocks[index].kind else { return }
            task.isCompleted.toggle()
            document.blocks[index].kind = .task(task)
        }
    }

    func split(_ surface: EditorSurfaceID, at offset: Int) {
        switch surface {
        case .block(let id): splitBlock(id, at: offset)
        case .listItem(let blockID, let itemID): splitListItem(blockID: blockID, itemID: itemID, at: offset)
        case .tableCell: move(from: surface, direction: .next, screenX: nil)
        }
    }

    func mergeBackward(_ surface: EditorSurfaceID) -> Bool {
        switch surface {
        case .block(let id): return mergeBlockBackward(id)
        case .listItem(let blockID, let itemID): return mergeListItemBackward(blockID: blockID, itemID: itemID)
        case .tableCell: move(from: surface, direction: .previous, screenX: nil); return true
        }
    }

    func move(from surface: EditorSurfaceID, direction: FocusDirection, screenX: CGFloat?) {
        let order = orderedSurfaces()
        guard let current = order.firstIndex(of: surface) else { return }
        let step = (direction == .previous || direction == .up) ? -1 : 1
        var nextIndex: Int
        if case .tableCell(let blockID, let rowID, let columnID) = surface,
           direction == .up || direction == .down,
           let block = document.blocks.first(where: { $0.id == blockID }),
           case .table(let table) = block.kind,
           let column = table.columns.firstIndex(where: { $0.id == columnID }) {
            let rows = [table.header] + table.rows
            let row = rows.firstIndex(where: { $0.id == rowID }) ?? 0
            let targetRow = row + step
            if rows.indices.contains(targetRow) {
                let target = EditorSurfaceID.tableCell(blockID: blockID, rowID: rows[targetRow].id, columnID: table.columns[column].id)
                selectedSurface = target
                requestFocus(target, anchor: screenX.map { .horizontal($0, fromBottom: step < 0) } ?? (step < 0 ? .end : .start))
                return
            }
            let edge = step < 0 ? order.firstIndex(where: { $0.blockID == blockID })! : order.lastIndex(where: { $0.blockID == blockID })!
            nextIndex = edge + step
        } else {
            nextIndex = current + step
        }
        while order.indices.contains(nextIndex), !focusRegistry.isRegistered(order[nextIndex]) { nextIndex += step }
        guard order.indices.contains(nextIndex) else { return }
        let target = order[nextIndex]
        self.selectedSurface = target
        let backwards = direction == .previous || direction == .up
        let anchor: CaretAnchor = screenX.map { .horizontal($0, fromBottom: backwards) } ?? (backwards ? .end : .start)
        requestFocus(target, anchor: anchor)
    }

    func insert(_ kind: BlockKind, after surface: EditorSurfaceID?) {
        let block = NoteBlock(kind: kind)
        mutate { document in
            let index = surface.flatMap { value in document.blocks.firstIndex(where: { $0.id == value.blockID }) }
            document.blocks.insert(block, at: min((index ?? document.blocks.count - 1) + 1, document.blocks.count))
        }
        let target: EditorSurfaceID
        if case .table(let table) = kind, let column = table.columns.first, let cell = table.header.cells.first {
            target = .tableCell(blockID: block.id, rowID: table.header.id, columnID: column.id)
            _ = cell
        } else {
            target = .block(block.id)
        }
        selectedSurface = target
        requestFocus(target, anchor: .start)
    }

    func addTableRow(blockID: UUID) {
        mutate { document in
            guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
                  case .table(var table) = document.blocks[index].kind else { return }
            table.rows.append(TableRow(cells: table.columns.map { _ in TableCell(content: RichText(string: "")) }))
            document.blocks[index].kind = .table(table)
        }
    }

    func addTableColumn(blockID: UUID) {
        mutate { document in
            guard let index = document.blocks.firstIndex(where: { $0.id == blockID }),
                  case .table(var table) = document.blocks[index].kind else { return }
            table.columns.append(TableColumn())
            table.normalize()
            document.blocks[index].kind = .table(table)
        }
    }

    func transformActiveBlock(_ transform: (RichText) -> BlockKind) {
        guard let selectedSurface,
              case .block(let id) = selectedSurface,
              let index = document.blocks.firstIndex(where: { $0.id == id }),
              let content = Self.content(of: document.blocks[index].kind) else { return }
        mutate { $0.blocks[index].kind = transform(content) }
    }

    func transformActiveBlock(to style: ListStyle) {
        guard let selectedSurface,
              case .block(let id) = selectedSurface,
              let index = document.blocks.firstIndex(where: { $0.id == id }),
              let content = Self.content(of: document.blocks[index].kind) else { return }
        let item = ListBlockItem(content: content)
        mutate { $0.blocks[index].kind = .list(ListBlock(style: style, items: [item])) }
        let target = EditorSurfaceID.listItem(blockID: id, itemID: item.id)
        self.selectedSurface = target
        requestFocus(target, anchor: .end)
    }

    func transformActiveBlockToTask() {
        transformActiveBlock { .task(TaskBlock(isCompleted: false, content: $0)) }
    }

    func reloadIfChanged(markdown: String) {
        guard synchronizedMarkdown != markdown else { return }
        saveTask?.cancel()
        document = codec.parse(markdown)
        synchronizedMarkdown = markdown
        renderRevision &+= 1
    }

    func setSelected(_ surface: EditorSurfaceID) { selectedSurface = surface }

    private func splitBlock(_ id: UUID, at offset: Int) {
        guard let index = document.blocks.firstIndex(where: { $0.id == id }),
              let content = Self.content(of: document.blocks[index].kind) else { return }
        let (left, right) = content.split(at: offset)
        let newBlock = NoteBlock(kind: .paragraph(right))
        mutate { document in
            document.blocks[index].kind = Self.replacingContent(in: document.blocks[index].kind, with: left)
            document.blocks.insert(newBlock, at: index + 1)
        }
        selectedSurface = .block(newBlock.id)
        requestFocus(.block(newBlock.id), anchor: .start)
    }

    private func splitListItem(blockID: UUID, itemID: UUID, at offset: Int) {
        guard let blockIndex = document.blocks.firstIndex(where: { $0.id == blockID }),
              case .list(let current) = document.blocks[blockIndex].kind,
              let itemIndex = current.items.firstIndex(where: { $0.id == itemID }) else { return }
        let (left, right) = current.items[itemIndex].content.split(at: offset)
        let newItem = ListBlockItem(content: right)
        mutate { document in
            guard case .list(var list) = document.blocks[blockIndex].kind else { return }
            list.items[itemIndex].content = left
            list.items.insert(newItem, at: itemIndex + 1)
            document.blocks[blockIndex].kind = .list(list)
        }
        let target = EditorSurfaceID.listItem(blockID: blockID, itemID: newItem.id)
        selectedSurface = target
        requestFocus(target, anchor: .start)
    }

    private func mergeBlockBackward(_ id: UUID) -> Bool {
        guard let index = document.blocks.firstIndex(where: { $0.id == id }), index > 0,
              let current = Self.content(of: document.blocks[index].kind),
              let previous = Self.content(of: document.blocks[index - 1].kind) else { return false }
        let destination = document.blocks[index - 1].id
        let caret = previous.utf16Length
        mutate { document in
            document.blocks[index - 1].kind = Self.replacingContent(in: document.blocks[index - 1].kind, with: previous.appending(current))
            document.blocks.remove(at: index)
        }
        selectedSurface = .block(destination)
        requestFocus(.block(destination), anchor: .index(caret))
        return true
    }

    private func mergeListItemBackward(blockID: UUID, itemID: UUID) -> Bool {
        guard let blockIndex = document.blocks.firstIndex(where: { $0.id == blockID }),
              case .list(let list) = document.blocks[blockIndex].kind,
              let itemIndex = list.items.firstIndex(where: { $0.id == itemID }) else { return false }
        if itemIndex == 0 {
            let content = list.items[0].content
            if list.items.count == 1 {
                mutate { $0.blocks[blockIndex].kind = .paragraph(content) }
                let target = EditorSurfaceID.block(blockID)
                selectedSurface = target
                requestFocus(target, anchor: .start)
            } else {
                let paragraph = NoteBlock(kind: .paragraph(content))
                mutate { document in
                    guard case .list(var value) = document.blocks[blockIndex].kind else { return }
                    value.items.removeFirst()
                    document.blocks[blockIndex].kind = .list(value)
                    document.blocks.insert(paragraph, at: blockIndex)
                }
                let target = EditorSurfaceID.block(paragraph.id)
                selectedSurface = target
                requestFocus(target, anchor: .end)
            }
            return true
        }
        let target = list.items[itemIndex - 1].id
        let caret = list.items[itemIndex - 1].content.utf16Length
        mutate { document in
            guard case .list(var value) = document.blocks[blockIndex].kind else { return }
            value.items[itemIndex - 1].content = value.items[itemIndex - 1].content.appending(value.items[itemIndex].content)
            value.items.remove(at: itemIndex)
            document.blocks[blockIndex].kind = .list(value)
        }
        let surface = EditorSurfaceID.listItem(blockID: blockID, itemID: target)
        selectedSurface = surface
        requestFocus(surface, anchor: .index(caret))
        return true
    }

    private func orderedSurfaces() -> [EditorSurfaceID] {
        document.blocks.flatMap { block -> [EditorSurfaceID] in
            switch block.kind {
            case .list(let list): return list.items.map { .listItem(blockID: block.id, itemID: $0.id) }
            case .table(let table):
                return ([table.header] + table.rows).flatMap { row in
                    zip(table.columns, row.cells).map { .tableCell(blockID: block.id, rowID: row.id, columnID: $0.0.id) }
                }
            default: return [.block(block.id)]
            }
        }
    }

    func beginDocumentSelection(at surface: EditorSurfaceID, characterIndex: Int) {
        focusRegistry.beginSelection(at: surface, characterIndex: characterIndex)
    }

    func extendDocumentSelection(to screenPoint: NSPoint) {
        focusRegistry.extendSelection(to: screenPoint, orderedSurfaces: orderedSurfaces())
    }

    func finishDocumentSelection() { focusRegistry.finishSelection() }

    func copyDocumentSelection() -> Bool {
        focusRegistry.copySelection(orderedSurfaces: orderedSurfaces())
    }

    func selectAllDocument() {
        focusRegistry.selectAll(orderedSurfaces: orderedSurfaces())
    }

    private func requestFocus(_ target: EditorSurfaceID, anchor: CaretAnchor) {
        focusGeneration &+= 1
        let generation = focusGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.focusGeneration == generation else { return }
            self.focusRegistry.focus(target, anchor: anchor)
        }
    }

    private func mutate(invalidateView: Bool = true, _ body: (inout EditorDocument) -> Void) {
        body(&document)
        document.revision &+= 1
        if invalidateView { renderRevision &+= 1 }
        scheduleSave(revision: document.revision)
    }

    private func scheduleSave(revision: UInt64) {
        saveTask?.cancel()
        let snapshot = document
        saveTask = Task { [codec, onMarkdownChange] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, revision == self.document.revision else { return }
            let markdown = codec.serialize(snapshot)
            self.synchronizedMarkdown = markdown
            onMarkdownChange(markdown)
        }
    }

    private static func content(of kind: BlockKind) -> RichText? {
        switch kind {
        case .paragraph(let value), .quote(let value): value
        case .heading(_, let value): value
        case .task(let value): value.content
        case .code(let value): RichText(string: value.code)
        default: nil
        }
    }

    private static func replacingContent(in kind: BlockKind, with content: RichText) -> BlockKind {
        switch kind {
        case .heading(let level, _): .heading(level: level, content: content)
        case .quote: .quote(content)
        case .task(let value): .task(TaskBlock(isCompleted: value.isCompleted, content: content))
        case .code(let value): .code(CodeBlock(language: value.language, code: content.string))
        default: .paragraph(content)
        }
    }

    private static func set(_ content: RichText, at surface: EditorSurfaceID, in document: inout EditorDocument) {
        guard let blockIndex = document.blocks.firstIndex(where: { $0.id == surface.blockID }) else { return }
        switch surface {
        case .block:
            document.blocks[blockIndex].kind = replacingContent(in: document.blocks[blockIndex].kind, with: content)
        case .listItem(_, let itemID):
            guard case .list(var list) = document.blocks[blockIndex].kind,
                  let itemIndex = list.items.firstIndex(where: { $0.id == itemID }) else { return }
            list.items[itemIndex].content = content
            document.blocks[blockIndex].kind = .list(list)
        case .tableCell(_, let rowID, let columnID):
            guard case .table(var table) = document.blocks[blockIndex].kind,
                  let columnIndex = table.columns.firstIndex(where: { $0.id == columnID }) else { return }
            if table.header.id == rowID { table.header.cells[columnIndex].content = content }
            else if let rowIndex = table.rows.firstIndex(where: { $0.id == rowID }) { table.rows[rowIndex].cells[columnIndex].content = content }
            document.blocks[blockIndex].kind = .table(table)
        }
    }
}

@MainActor
final class FocusRegistry {
    private final class WeakView { weak var value: WYSIWYGTextView?; init(_ value: WYSIWYGTextView) { self.value = value } }
    private var views: [EditorSurfaceID: WeakView] = [:]
    private var dragAnchor: (surface: EditorSurfaceID, index: Int)?
    private var hasCrossSurfaceSelection = false
    private var mouseMonitor: Any?
    var orderedSurfacesProvider: (() -> [EditorSurfaceID])?

    func register(_ view: WYSIWYGTextView, for id: EditorSurfaceID) {
        views[id] = WeakView(view)
        installMouseMonitorIfNeeded()
    }
    func unregister(_ id: EditorSurfaceID, view: WYSIWYGTextView) {
        guard views[id]?.value === view else { return }
        views[id] = nil
        removeMouseMonitorIfUnused()
    }
    func isRegistered(_ id: EditorSurfaceID) -> Bool { views[id]?.value != nil }

    func focus(_ id: EditorSurfaceID, anchor: CaretAnchor) {
        guard let view = views[id]?.value else { return }
        clearSelections(except: id)
        view.window?.makeFirstResponder(view)
        let length = (view.string as NSString).length
        let index: Int
        switch anchor {
        case .start: index = 0
        case .end: index = length
        case .index(let value): index = value
        case .horizontal(let screenX, let fromBottom): index = view.characterIndex(screenX: screenX, fromBottom: fromBottom)
        }
        view.setSelectedRange(NSRange(location: min(max(index, 0), length), length: 0))
    }

    func beginSelection(at surface: EditorSurfaceID, characterIndex: Int) {
        clearSelections(except: surface)
        dragAnchor = (surface, characterIndex)
        hasCrossSurfaceSelection = false
    }

    func extendSelection(to screenPoint: NSPoint, orderedSurfaces: [EditorSurfaceID]) {
        guard let anchor = dragAnchor,
              let anchorPosition = orderedSurfaces.firstIndex(of: anchor.surface),
              let destination = destination(at: screenPoint),
              let destinationPosition = orderedSurfaces.firstIndex(of: destination.surface) else { return }

        if anchor.surface == destination.surface {
            hasCrossSurfaceSelection = false
            clearSelectionRanges(except: anchor.surface)
            return
        }

        hasCrossSurfaceSelection = true
        let lower = min(anchorPosition, destinationPosition)
        let upper = max(anchorPosition, destinationPosition)
        for (position, surface) in orderedSurfaces.enumerated() {
            guard let view = views[surface]?.value else { continue }
            let length = (view.string as NSString).length
            let selection: NSRange
            if position < lower || position > upper {
                selection = NSRange(location: 0, length: 0)
            } else if surface == anchor.surface {
                selection = anchorPosition < destinationPosition
                    ? NSRange(location: min(anchor.index, length), length: max(length - anchor.index, 0))
                    : NSRange(location: 0, length: min(anchor.index, length))
            } else if surface == destination.surface {
                selection = anchorPosition < destinationPosition
                    ? NSRange(location: 0, length: min(destination.index, length))
                    : NSRange(location: min(destination.index, length), length: max(length - destination.index, 0))
            } else {
                selection = NSRange(location: 0, length: length)
            }
            view.setSelectedRange(selection)
        }
    }

    func finishSelection() { dragAnchor = nil }

    func copySelection(orderedSurfaces: [EditorSurfaceID]) -> Bool {
        guard hasCrossSurfaceSelection else { return false }
        let fragments = orderedSurfaces.compactMap { surface -> String? in
            guard let view = views[surface]?.value else { return nil }
            let selected = view.selectedRange()
            guard selected.length > 0 else { return nil }
            return (view.string as NSString).substring(with: selected)
        }
        guard !fragments.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fragments.joined(separator: "\n\n"), forType: .string)
        return true
    }

    func selectAll(orderedSurfaces: [EditorSurfaceID]) {
        hasCrossSurfaceSelection = orderedSurfaces.count > 1
        for surface in orderedSurfaces {
            guard let view = views[surface]?.value else { continue }
            view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        }
    }

    func clearSelections(except retained: EditorSurfaceID? = nil) {
        hasCrossSurfaceSelection = false
        dragAnchor = nil
        clearSelectionRanges(except: retained)
    }

    private func clearSelectionRanges(except retained: EditorSurfaceID? = nil) {
        for (surface, reference) in views where surface != retained {
            reference.value?.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    func resignAll() {
        for reference in views.values {
            guard let view = reference.value else { continue }
            if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
            view.setSelectedRange(NSRange(location: 0, length: 0))
        }
        views.removeAll()
        removeMouseMonitor()
        hasCrossSurfaceSelection = false
        dragAnchor = nil
    }

    private func destination(at screenPoint: NSPoint) -> (surface: EditorSurfaceID, index: Int)? {
        let candidates = views.compactMap { surface, reference -> (EditorSurfaceID, WYSIWYGTextView, NSRect)? in
            guard let view = reference.value, let window = view.window else { return nil }
            let windowRect = view.convert(view.bounds, to: nil)
            return (surface, view, window.convertToScreen(windowRect))
        }
        guard let candidate = candidates.min(by: {
            distance(from: screenPoint, to: $0.2) < distance(from: screenPoint, to: $1.2)
        }) else { return nil }
        let windowPoint = candidate.1.window?.convertPoint(fromScreen: screenPoint) ?? .zero
        let localPoint = candidate.1.convert(windowPoint, from: nil)
        return (candidate.0, candidate.1.characterIndexForInsertion(at: localPoint))
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func range(from first: Int, to second: Int) -> NSRange {
        NSRange(location: min(first, second), length: abs(second - first))
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            let hitView = event.window?.contentView?.hitTest(event.locationInWindow)
            let clickedInsideEditor = self.views.values.contains { reference in
                guard let editorView = reference.value, let hitView else { return false }
                return hitView === editorView || hitView.isDescendant(of: editorView)
            }
            if !clickedInsideEditor { self.clearSelections() }
            return event
        }
    }

    private func removeMouseMonitorIfUnused() {
        views = views.filter { $0.value.value != nil }
        if views.isEmpty { removeMouseMonitor() }
    }

    private func removeMouseMonitor() {
        guard let mouseMonitor else { return }
        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }

}
