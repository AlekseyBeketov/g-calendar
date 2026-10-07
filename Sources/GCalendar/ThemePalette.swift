import Foundation

/// The rendering adapter and contrast fixtures share the same sRGB values.
enum ThemePalette {
    enum Role: CaseIterable {
        case canvas, surface, surfaceRaised, textPrimary, textSecondary, outline
        case accent, selection, task, overdue, success, warning
    }

    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        init(hex: UInt32) {
            red = Double((hex >> 16) & 255) / 255
            green = Double((hex >> 8) & 255) / 255
            blue = Double(hex & 255) / 255
        }

        private init(red: Double, green: Double, blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }

        var relativeLuminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        func contrast(against other: RGB) -> Double {
            let first = relativeLuminance, second = other.relativeLuminance
            return (max(first, second) + 0.05) / (min(first, second) + 0.05)
        }

        func blended(over background: RGB, opacity: Double) -> RGB {
            precondition((0...1).contains(opacity))
            return RGB(red: red * opacity + background.red * (1 - opacity),
                       green: green * opacity + background.green * (1 - opacity),
                       blue: blue * opacity + background.blue * (1 - opacity))
        }
    }

    static func color(_ role: Role, dark: Bool) -> RGB {
        let hex: UInt32
        switch role {
        case .canvas: hex = dark ? 0x111318 : 0xF7F9FC
        case .surface: hex = dark ? 0x1B1D23 : 0xFFFFFF
        case .surfaceRaised: hex = dark ? 0x242730 : 0xFFFFFF
        case .textPrimary: hex = dark ? 0xF1F0F7 : 0x202124
        case .textSecondary: hex = dark ? 0xC2C5CE : 0x505866
        case .outline: hex = dark ? 0x9297A3 : 0x747989
        case .accent: hex = dark ? 0x90CAF9 : 0x0B57D0
        case .selection: hex = dark ? 0x263D5D : 0xD3E3FD
        case .task: hex = dark ? 0x72D5B5 : 0x0F6E58
        case .overdue: hex = dark ? 0xFFB4AB : 0xB21C19
        case .success: hex = dark ? 0x90D5A2 : 0x137333
        case .warning: hex = dark ? 0xFFCD7A : 0x8A4B00
        }
        return RGB(hex: hex)
    }
}
