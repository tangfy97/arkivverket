import AppKit

final class BackgroundView: NSView {
    var color: NSColor = Palette.bg {
        didSet { needsDisplay = true }
    }
    var onFolderDrop: ((URL) -> Void)?
    var onAppearanceChange: (() -> Void)?
    private var isDropTargeted = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
        guard isDropTargeted else { return }
        let rect = bounds.insetBy(dx: 18, dy: 18)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        Palette.accentSubtle.setFill()
        path.fill()
        Palette.accent.setStroke()
        path.lineWidth = 2
        path.setLineDash([8, 6], count: 2, phase: 0)
        path.stroke()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard folderURL(from: sender) != nil else { return [] }
        isDropTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { isDropTargeted = false }
        guard let url = folderURL(from: sender) else { return false }
        onFolderDrop?(url)
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
        needsDisplay = true
    }

    private func folderURL(from draggingInfo: NSDraggingInfo) -> URL? {
        guard let string = draggingInfo.draggingPasteboard.string(forType: .fileURL),
              let url = URL(string: string) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }
}
