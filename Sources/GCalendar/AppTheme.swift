import AppKit
import SwiftUI

enum AppTheme {
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(calibratedRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }

    static let canvas = adaptive(light: (247.0 / 255, 249.0 / 255, 252.0 / 255), dark: (0.067, 0.075, 0.094))
    static let surface = adaptive(light: (1.000, 1.000, 1.000), dark: (0.106, 0.114, 0.137))
    static let surfaceRaised = adaptive(light: (1.000, 1.000, 1.000), dark: (0.141, 0.153, 0.176))
    static let textPrimary = adaptive(light: (0.125, 0.129, 0.141), dark: (0.945, 0.941, 0.969))
    static let textSecondary = adaptive(light: (0.314, 0.345, 0.400), dark: (0.761, 0.773, 0.808))
    static let outline = adaptive(light: (0.455, 0.475, 0.537), dark: (0.573, 0.592, 0.639))
    static let accent = adaptive(light: (0.043, 0.341, 0.816), dark: (0.565, 0.792, 0.976))
    static let selection = adaptive(light: (0.827, 0.890, 0.992), dark: (0.149, 0.239, 0.365))
    static let event = accent
    static let task = adaptive(light: (0.086, 0.514, 0.420), dark: (0.447, 0.835, 0.710))
    static let overdue = adaptive(light: (0.773, 0.133, 0.122), dark: (1.000, 0.706, 0.671))
    static let success = adaptive(light: (0.094, 0.502, 0.220), dark: (0.565, 0.835, 0.635))
    static let warning = adaptive(light: (0.690, 0.376, 0.000), dark: (1.000, 0.804, 0.478))
    static let editorInset: CGFloat = 24
    static let sectionGap: CGFloat = 16
    static let fieldGap: CGFloat = 8
}
