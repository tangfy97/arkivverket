import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

enum Palette {
    static let bg = NSColor(calibratedRed: 0.973, green: 0.969, blue: 0.953, alpha: 1)
    static let surface = NSColor.white
    static let elevated = NSColor(calibratedRed: 0.980, green: 0.976, blue: 0.965, alpha: 1)
    static let hover = NSColor(calibratedRed: 0.941, green: 0.937, blue: 0.929, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.357, green: 0.549, blue: 0.541, alpha: 1)
    static let text = NSColor(calibratedWhite: 0.20, alpha: 1)
    static let secondary = NSColor(calibratedWhite: 0.58, alpha: 1)
    static let border = NSColor(calibratedWhite: 0.0, alpha: 0.07)
    static let dark = NSColor(calibratedWhite: 0.04, alpha: 1)
}
