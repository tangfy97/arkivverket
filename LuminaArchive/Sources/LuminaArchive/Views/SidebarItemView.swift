import AppKit

final class SidebarItemView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    var isHighlighted = false {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)

        nameLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        nameLabel.textColor = Palette.text
        nameLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.isHidden = true
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let textX: CGFloat = 22
        let textWidth = bounds.width - textX - 8
        nameLabel.frame = NSRect(x: textX, y: (bounds.height - 16) / 2, width: textWidth, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHighlighted {
            let bgRect = bounds.insetBy(dx: 4, dy: 1)
            let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6)
            Palette.accentSubtle.setFill()
            bgPath.fill()

            nameLabel.textColor = Palette.accent

            let bar = NSRect(x: 7, y: 6, width: 3, height: bounds.height - 12)
            let barPath = NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5)
            Palette.accent.setFill()
            barPath.fill()
        } else {
            nameLabel.textColor = Palette.text
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let outlineView = enclosingFolderOutlineView(), outlineView.showContextMenu(for: event) {
            return
        }
        super.rightMouseDown(with: event)
    }

    private func enclosingFolderOutlineView() -> FolderOutlineView? {
        var current = superview
        while let view = current {
            if let outlineView = view as? FolderOutlineView {
                return outlineView
            }
            current = view.superview
        }
        return nil
    }
}
