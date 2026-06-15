import AppKit

final class ImageCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImageCollectionItem")
    private let cardView = NSView()
    private let thumbView = NSImageView()
    private let numberLabel = NSTextField(labelWithString: "")
    private let badgeView = SelectionBadgeView()
    private var representedURL: URL?
    private var representedName = ""
    private var representedIndex = 0

    override var isSelected: Bool {
        didSet { applySelection(isSelected) }
    }

    override func loadView() {
        view = ThumbnailCellView()
        view.setAccessibilityElement(true)

        cardView.wantsLayer = true
        cardView.layer?.backgroundColor = Palette.card.cgColor
        cardView.layer?.cornerRadius = 10
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0.09
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        cardView.layer?.shadowRadius = 6
        cardView.layer?.masksToBounds = false

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 7
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.backgroundColor = Palette.hover.cgColor

        numberLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        numberLabel.textColor = Palette.secondary
        numberLabel.alignment = .center
        badgeView.isHidden = true

        cardView.addSubview(thumbView)
        view.addSubview(cardView)
        view.addSubview(badgeView)
        view.addSubview(numberLabel)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let pad: CGFloat = 6
        let labelHeight: CGFloat = 20
        cardView.frame = NSRect(
            x: 0,
            y: labelHeight + 4,
            width: view.bounds.width,
            height: view.bounds.height - labelHeight - 4
        )
        thumbView.frame = cardView.bounds.insetBy(dx: pad, dy: pad)
        cardView.layer?.shadowPath = CGPath(roundedRect: cardView.bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        badgeView.frame = NSRect(x: cardView.frame.maxX - 34, y: cardView.frame.minY + 10, width: 24, height: 24)
        numberLabel.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: labelHeight)
    }

    func configure(asset: ImageAsset, index: Int, side: CGFloat, isCurrent: Bool, isSelected: Bool) {
        representedURL = asset.url
        representedName = asset.url.lastPathComponent
        representedIndex = index
        numberLabel.stringValue = String(format: "%03d", index + 1)
        view.toolTip = asset.url.lastPathComponent
        thumbView.image = nil
        _ = isCurrent
        (view as? ThumbnailCellView)?.indexPath = IndexPath(item: index, section: 0)
        updateSelection(isCurrent: isCurrent, isSelected: isSelected)

        ImageCache.shared.thumbnail(for: asset.url, side: side) { [weak self] image in
            guard let self, self.representedURL == asset.url else { return }
            self.thumbView.image = image
        }
    }

    func updateSelection(isCurrent: Bool, isSelected: Bool) {
        _ = isCurrent
        applySelection(isSelected)
        view.setAccessibilityLabel("\(representedName), image \(representedIndex + 1)\(isSelected ? ", selected" : "")")
        view.setAccessibilityValue(isSelected ? "selected" : "not selected")
    }

    private func applySelection(_ selected: Bool) {
        (view as? ThumbnailCellView)?.isSelectedForExport = selected
        badgeView.isHidden = !selected
        badgeView.needsDisplay = true
        numberLabel.textColor = selected ? Palette.accent : Palette.tertiary
        let layer = cardView.layer
        layer?.backgroundColor = (selected ? Palette.selected : Palette.card).cgColor
        layer?.borderColor = (selected ? Palette.accent : NSColor.clear).cgColor
        layer?.borderWidth = selected ? 4 : 0
        layer?.shadowOpacity = selected ? 0.22 : 0.09
        layer?.shadowRadius = selected ? 10 : 6
    }
}

private final class SelectionBadgeView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let badgePath = NSBezierPath(ovalIn: rect)
        Palette.accent.setFill()
        badgePath.fill()

        let check = NSBezierPath()
        check.move(to: NSPoint(x: rect.minX + 6, y: rect.midY))
        check.line(to: NSPoint(x: rect.minX + 10, y: rect.midY + 5))
        check.line(to: NSPoint(x: rect.maxX - 6, y: rect.midY - 6))
        NSColor.white.setStroke()
        check.lineWidth = 2.4
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
    }
}

final class ThumbnailCellView: NSView {
    var indexPath: IndexPath?
    var isSelectedForExport = false {
        didSet { needsDisplay = true }
    }
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        if let collectionView = enclosingCollectionView(), let indexPath {
            collectionView.mouseDown(onItemAt: indexPath, with: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let collectionView = enclosingCollectionView() {
            collectionView.mouseDragged(with: event)
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let collectionView = enclosingCollectionView() {
            collectionView.mouseUp(with: event)
            return
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let collectionView = enclosingCollectionView(), collectionView.showContextMenu(for: event) {
            return
        }
        super.rightMouseDown(with: event)
    }

    private func enclosingCollectionView() -> DoubleClickCollectionView? {
        var current = superview
        while let view = current {
            if let collectionView = view as? DoubleClickCollectionView {
                return collectionView
            }
            current = view.superview
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let labelHeight: CGFloat = 24
        let ringRect = NSRect(
            x: 1,
            y: labelHeight + 5,
            width: bounds.width - 2,
            height: bounds.height - labelHeight - 6
        )
        let path = NSBezierPath(roundedRect: ringRect, xRadius: 11, yRadius: 11)
        if isHovered && !isSelectedForExport {
            Palette.accentSubtle.setFill()
            path.fill()
        }
    }
}
