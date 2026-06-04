import AppKit

final class SidebarItemView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let cardBg = NSView()
    var isHighlighted = false {
        didSet {
            needsDisplay = true
            updateCard()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        cardBg.wantsLayer = true
        cardBg.layer?.cornerRadius = 9
        addSubview(cardBg)

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = Palette.text
        nameLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = Palette.tertiary
        addSubview(nameLabel)
        addSubview(subtitleLabel)
        updateCard()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    private func updateCard() {
        if isHighlighted {
            cardBg.layer?.backgroundColor = Palette.card.cgColor
            cardBg.layer?.shadowColor = NSColor.black.cgColor
            cardBg.layer?.shadowOpacity = 0.10
            cardBg.layer?.shadowOffset = CGSize(width: 0, height: -1)
            cardBg.layer?.shadowRadius = 4
            nameLabel.textColor = Palette.text
        } else {
            cardBg.layer?.backgroundColor = Palette.card.withAlphaComponent(0.45).cgColor
            cardBg.layer?.shadowOpacity = 0
            nameLabel.textColor = Palette.text
        }
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        cardBg.frame = NSRect(x: inset, y: 4, width: bounds.width - inset * 2, height: bounds.height - 8)
        let textX: CGFloat = inset + 12
        let textWidth = bounds.width - textX - inset - 12
        nameLabel.frame = NSRect(x: textX, y: 10, width: textWidth, height: 18)
        subtitleLabel.frame = NSRect(x: textX, y: 29, width: textWidth, height: 15)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted else { return }
        let barX: CGFloat = 11
        let bar = NSRect(x: barX, y: 8, width: 3, height: bounds.height - 16)
        let path = NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5)
        Palette.accent.setFill()
        path.fill()
    }
}
