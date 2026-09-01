import AppKit
import SwiftUI

struct NotePaletteColor: Sendable {
    let name: String
    let paper: Color
    let accent: Color
    let ink: Color
}

enum NotePalette {
    static let colors: [NotePaletteColor] = [
        .init(name: "Lemon", paper: Color(hex: 0xFCE795), accent: Color(hex: 0xE0AD08), ink: Color(hex: 0x3A3008)),
        .init(name: "Peach", paper: Color(hex: 0xFBCFA6), accent: Color(hex: 0xE2762A), ink: Color(hex: 0x422413)),
        .init(name: "Rose", paper: Color(hex: 0xFAC4D1), accent: Color(hex: 0xDC4570), ink: Color(hex: 0x40161F)),
        .init(name: "Lilac", paper: Color(hex: 0xD9C7FA), accent: Color(hex: 0x7C4DEE), ink: Color(hex: 0x2A1B44)),
        .init(name: "Sky", paper: Color(hex: 0xBEDDFA), accent: Color(hex: 0x2280D6), ink: Color(hex: 0x13293A)),
        .init(name: "Mint", paper: Color(hex: 0xB4E8D0), accent: Color(hex: 0x0E9B6E), ink: Color(hex: 0x0F2E23)),
        .init(name: "Sand", paper: Color(hex: 0xE3D3B4), accent: Color(hex: 0xA37B3C), ink: Color(hex: 0x372C18)),
        .init(name: "Slate", paper: Color(hex: 0xCBD6E2), accent: Color(hex: 0x4E6579), ink: Color(hex: 0x1A242E)),
    ]

    static func color(_ index: Int) -> NotePaletteColor {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    static func color(for note: Note) -> NotePaletteColor {
        guard let hex = note.customColorHex, let rgb = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else {
            return color(note.colorIndex)
        }
        let red = CGFloat((rgb >> 16) & 0xff) / 255
        let green = CGFloat((rgb >> 8) & 0xff) / 255
        let blue = CGFloat(rgb & 0xff) / 255
        let paper = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        let accent = paper.blended(withFraction: 0.28, of: .black) ?? paper
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        let ink = luminance > 0.58 ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        return .init(name: "Custom", paper: Color(nsColor: paper), accent: Color(nsColor: accent), ink: Color(nsColor: ink))
    }

    static func swiftUIColor(for note: Note) -> Color { color(for: note).paper }

    static func hex(_ color: Color) -> String? {
        guard let value = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let red = Int((value.redComponent * 255).rounded())
        let green = Int((value.greenComponent * 255).rounded())
        let blue = Int((value.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
