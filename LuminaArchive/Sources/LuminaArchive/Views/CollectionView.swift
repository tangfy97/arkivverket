import AppKit

final class DoubleClickCollectionView: NSCollectionView {
    var keyHandler: ((NSEvent) -> Bool)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var itemClickHandler: ((IndexPath, Bool) -> Void)?
    var itemDoubleClickHandler: ((IndexPath) -> Void)?
    var dragSelectionHandler: ((Set<IndexPath>) -> Void)?
    private var dragStartPoint: NSPoint?
    private var dragStartIndexPath: IndexPath?
    private var hasStartedRangeSelection = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let indexPath = indexPathForItemOrLayout(at: point) {
            itemDoubleClickHandler?(indexPath)
            return
        }
        guard let indexPath = indexPathForItemOrLayout(at: point) else {
            dragStartPoint = nil
            dragStartIndexPath = nil
            hasStartedRangeSelection = false
            return
        }
        dragStartPoint = point
        dragStartIndexPath = indexPath
        hasStartedRangeSelection = false
        itemClickHandler?(indexPath, event.modifierFlags.contains(.command))
    }

    func mouseDown(onItemAt indexPath: IndexPath, with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            itemDoubleClickHandler?(indexPath)
            return
        }
        dragStartPoint = convert(event.locationInWindow, from: nil)
        dragStartIndexPath = indexPath
        hasStartedRangeSelection = false
        itemClickHandler?(indexPath, event.modifierFlags.contains(.command))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint else {
            super.mouseDragged(with: event)
            return
        }
        let currentPoint = convert(event.locationInWindow, from: nil)
        if !hasStartedRangeSelection {
            let dx = currentPoint.x - dragStartPoint.x
            let dy = currentPoint.y - dragStartPoint.y
            guard hypot(dx, dy) > 6 else { return }
            hasStartedRangeSelection = true
        }
        let rect = NSRect(
            x: min(dragStartPoint.x, currentPoint.x),
            y: min(dragStartPoint.y, currentPoint.y),
            width: abs(currentPoint.x - dragStartPoint.x),
            height: abs(currentPoint.y - dragStartPoint.y)
        )
        var indexPaths = indexPathsIntersecting(rect)
        if let dragStartIndexPath {
            indexPaths.insert(dragStartIndexPath)
        }
        if !indexPaths.isEmpty {
            dragSelectionHandler?(indexPaths)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
        dragStartIndexPath = nil
        hasStartedRangeSelection = false
    }

    override func rightMouseDown(with event: NSEvent) {
        if showContextMenu(for: event) {
            return
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        return contextMenuProvider?(indexPathForItemOrLayout(at: point)) ?? super.menu(for: event)
    }

    @discardableResult
    func showContextMenu(for event: NSEvent) -> Bool {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let menu = contextMenuProvider?(indexPathForItemOrLayout(at: point)) else { return false }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    private func indexPathsIntersecting(_ rect: NSRect) -> Set<IndexPath> {
        guard let layout = collectionViewLayout else { return [] }
        let attributes = layout.layoutAttributesForElements(in: rect)
        return Set(attributes.compactMap { attribute in
            guard attribute.representedElementCategory == .item,
                  attribute.frame.intersects(rect) else {
                return nil
            }
            return attribute.indexPath
        })
    }

    private func indexPathForItemOrLayout(at point: NSPoint) -> IndexPath? {
        if let indexPath = indexPathForItem(at: point) {
            return indexPath
        }

        let hitRect = NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
        guard let layout = collectionViewLayout else { return nil }
        return layout.layoutAttributesForElements(in: hitRect)
            .first(where: { attribute in
                attribute.representedElementCategory == .item && attribute.frame.contains(point)
            })?
            .indexPath
    }
}
