import AppKit

final class IconButton: NSButton {
    var isActive = false {
        didSet { needsDisplay = true }
    }

    init(symbol: String, tooltip: String) {
        super.init(frame: .zero)
        toolTip = tooltip
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryChange)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        imageScaling = .scaleNone
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        (isActive ? Palette.accentSubtle : NSColor.clear).setFill()
        path.fill()

        let color = isActive ? Palette.accent : Palette.secondary
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        if let image = image?.withSymbolConfiguration(config) {
            let size = image.size
            image.draw(in: NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            ))
        }
    }
}
