import AppKit
import Observation

@MainActor
@Observable
final class EditorBridge {
    private(set) var isDictating = false
    private var anchorRange = NSRange(location: 0, length: 0)
    private var provisionalRange: NSRange?
    private var committedLength = 0
    weak var activeTextView: PocketTextView?

    func showFind() { currentTextView()?.performFindPanelAction(NSMenuItem()) }

    @discardableResult
    func performBlockCommand(_ command: EditorCommand) -> Bool {
        guard let textView = currentTextView() else { return false }
        switch command {
        case .formatTitle:
            textView.setTitle()
            return true
        case .formatHeading:
            textView.setHeading()
            return true
        case .formatSubheading:
            textView.setSubheading()
            return true
        case .formatBody:
            textView.setBody()
            return true
        case .formatBulletList:
            textView.toggleBulletList()
            return true
        case .formatDashList:
            textView.toggleDashedList()
            return true
        case .formatNumberList:
            textView.toggleNumberedList()
            return true
        case .formatCheckList:
            textView.toggleChecklist()
            return true
        case .formatBlockQuote:
            textView.toggleBlockQuote()
            return true
        case .formatBold:
            textView.toggleBold()
            return true
        case .formatItalic:
            textView.toggleItalic()
            return true
        case .formatUnderline:
            textView.toggleUnderline()
            return true
        case .formatStrikethrough:
            textView.toggleStrikethrough()
            return true
        case .formatMonospaced:
            textView.setMonostyled()
            return true
        case .toggleTask, .formatCheckList:
            textView.toggleChecklist()
            return true
        default:
            return false
        }
    }

    @discardableResult
    func insertImageBlock(_ source: String) -> Bool {
        if let tv = currentTextView() {
            tv.insertImageAttachment(filename: source, alt: "Image")
            return true
        }
        return false
    }

    func toggleTask() {
        currentTextView()?.toggleChecklist()
    }

    func insertText(_ text: String) {
        guard let textView = currentTextView() else { return }
        let selected = textView.selectedRange()
        if textView.shouldChangeText(in: selected, replacementString: text) {
            textView.textStorage?.replaceCharacters(in: selected, with: text)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selected.location + (text as NSString).length, length: 0))
        }
    }

    // MARK: - Voice Dictation

    func beginDictation() {
        guard let textView = currentTextView(), !isDictating else { return }
        isDictating = true
        anchorRange = textView.selectedRange()
        provisionalRange = nil
        committedLength = 0
        textView.isEditable = false
        textView.undoManager?.beginUndoGrouping()
        textView.undoManager?.setActionName("Voice Dictation")
    }

    func applyInterim(_ text: String) {
        guard let textView = currentTextView(), isDictating else { return }
        let range = provisionalRange ?? NSRange(location: anchorRange.location + committedLength, length: anchorRange.length)
        textView.textStorage?.replaceCharacters(in: range, with: text)
        provisionalRange = NSRange(location: range.location, length: (text as NSString).length)
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    func commitFinal(_ text: String) {
        guard let textView = currentTextView(), isDictating else { return }
        let range = provisionalRange ?? NSRange(location: anchorRange.location + committedLength, length: committedLength == 0 ? anchorRange.length : 0)
        let suffix = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
        let replacement = text + suffix
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        committedLength += (replacement as NSString).length
        provisionalRange = nil
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: anchorRange.location + committedLength, length: 0))
    }

    func finishDictation(discardInterim: Bool) {
        guard let textView = currentTextView(), isDictating else { return }
        if discardInterim, let provisionalRange {
            textView.textStorage?.replaceCharacters(in: provisionalRange, with: "")
        }
        provisionalRange = nil
        isDictating = false
        textView.isEditable = true
        textView.undoManager?.endUndoGrouping()
        textView.didChangeText()
    }

    private static weak var globalLastActiveTextView: PocketTextView?

    static func setLastActive(_ textView: PocketTextView) {
        globalLastActiveTextView = textView
    }

    private func currentTextView() -> PocketTextView? {
        if let activeTextView { return activeTextView }
        if let textView = NSApp.keyWindow?.firstResponder as? PocketTextView {
            Self.globalLastActiveTextView = textView
            return textView
        }
        if let last = Self.globalLastActiveTextView, last.window != nil {
            return last
        }
        return nil
    }
}
