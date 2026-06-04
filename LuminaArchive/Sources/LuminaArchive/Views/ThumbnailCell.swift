import AppKit

final class ImageCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImageCollectionItem")
    private let cardView = NSView()
    private let thumbView = NSImageView()
    private let numberLabel = NSTextField(labelWithString: "")
    private var representedURL: URL?

    override func loadView() {
        view = ThumbnailCellView()

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

        cardView.addSubview(thumbView)
        view.addSubview(cardView)
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
        numberLabel.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: labelHeight)
    }

    func configure(asset: ImageAsset, index: Int, side: CGFloat, isCurrent: Bool) {
        representedURL = asset.url
        numberLabel.stringValue = String(format: "%03d", index + 1)
        numberLabel.textColor = isCurrent ? Palette.accent : Palette.tertiary
        thumbView.image = nil
        (view as? ThumbnailCellView)?.isSelected = isCurrent

        ImageCache.shared.thumbnail(for: asset.url, side: side) { [weak self] image in
            guard let self, self.representedURL == asset.url else { return }
            self.thumbView.image = image
        }
    }
}

final class ThumbnailCellView: NSView {
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let labelHeight: CGFloat = 24
        let ringRect = NSRect(
            x: 1,
            y: labelHeight + 5,
            width: bounds.width - 2,
            height: bounds.height - labelHeight - 6
        )
        let path = NSBezierPath(roundedRect: ringRect, xRadius: 11, yRadius: 11)
        Palette.accent.setStroke()
        path.lineWidth = 2.5
        path.stroke()
    }
}
