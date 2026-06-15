import AppKit

enum Palette {
    static let bg = dynamic(
        light: NSColor(srgbRed: 0.898, green: 0.890, blue: 0.874, alpha: 1),
        dark: NSColor(srgbRed: 0.105, green: 0.106, blue: 0.112, alpha: 1)
    )
    static let card = dynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.158, green: 0.160, blue: 0.170, alpha: 1)
    )
    static let cardShadowColor = dynamic(
        light: NSColor(calibratedWhite: 0, alpha: 0.10),
        dark: NSColor(calibratedWhite: 0, alpha: 0.35)
    )
    static let surface = dynamic(
        light: NSColor(srgbRed: 0.994, green: 0.992, blue: 0.988, alpha: 1),
        dark: NSColor(srgbRed: 0.125, green: 0.127, blue: 0.135, alpha: 1)
    )
    static let elevated = dynamic(
        light: NSColor(srgbRed: 0.969, green: 0.965, blue: 0.953, alpha: 1),
        dark: NSColor(srgbRed: 0.190, green: 0.193, blue: 0.205, alpha: 1)
    )
    static let hover = dynamic(
        light: NSColor(srgbRed: 0.918, green: 0.914, blue: 0.902, alpha: 1),
        dark: NSColor(srgbRed: 0.235, green: 0.238, blue: 0.250, alpha: 1)
    )
    static let selected = dynamic(
        light: NSColor(srgbRed: 0.290, green: 0.475, blue: 0.463, alpha: 0.10),
        dark: NSColor(srgbRed: 0.478, green: 0.730, blue: 0.700, alpha: 0.18)
    )
    static let accent = dynamic(
        light: NSColor(srgbRed: 0.235, green: 0.435, blue: 0.420, alpha: 1),
        dark: NSColor(srgbRed: 0.478, green: 0.730, blue: 0.700, alpha: 1)
    )
    static let accentSubtle = dynamic(
        light: NSColor(srgbRed: 0.235, green: 0.435, blue: 0.420, alpha: 0.18),
        dark: NSColor(srgbRed: 0.478, green: 0.730, blue: 0.700, alpha: 0.22)
    )
    static let text = dynamic(
        light: NSColor(calibratedWhite: 0.08, alpha: 1),
        dark: NSColor(calibratedWhite: 0.92, alpha: 1)
    )
    static let secondary = dynamic(
        light: NSColor(calibratedWhite: 0.46, alpha: 1),
        dark: NSColor(calibratedWhite: 0.72, alpha: 1)
    )
    static let tertiary = dynamic(
        light: NSColor(calibratedWhite: 0.52, alpha: 1),
        dark: NSColor(calibratedWhite: 0.62, alpha: 1)
    )
    static let border = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.055),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.090)
    )
    static let divider = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.072),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.110)
    )
    static let dark = NSColor(srgbRed: 0.040, green: 0.040, blue: 0.042, alpha: 1)
    static let darkOverlay = NSColor(calibratedWhite: 0.0, alpha: 0.52)

    static let sidebarBg = dynamic(
        light: NSColor(srgbRed: 0.884, green: 0.877, blue: 0.862, alpha: 1),
        dark: NSColor(srgbRed: 0.095, green: 0.096, blue: 0.102, alpha: 1)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}
