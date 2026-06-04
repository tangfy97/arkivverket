import AppKit

final class SidebarItemView: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        title.font = .systemFont(ofSize: 13.5, weight: .medium)
        title.textColor = Palette.text
        title.lineBreakMode = .byTruncatingMiddle
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = Palette.tertiary
        addSubview(title)
        addSubview(subtitle)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 16, y: 10, width: bounds.width - 32, height: 19)
        subtitle.frame = NSRect(x: 16, y: 30, width: bounds.width - 32, height: 15)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            Palette.selected.setFill()
            bounds.fill()
            let bar = NSRect(x: 0, y: 4, width: 3, height: bounds.height - 8)
            let path = NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5)
            Palette.accent.setFill()
            path.fill()
        }
    }
}
