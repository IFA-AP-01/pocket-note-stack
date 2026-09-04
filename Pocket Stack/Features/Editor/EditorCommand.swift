import Foundation

enum EditorCommand: Equatable {
    case formatBody
    case formatTitle
    case formatHeading
    case formatSubheading
    case formatBold
    case formatItalic
    case formatUnderline
    case formatStrikethrough
    case formatMonospaced
    case formatBulletList
    case formatDashList
    case formatNumberList
    case formatCheckList
    case formatBlockQuote
    case insertLink
    case insertCodeBlock
    case insertInlineMath
    case insertDisplayMath
    case insertTable
    case insertImage
    case toggleTask
    case cycleColor
    case delete
    case archive
    case increaseFont
    case decreaseFont
    case escape
    case togglePin
}
