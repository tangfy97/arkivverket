import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

enum Palette {
    static let bg = NSColor(srgbRed: 0.957, green: 0.953, blue: 0.941, alpha: 1)
    static let surface = NSColor(srgbRed: 0.994, green: 0.992, blue: 0.988, alpha: 1)
    static let elevated = NSColor(srgbRed: 0.969, green: 0.965, blue: 0.953, alpha: 1)
    static let hover = NSColor(srgbRed: 0.918, green: 0.914, blue: 0.902, alpha: 1)
    static let selected = NSColor(srgbRed: 0.290, green: 0.475, blue: 0.463, alpha: 0.10)
    static let accent = NSColor(srgbRed: 0.235, green: 0.435, blue: 0.420, alpha: 1)
    static let accentSubtle = NSColor(srgbRed: 0.235, green: 0.435, blue: 0.420, alpha: 0.18)
    static let text = NSColor(calibratedWhite: 0.08, alpha: 1)
    static let secondary = NSColor(calibratedWhite: 0.46, alpha: 1)
    static let tertiary = NSColor(calibratedWhite: 0.65, alpha: 1)
    static let border = NSColor(calibratedWhite: 0.0, alpha: 0.055)
    static let divider = NSColor(calibratedWhite: 0.0, alpha: 0.072)
    static let dark = NSColor(srgbRed: 0.040, green: 0.040, blue: 0.042, alpha: 1)
    static let darkOverlay = NSColor(calibratedWhite: 0.0, alpha: 0.52)
}
