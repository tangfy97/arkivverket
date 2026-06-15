import AppKit

final class FolderOutlineView: NSOutlineView {
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func rightMouseDown(with event: NSEvent) {
        if showContextMenu(for: event) {
            return
        }
        super.rightMouseDown(with: event)
    }

    @discardableResult
    func showContextMenu(for event: NSEvent) -> Bool {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0, let menu = contextMenuProvider?(row) else { return false }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        return true
    }
}
