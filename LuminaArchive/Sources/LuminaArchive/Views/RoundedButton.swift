import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class RoundedButton: NSButton {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    var activeFillColor: NSColor = Palette.surface { didSet { needsDisplay = true } }
    var textColor: NSColor = Palette.secondary { didSet { needsDisplay = true } }
    var activeTextColor: NSColor = Palette.text { didSet { needsDisplay = true } }
    var isActive: Bool = false { didSet { needsDisplay = true } }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 12, weight: .medium)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let radius = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        (isActive ? activeFillColor : fillColor).setFill()
        path.fill()
        Palette.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        let foregroundColor = isActive ? activeTextColor : textColor
        if let image {
            let drawImage = image.withSymbolConfiguration(.init(paletteColors: [foregroundColor])) ?? image
            let size = drawImage.size
            let imageRect = NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            drawImage.draw(in: imageRect)
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: foregroundColor
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
