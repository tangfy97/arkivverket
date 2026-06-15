import AppKit

final class HomeStateView: NSView {
    enum State {
        case welcome(recents: [URL])
        case loading(String)
        case message(String, showOpenButton: Bool)
    }

    var onOpenFolder: (() -> Void)?
    var onOpenRecent: ((URL) -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Arkiv")
    private let subtitleLabel = NSTextField(labelWithString: "Browse local image archives with rendered markdown profiles.")
    private let dropCard = DropZoneCardView()
    private let dropIcon = NSImageView()
    private let dropTitleLabel = NSTextField(labelWithString: "Drop an archive folder here")
    private let chooseButton = RoundedButton(title: "Choose Folder", target: nil, action: nil)
    private let shortcutLabel = NSTextField(labelWithString: "Cmd-O")
    private let dividerLabel = NSTextField(labelWithString: "or")
    private let hintBox = NSView()
    private let hintIcon = NSImageView()
    private let hintLabel = NSTextField(labelWithString: "Each subfolder with images or a profile.md file becomes a browsable entry.")
    private let recentTitleLabel = NSTextField(labelWithString: "Recent")
    private let loadingIndicator = NSProgressIndicator()
    private var recentRows: [RecentLibraryRow] = []
    private var state: State = .welcome(recents: [])

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 28, weight: .regular)
        titleLabel.textColor = Palette.accent
        titleLabel.alignment = .center
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = Palette.secondary
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        addSubview(subtitleLabel)

        addSubview(dropCard)
        dropIcon.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Folder")?
            .withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
        dropIcon.contentTintColor = Palette.accent
        dropIcon.alphaValue = 0.45
        dropCard.addSubview(dropIcon)

        dropTitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        dropTitleLabel.textColor = Palette.secondary
        dropTitleLabel.alignment = .center
        dropCard.addSubview(dropTitleLabel)

        chooseButton.target = self
        chooseButton.action = #selector(openFolder)
        chooseButton.fillColor = Palette.accent
        chooseButton.textColor = .white
        chooseButton.activeTextColor = .white
        chooseButton.setAccessibilityLabel("Choose folder")
        dropCard.addSubview(chooseButton)

        shortcutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        shortcutLabel.textColor = Palette.tertiary
        shortcutLabel.alignment = .center
        shortcutLabel.wantsLayer = true
        shortcutLabel.layer?.cornerRadius = 4
        shortcutLabel.layer?.borderWidth = 1
        dropCard.addSubview(shortcutLabel)

        dividerLabel.font = .systemFont(ofSize: 11, weight: .regular)
        dividerLabel.textColor = Palette.tertiary
        dividerLabel.alignment = .center
        dropCard.addSubview(dividerLabel)

        hintBox.wantsLayer = true
        hintBox.layer?.cornerRadius = 8
        addSubview(hintBox)

        hintIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Info")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        hintIcon.contentTintColor = Palette.accent
        hintIcon.alphaValue = 0.55
        hintBox.addSubview(hintIcon)

        hintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hintLabel.textColor = Palette.secondary
        hintLabel.maximumNumberOfLines = 2
        hintLabel.lineBreakMode = .byWordWrapping
        hintBox.addSubview(hintLabel)

        recentTitleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        recentTitleLabel.textColor = Palette.tertiary
        recentTitleLabel.alignment = .left
        addSubview(recentTitleLabel)

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .regular
        addSubview(loadingIndicator)

        setAccessibilityElement(true)
        setAccessibilityLabel("Arkiv home")
        refreshColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    func configure(_ state: State) {
        self.state = state
        if case let .welcome(recents) = state {
            rebuildRecentRows(recents)
        } else {
            rebuildRecentRows([])
        }
        needsLayout = true
        updateVisibility()
    }

    func refreshColors() {
        titleLabel.textColor = Palette.accent
        subtitleLabel.textColor = Palette.secondary
        dropTitleLabel.textColor = Palette.secondary
        shortcutLabel.textColor = Palette.tertiary
        shortcutLabel.layer?.backgroundColor = Palette.hover.withAlphaComponent(0.55).cgColor
        shortcutLabel.layer?.borderColor = Palette.border.cgColor
        dividerLabel.textColor = Palette.tertiary
        hintBox.layer?.backgroundColor = Palette.accentSubtle.withAlphaComponent(0.35).cgColor
        hintLabel.textColor = Palette.secondary
        recentTitleLabel.textColor = Palette.tertiary
        dropIcon.contentTintColor = Palette.accent
        hintIcon.contentTintColor = Palette.accent
        dropCard.needsDisplay = true
        recentRows.forEach { $0.refreshColors() }
    }

