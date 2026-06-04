import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class DoubleClickCollectionView: NSCollectionView {
    var keyHandler: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let indexPath = indexPathForItem(at: point) {
            (delegate as? MainWindowController)?.openCollectionItem(at: indexPath)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
