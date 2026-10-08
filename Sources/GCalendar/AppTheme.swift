import AppKit
import SwiftUI

enum AppTheme {
    private static func adaptive(_ role: ThemePalette.Role) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = ThemePalette.color(role, dark: isDark)
            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }

    static let canvas = adaptive(.canvas)
    static let surface = adaptive(.surface)
    static let surfaceRaised = adaptive(.surfaceRaised)
    static let textPrimary = adaptive(.textPrimary)
    static let textSecondary = adaptive(.textSecondary)
    static let outline = adaptive(.outline)
    static let accent = adaptive(.accent)
    static let selection = adaptive(.selection)
    static let event = accent
    static let task = adaptive(.task)
    static let overdue = adaptive(.overdue)
    static let success = adaptive(.success)
    static let warning = adaptive(.warning)
    static let editorInset: CGFloat = 24
    static let sectionGap: CGFloat = 16
    static let fieldGap: CGFloat = 8
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let number = UInt64(value, radix: 16) else { return nil }
        let red, green, blue: Double
        if value.count == 6 {
            red = Double((number >> 16) & 0xff) / 255
            green = Double((number >> 8) & 0xff) / 255
            blue = Double(number & 0xff) / 255
        } else { return nil }
        self.init(red: red, green: green, blue: blue)
    }
}
