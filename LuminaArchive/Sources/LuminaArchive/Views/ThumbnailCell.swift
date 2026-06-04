import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class ImageCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImageCollectionItem")
    private let thumbShadowView = NSView()
    private let thumbImageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var representedURL: URL?

    var selectedAccent: Bool = false {
        didSet { view.needsDisplay = true }
    }

    override func loadView() {
        view = ThumbnailCellView()
        view.wantsLayer = true

        thumbShadowView.wantsLayer = true
        thumbShadowView.layer?.backgroundColor = Palette.hover.cgColor
        thumbShadowView.layer?.cornerRadius = 8
        thumbShadowView.layer?.shadowColor = NSColor.black.cgColor
        thumbShadowView.layer?.shadowOpacity = 0.12
        thumbShadowView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        thumbShadowView.layer?.shadowRadius = 6
        thumbShadowView.layer?.masksToBounds = false

        thumbImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbImageView.wantsLayer = true
        thumbImageView.layer?.backgroundColor = Palette.hover.cgColor
        thumbImageView.layer?.cornerRadius = 8
        thumbImageView.layer?.masksToBounds = true

        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.textColor = Palette.tertiary
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle

        thumbShadowView.addSubview(thumbImageView)
        view.addSubview(thumbShadowView)
        view.addSubview(label)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let labelHeight: CGFloat = 18
        thumbShadowView.frame = NSRect(x: 6, y: 6, width: view.bounds.width - 12, height: view.bounds.height - labelHeight - 14)
        thumbShadowView.layer?.shadowPath = CGPath(roundedRect: thumbShadowView.bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        thumbImageView.frame = thumbShadowView.bounds
        label.frame = NSRect(x: 4, y: view.bounds.height - labelHeight - 2, width: view.bounds.width - 8, height: labelHeight)
    }

    func configure(asset: ImageAsset, index: Int, side: CGFloat, isCurrent: Bool) {
        representedURL = asset.url
        label.stringValue = String(format: "%03d", index + 1)
        thumbImageView.image = nil
        selectedAccent = isCurrent
        (view as? ThumbnailCellView)?.isSelected = isCurrent

        ImageCache.shared.thumbnail(for: asset.url, side: side) { [weak self] image in
            guard let self, self.representedURL == asset.url else { return }
            self.thumbImageView.image = image
        }
    }
}

final class ThumbnailCellView: NSView {
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            Palette.accent.setStroke()
            path.lineWidth = 2.5
            path.stroke()
        }
    }
}