    override func layout() {
        super.layout()
        let contentWidth = min(bounds.width - 48, 380)
        let startY: CGFloat
        switch state {
        case .welcome(let recents):
            let recentHeight = recents.isEmpty ? 0 : CGFloat(min(recents.count, 4)) * 34 + 32
            let totalHeight: CGFloat = 68 + 16 + 34 + 10 + 40 + 22 + 134 + 18 + 56 + recentHeight
            startY = max(28, (bounds.height - totalHeight) / 2)
        case .loading, .message:
            startY = max(48, (bounds.height - 250) / 2)
        }

        let centerX = bounds.midX
        iconView.frame = NSRect(x: centerX - 34, y: startY, width: 68, height: 68)
        titleLabel.frame = NSRect(x: centerX - contentWidth / 2, y: iconView.frame.maxY + 14, width: contentWidth, height: 34)
        subtitleLabel.frame = NSRect(x: centerX - contentWidth / 2, y: titleLabel.frame.maxY + 6, width: contentWidth, height: 40)

        switch state {
        case .welcome:
            dropCard.frame = NSRect(x: centerX - contentWidth / 2, y: subtitleLabel.frame.maxY + 22, width: contentWidth, height: 134)
            layoutDropCard()
            hintBox.frame = NSRect(x: centerX - contentWidth / 2, y: dropCard.frame.maxY + 18, width: contentWidth, height: 56)
            hintIcon.frame = NSRect(x: 14, y: 14, width: 14, height: 14)
            hintLabel.frame = NSRect(x: 36, y: 10, width: contentWidth - 50, height: 36)
            layoutRecentRows(from: hintBox.frame.maxY + 22, width: contentWidth, centerX: centerX)
        case .loading(let message):
            loadingIndicator.frame = NSRect(x: centerX - 10, y: subtitleLabel.frame.maxY + 22, width: 20, height: 20)
            subtitleLabel.stringValue = message
        case .message(let message, _):
            subtitleLabel.stringValue = message
            dropCard.frame = NSRect(x: centerX - contentWidth / 2, y: subtitleLabel.frame.maxY + 22, width: contentWidth, height: 92)
            layoutMessageCard()
        }
    }

    private func layoutDropCard() {
        dropIcon.frame = NSRect(x: (dropCard.bounds.width - 24) / 2, y: 20, width: 24, height: 24)
        dropTitleLabel.frame = NSRect(x: 16, y: 50, width: dropCard.bounds.width - 32, height: 20)
        dividerLabel.frame = NSRect(x: (dropCard.bounds.width - 28) / 2, y: 76, width: 28, height: 18)
        chooseButton.frame = NSRect(x: (dropCard.bounds.width - 144) / 2, y: 98, width: 144, height: 32)
        shortcutLabel.frame = NSRect(x: chooseButton.frame.maxX + 10, y: 104, width: 52, height: 20)
    }

    private func layoutMessageCard() {
        dropIcon.frame = .zero
        dropTitleLabel.frame = .zero
        dividerLabel.frame = .zero
        chooseButton.frame = NSRect(x: (dropCard.bounds.width - 144) / 2, y: 30, width: 144, height: 32)
        shortcutLabel.frame = .zero
    }

    private func layoutRecentRows(from y: CGFloat, width: CGFloat, centerX: CGFloat) {
        guard !recentRows.isEmpty else { return }
        recentTitleLabel.frame = NSRect(x: centerX - width / 2 + 2, y: y, width: width, height: 16)
        var rowY = recentTitleLabel.frame.maxY + 6
        for row in recentRows {
            row.frame = NSRect(x: centerX - width / 2, y: rowY, width: width, height: 32)
            rowY += 34
        }
    }

    private func updateVisibility() {
        switch state {
        case .welcome:
            subtitleLabel.stringValue = "Browse local image archives with rendered markdown profiles."
            [iconView, titleLabel, subtitleLabel, dropCard, hintBox].forEach { $0.isHidden = false }
            recentTitleLabel.isHidden = recentRows.isEmpty
            loadingIndicator.stopAnimation(nil)
            loadingIndicator.isHidden = true
        case .loading(let message):
            subtitleLabel.stringValue = message
            [iconView, titleLabel, subtitleLabel].forEach { $0.isHidden = false }
            [dropCard, hintBox, recentTitleLabel].forEach { $0.isHidden = true }
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
        case .message(let message, let showOpenButton):
            subtitleLabel.stringValue = message
            [iconView, titleLabel, subtitleLabel].forEach { $0.isHidden = false }
            dropCard.isHidden = !showOpenButton
            chooseButton.isHidden = !showOpenButton
            [hintBox, recentTitleLabel].forEach { $0.isHidden = true }
            loadingIndicator.stopAnimation(nil)
            loadingIndicator.isHidden = true
        }
        recentRows.forEach { $0.isHidden = recentTitleLabel.isHidden }
    }

    private func rebuildRecentRows(_ urls: [URL]) {
        recentRows.forEach { $0.removeFromSuperview() }
        recentRows = urls.prefix(4).map { url in
            let row = RecentLibraryRow(url: url)
            row.target = self
            row.action = #selector(openRecent(_:))
            addSubview(row)
            return row
        }
    }

    @objc private func openFolder() {
        onOpenFolder?()
    }

    @objc private func openRecent(_ sender: RecentLibraryRow) {
        onOpenRecent?(sender.url)
    }
}

private final class DropZoneCardView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        Palette.card.withAlphaComponent(0.45).setFill()
        path.fill()
        Palette.border.setStroke()
        path.lineWidth = 1.5
        path.setLineDash([7, 5], count: 2, phase: 0)
        path.stroke()
    }
}

private final class RecentLibraryRow: NSButton {
    let url: URL
    private let folderIcon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        wantsLayer = true
        toolTip = url.path
        setAccessibilityLabel("Open recent library \(url.lastPathComponent)")

        folderIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        addSubview(folderIcon)

        nameLabel.stringValue = url.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        pathLabel.stringValue = url.deletingLastPathComponent().lastPathComponent
        pathLabel.font = .systemFont(ofSize: 11, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(pathLabel)
        refreshColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    func refreshColors() {
        folderIcon.contentTintColor = Palette.accent
        nameLabel.textColor = Palette.text
        pathLabel.textColor = Palette.tertiary
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        Palette.hover.setFill()
        path.fill()
    }

    override func layout() {
        super.layout()
        folderIcon.frame = NSRect(x: 10, y: 9, width: 14, height: 14)
        nameLabel.frame = NSRect(x: 34, y: 4, width: bounds.width - 44, height: 16)
        pathLabel.frame = NSRect(x: 34, y: 18, width: bounds.width - 44, height: 12)
    }
}
