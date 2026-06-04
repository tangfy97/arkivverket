import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class BackgroundView: NSView {
    var color: NSColor = Palette.bg {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}
