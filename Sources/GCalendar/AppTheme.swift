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

    static let canvas = adaptive(light: (0.969, 0.973, 0.980), dark: (0.067, 0.075, 0.094))
    static let surface = adaptive(light: (1.000, 1.000, 1.000), dark: (0.106, 0.114, 0.137))
    static let surfaceRaised = adaptive(light: (1.000, 1.000, 1.000), dark: (0.141, 0.153, 0.176))
    static let textPrimary = adaptive(light: (0.098, 0.106, 0.125), dark: (0.945, 0.941, 0.969))
    static let textSecondary = adaptive(light: (0.333, 0.353, 0.392), dark: (0.761, 0.773, 0.808))
    static let outline = adaptive(light: (0.455, 0.475, 0.537), dark: (0.573, 0.592, 0.639))
    static let accent = adaptive(light: (0.208, 0.408, 0.831), dark: (0.663, 0.773, 1.000))
    static let event = accent
    static let task = adaptive(light: (0.086, 0.514, 0.420), dark: (0.447, 0.835, 0.710))
    static let overdue = adaptive(light: (0.702, 0.149, 0.118), dark: (1.000, 0.706, 0.671))
    static let success = adaptive(light: (0.145, 0.459, 0.302), dark: (0.565, 0.835, 0.635))
    static let warning = adaptive(light: (0.584, 0.353, 0.000), dark: (1.000, 0.804, 0.478))
}
