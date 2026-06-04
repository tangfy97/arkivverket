import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class SidebarItemView: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = Palette.text
        title.lineBreakMode = .byTruncatingMiddle
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = Palette.secondary
        addSubview(title)
        addSubview(subtitle)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 12, y: 7, width: bounds.width - 24, height: 18)
        subtitle.frame = NSRect(x: 12, y: 26, width: bounds.width - 24, height: 16)
    }
}
