import AppKit
import MarkdownEngine
import Observation

@MainActor
@Observable
final class EditorBridge {
    private(set) var isDictating = false
    private var anchorRange = NSRange(location: 0, length: 0)
    private var provisionalRange: NSRange?
    private var committedLength = 0

    func showFind() { activeTextView()?.performFindPanelAction(NSMenuItem()) }

    @discardableResult
    func performBlockCommand(_ command: EditorCommand) -> Bool {
        guard let textView = activeTextView() as? WYSIWYGTextView else { return false }
        return textView.commandHandler?(command, textView) == true
    }

    @discardableResult
    func insertImageBlock(_ source: String) -> Bool {
        guard let textView = activeTextView() as? WYSIWYGTextView else { return false }
        textView.imageHandler?(source)
        return true
    }

    func toggleTask() {
        guard let textView = activeTextView() else { return }
        let source = textView.string as NSString
        let selected = textView.selectedRange()
        let lineRange = source.lineRange(for: NSRange(location: min(selected.location, source.length), length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let replacement = NoteTask.toMarkdown(NoteTask.toggle(line: NoteTask.fromMarkdown(line)))
            + (source.substring(with: lineRange).hasSuffix("\n") ? "\n" : "")
        if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: lineRange, with: replacement)
            textView.didChangeText()
        }
    }
    
    func applyWrap(prefix: String, suffix: String) {
        guard let textView = activeTextView() else { return }
        let selected = textView.selectedRange()
        let text = (textView.string as NSString).substring(with: selected)
        let replacement = prefix + text + suffix
        if textView.shouldChangeText(in: selected, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: selected, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selected.location + prefix.count, length: selected.length))
        }
    }
    
    func togglePrefix(_ prefix: String) {
        guard let textView = activeTextView() else { return }
        let source = textView.string as NSString
        let selected = textView.selectedRange()
        let lineRange = source.lineRange(for: NSRange(location: min(selected.location, source.length), length: 0))
        var line = source.substring(with: lineRange)
        let hasNewline = line.hasSuffix("\n")
        if hasNewline { line.removeLast() }
        
        // Remove existing standard prefixes before applying new one
        let existingPrefixes = ["### ", "## ", "# ", "- [ ] ", "- [x] ", "- [X] ", "* ", "- ", "1. ", "☐ ", "☑ "]
        for ep in existingPrefixes {
            if line.hasPrefix(ep) {
                line.removeFirst(ep.count)
                break
            }
        }
        
        let replacement = (prefix.isEmpty ? line : prefix + line) + (hasNewline ? "\n" : "")
        if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: lineRange, with: replacement)
            textView.didChangeText()
        }
    }
    
    func insertText(_ text: String) {
        guard let textView = activeTextView() else { return }
        let selected = textView.selectedRange()
        if textView.shouldChangeText(in: selected, replacementString: text) {
            textView.textStorage?.replaceCharacters(in: selected, with: text)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selected.location + (text as NSString).length, length: 0))
        }
    }

    func beginDictation() {
        guard let textView = activeTextView(), !isDictating else { return }
        isDictating = true
        anchorRange = textView.selectedRange()
        provisionalRange = nil
        committedLength = 0
        textView.isEditable = false
        textView.undoManager?.beginUndoGrouping()
        textView.undoManager?.setActionName("Voice Dictation")
    }

    func applyInterim(_ text: String) {
        guard let textView = activeTextView(), isDictating else { return }
        let range = provisionalRange ?? NSRange(location: anchorRange.location + committedLength, length: anchorRange.length)
        textView.textStorage?.replaceCharacters(in: range, with: text)
        provisionalRange = NSRange(location: range.location, length: (text as NSString).length)
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    func commitFinal(_ text: String) {
        guard let textView = activeTextView(), isDictating else { return }
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
        guard let textView = activeTextView(), isDictating else { return }
        if discardInterim, let provisionalRange {
            textView.textStorage?.replaceCharacters(in: provisionalRange, with: "")
        }
        provisionalRange = nil
        isDictating = false
        textView.isEditable = true
        textView.undoManager?.endUndoGrouping()
        textView.didChangeText()
    }

    private static weak var globalLastActiveTextView: NSTextView?

    static func setLastActive(_ textView: NSTextView) {
        globalLastActiveTextView = textView
    }

    private func activeTextView() -> NSTextView? {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.delegate is NativeTextViewCoordinator || textView is WYSIWYGTextView {
            Self.globalLastActiveTextView = textView
            return textView
        }
        if let last = Self.globalLastActiveTextView, last.window != nil {
            return last
        }
        return nil
    }
}
