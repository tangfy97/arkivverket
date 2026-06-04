import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class ImageCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImageCollectionItem")
    private let thumbImageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var representedURL: URL?

    var selectedAccent: Bool = false {
        didSet { view.needsDisplay = true }
    }

    override func loadView() {
        view = ThumbnailCellView()
        view.wantsLayer = true

        thumbImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbImageView.wantsLayer = true
        thumbImageView.layer?.backgroundColor = NSColor.white.cgColor
        thumbImageView.layer?.cornerRadius = 8
        thumbImageView.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = Palette.secondary
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle

        view.addSubview(thumbImageView)
        view.addSubview(label)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let labelHeight: CGFloat = 18
        thumbImageView.frame = NSRect(x: 6, y: 6, width: view.bounds.width - 12, height: view.bounds.height - labelHeight - 14)
        label.frame = NSRect(x: 4, y: view.bounds.height - labelHeight - 2, width: view.bounds.width - 8, height: labelHeight)
    }

    func configure(asset: ImageAsset, side: CGFloat, isCurrent: Bool) {
        representedURL = asset.url
        label.stringValue = asset.name
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
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.white.setFill()
        path.fill()
        (isSelected ? Palette.accent : Palette.border).setStroke()
        path.lineWidth = isSelected ? 3 : 1
        path.stroke()
    }
}
