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
        case .toggleTask:
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
        textView.undoManager?.beginUndoGrouping()
        textView.undoManager?.setActionName("Voice Dictation")

        if !textView.hasUserPlacedCursor {
            let totalLength = (textView.string as NSString).length
            if totalLength > 0 {
                if !textView.string.hasSuffix("\n") {
                    textView.textStorage?.replaceCharacters(in: NSRange(location: totalLength, length: 0), with: "\n")
                    textView.didChangeText()
                    anchorRange = NSRange(location: totalLength + 1, length: 0)
                } else {
                    anchorRange = NSRange(location: totalLength, length: 0)
                }
            } else {
                anchorRange = NSRange(location: 0, length: 0)
            }
            textView.setSelectedRange(anchorRange)
            textView.scrollRangeToVisible(anchorRange)
            textView.hasUserPlacedCursor = true
        } else {
            anchorRange = textView.selectedRange()
        }

        provisionalRange = nil
        committedLength = 0
        textView.isEditable = false
        textView.showDictationCaret(at: anchorRange.location)
        textView.window?.invalidateCursorRects(for: textView)
        NSCursor.operationNotAllowed.set()
    }

    func applyInterim(_ text: String) {
        guard let textView = currentTextView(), isDictating else { return }
        let range = provisionalRange ?? NSRange(location: anchorRange.location + committedLength, length: committedLength == 0 ? anchorRange.length : 0)
        textView.textStorage?.replaceCharacters(in: range, with: text)
        let newLen = (text as NSString).length
        provisionalRange = NSRange(location: range.location, length: newLen)
        let targetLocation = range.location + newLen
        textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
        textView.showDictationCaret(at: targetLocation)
        textView.scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
    }

    func promoteInterim() {
        guard let textView = currentTextView(), isDictating, let provisionalRange else { return }

        var separatorLength = 0
        if provisionalRange.length > 0,
           let storage = textView.textStorage {
            let lastCharacterRange = NSRange(location: NSMaxRange(provisionalRange) - 1, length: 1)
            let lastCharacter = (storage.string as NSString).substring(with: lastCharacterRange)
            if lastCharacter.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                storage.replaceCharacters(in: NSRange(location: NSMaxRange(provisionalRange), length: 0), with: " ")
                separatorLength = 1
            }
        }

        committedLength += provisionalRange.length + separatorLength
        self.provisionalRange = nil
        textView.didChangeText()
        let targetLocation = anchorRange.location + committedLength
        textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
        textView.showDictationCaret(at: targetLocation)
        textView.scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
    }

    func commitFinal(_ text: String) {
        guard let textView = currentTextView(), isDictating,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let range = provisionalRange ?? NSRange(location: anchorRange.location + committedLength, length: committedLength == 0 ? anchorRange.length : 0)
        let suffix = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
        let replacement = text + suffix
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        committedLength += (replacement as NSString).length
        provisionalRange = nil
        textView.didChangeText()
        let targetLocation = anchorRange.location + committedLength
        textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
        textView.showDictationCaret(at: targetLocation)
        textView.scrollRangeToVisible(NSRange(location: targetLocation, length: 0))
    }

    func insertDictationNewline() {
        guard let textView = currentTextView(), isDictating else { return }

        // Never insert a newline while there is pending unfinalized interim text
        guard provisionalRange == nil else { return }

        guard committedLength > 0 else { return }

        let insertPos = anchorRange.location + committedLength
        guard let storage = textView.textStorage, insertPos <= storage.length else { return }

        // Avoid duplicate newline if already ending in \n
        if insertPos > 0 {
            let lastCharRange = NSRange(location: insertPos - 1, length: 1)
            let lastChar = (storage.string as NSString).substring(with: lastCharRange)
            if lastChar == "\n" {
                return
            } else if lastChar == " " {
                storage.replaceCharacters(in: lastCharRange, with: "\n")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: insertPos, length: 0))
                textView.showDictationCaret(at: insertPos)
                textView.scrollRangeToVisible(NSRange(location: insertPos, length: 0))
                return
            }
        }

        storage.replaceCharacters(in: NSRange(location: insertPos, length: 0), with: "\n")
        committedLength += 1
        textView.didChangeText()
        let newPos = anchorRange.location + committedLength
        textView.setSelectedRange(NSRange(location: newPos, length: 0))
        textView.showDictationCaret(at: newPos)
        textView.scrollRangeToVisible(NSRange(location: newPos, length: 0))
    }

    func finishDictation(discardInterim: Bool) {
        guard let textView = currentTextView(), isDictating else { return }
        if discardInterim, let provisionalRange {
            textView.textStorage?.replaceCharacters(in: provisionalRange, with: "")
        }
        provisionalRange = nil
        isDictating = false
        textView.isEditable = true
        textView.hasUserPlacedCursor = true
        textView.hideDictationCaret()
        textView.window?.invalidateCursorRects(for: textView)
        NSCursor.iBeam.set()
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
