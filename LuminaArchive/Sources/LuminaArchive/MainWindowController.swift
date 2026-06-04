import AppKit
import WebKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    private let store = ArchiveStore()
    private var browserRoot: FolderNode?
    private var suppressBrowserSelection = false
    private var keyMonitor: Any?
    private let sidebarImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp",
        "bmp", "jp2", "cr2", "cr3", "nef", "arw", "raf", "rw2", "dng"
    ]
    private var models: [ModelFolder] = []
    private var filteredImages: [ImageAsset] = []
    private var selectedModelIndex = 0
    private var selectedImageIndex = 0
    private var viewMode: ViewMode = .split
    private var density: Density = .spacious
    private var profileVisible = true
    private var viewerProfileVisible = false
    private var slideshowTimer: Timer?
    private var sidebarSubtitleCache: [URL: String] = [:]
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var suppressCollectionSelectionHandler = false

    private let rootView = BackgroundView()
    private let topBar = NSVisualEffectView()
    private let modeControl = NSSegmentedControl(labels: ["Split", "Tabbed", "Fullscreen"], trackingMode: .selectOne, target: nil, action: nil)
    private let openButton = RoundedButton(title: "Choose Library", target: nil, action: nil)
    private let densityButton = IconButton(symbol: "square.grid.3x3.fill", tooltip: "Grid density")
    private let slideshowButton = IconButton(symbol: "play.fill", tooltip: "Slideshow")
    private let profileButton = IconButton(symbol: "text.alignleft", tooltip: "Profile")
    private let searchField = NSSearchField()
    private let sidebar = NSOutlineView()
    private let sidebarScroll = NSScrollView()
    private let sidebarDivider = NSView()
    private let libraryPathLabel = NSTextField(labelWithString: "No folder selected")
    private let changeLibraryButton = NSButton()
    private let toolbarStrip = BackgroundView()
    private let collectionView = DoubleClickCollectionView()
    private let collectionScroll = NSScrollView()
    private let previewImageView = NSImageView()
    private let viewerTopBar = NSView()
    private let viewerBottomBar = NSView()
    private let viewerTopGradient = CAGradientLayer()
    private let viewerBottomGradient = CAGradientLayer()
    private let viewerTitleLabel = NSTextField(labelWithString: "")
    private let viewerMetaLabel = NSTextField(labelWithString: "")
    private let viewerFileLabel = NSTextField(labelWithString: "")
    private let viewerExitButton = RoundedButton(title: "Exit", target: nil, action: nil)
    private let viewerProfileButton = RoundedButton(title: "Profile", target: nil, action: nil)
    private let viewerPrevButton = RoundedButton(title: "‹", target: nil, action: nil)
    private let viewerNextButton = RoundedButton(title: "›", target: nil, action: nil)
    private let profileCardView = NSView()
    private let profileWebView = WKWebView()
    private let profileDivider = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "Drop a folder here, or choose one below")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Arkiv"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 980, height: 620)
        self.init(window: window)
        window.delegate = self
        setup()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.makeFirstResponder(nil)
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func setup() {
        guard let window else { return }
        rootView.color = Palette.bg
        window.contentView = rootView

        setupTopBar()
        setupSidebar()
        setupDividers()
        setupToolbarStrip()
        setupCollection()
        setupPreview()
        setupViewerOverlay()
        setupProfile()
        setupStatusBar()
        setupEmptyState()
        layoutViews()
        updateModeButtons()
        updateContentVisibility()
        installKeyMonitor()

        let arguments = Array(CommandLine.arguments.dropFirst())
        let shouldOpenViewer = arguments.contains("--viewer")
        let shouldOpenViewerProfile = arguments.contains("--viewer-profile")
        if let argument = arguments.first(where: { !$0.hasPrefix("--") }) {
            openArchive(URL(fileURLWithPath: argument))
            if shouldOpenViewer, !filteredImages.isEmpty {
                openViewer(at: selectedImageIndex, showProfile: shouldOpenViewerProfile)
            }
        }
    }

    private func setupTopBar() {
        topBar.material = .headerView
        topBar.blendingMode = .withinWindow
        topBar.state = .active
        rootView.addSubview(topBar)

        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .rounded
        modeControl.font = .systemFont(ofSize: 11, weight: .regular)
        rootView.addSubview(modeControl)

        openButton.target = self
        openButton.action = #selector(openFolder)
        openButton.fillColor = Palette.accent
        openButton.textColor = .white
        openButton.activeTextColor = .white

        searchField.placeholderString = "Search images"
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 13)
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 8
        rootView.addSubview(searchField)

        densityButton.target = self
        densityButton.action = #selector(toggleDensity)
        rootView.addSubview(densityButton)

        slideshowButton.target = self
        slideshowButton.action = #selector(toggleSlideshow)
        rootView.addSubview(slideshowButton)

        profileButton.target = self
        profileButton.action = #selector(toggleProfile)
        rootView.addSubview(profileButton)
    }

    private func setupSidebar() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Model"))
        sidebar.addTableColumn(column)
        sidebar.outlineTableColumn = column
        sidebar.headerView = nil
        sidebar.rowHeight = 60
        sidebar.intercellSpacing = NSSize(width: 0, height: 0)
        sidebar.backgroundColor = .clear
        sidebar.selectionHighlightStyle = .none
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebarScroll.documentView = sidebar
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        rootView.addSubview(sidebarScroll)

        libraryPathLabel.font = .systemFont(ofSize: 12, weight: .medium)
        libraryPathLabel.textColor = Palette.secondary
        libraryPathLabel.lineBreakMode = .byTruncatingMiddle
        changeLibraryButton.target = self
        changeLibraryButton.action = #selector(openFolder)
        changeLibraryButton.bezelStyle = .regularSquare
        changeLibraryButton.isBordered = false
        changeLibraryButton.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Change library")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        changeLibraryButton.imageScaling = .scaleNone
        changeLibraryButton.toolTip = "Choose library"
        rootView.addSubview(libraryPathLabel)
        rootView.addSubview(changeLibraryButton)
    }

    private func setupDividers() {
        for divider in [sidebarDivider, profileDivider] {
            divider.wantsLayer = true
            divider.layer?.backgroundColor = Palette.border.cgColor
            rootView.addSubview(divider, positioned: .above, relativeTo: nil)
        }
    }

    private func setupToolbarStrip() {
        toolbarStrip.color = Palette.surface
        rootView.addSubview(toolbarStrip, positioned: .below, relativeTo: searchField)
    }

    private func setupCollection() {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 20
        layout.minimumLineSpacing = 24
        layout.sectionInset = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        layout.itemSize = NSSize(width: density.itemSide, height: density.itemSide + 28)

        collectionView.collectionViewLayout = layout
        collectionView.register(ImageCollectionItem.self, forItemWithIdentifier: ImageCollectionItem.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        collectionView.isSelectable = true
        collectionView.backgroundColors = [Palette.bg]
        collectionView.allowsEmptySelection = false
        collectionScroll.documentView = collectionView
        collectionScroll.hasVerticalScroller = true
        collectionScroll.drawsBackground = false
        rootView.addSubview(collectionScroll)
    }

    private func setupPreview() {
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = Palette.dark.cgColor
        previewImageView.layer?.cornerRadius = 0
        rootView.addSubview(previewImageView)
    }

    private func setupViewerOverlay() {
        viewerTopBar.wantsLayer = true
        viewerTopGradient.colors = [NSColor.black.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
        viewerTopGradient.startPoint = CGPoint(x: 0.5, y: 1)
        viewerTopGradient.endPoint = CGPoint(x: 0.5, y: 0)
        viewerTopBar.layer?.addSublayer(viewerTopGradient)
        rootView.addSubview(viewerTopBar)

        viewerBottomBar.wantsLayer = true
        viewerBottomGradient.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.55).cgColor]
        viewerBottomGradient.startPoint = CGPoint(x: 0.5, y: 1)
        viewerBottomGradient.endPoint = CGPoint(x: 0.5, y: 0)
        viewerBottomBar.layer?.addSublayer(viewerBottomGradient)
        rootView.addSubview(viewerBottomBar)

        viewerTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        viewerTitleLabel.textColor = .white
        viewerMetaLabel.font = .systemFont(ofSize: 11, weight: .medium)
        viewerMetaLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        viewerFileLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .light)
        viewerFileLabel.textColor = NSColor.white.withAlphaComponent(0.60)
        viewerFileLabel.alignment = .center

        viewerExitButton.target = self
        viewerExitButton.action = #selector(exitViewer)
        viewerProfileButton.target = self
        viewerProfileButton.action = #selector(toggleViewerProfile)
        viewerPrevButton.target = self
        viewerPrevButton.action = #selector(previousImage)
        viewerNextButton.target = self
        viewerNextButton.action = #selector(nextImage)
        viewerPrevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .semibold))
        viewerPrevButton.title = ""
        viewerNextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .semibold))
        viewerNextButton.title = ""

        for button in [viewerExitButton, viewerProfileButton, viewerPrevButton, viewerNextButton] {
            button.fillColor = NSColor.black.withAlphaComponent(0.35)
            button.textColor = .white
            button.activeFillColor = Palette.accent
            button.activeTextColor = .white
            rootView.addSubview(button)
        }
        for button in [viewerPrevButton, viewerNextButton] {
            button.fillColor = NSColor.white.withAlphaComponent(0.10)
            button.activeFillColor = NSColor.white.withAlphaComponent(0.22)
        }

        rootView.addSubview(viewerTitleLabel)
        rootView.addSubview(viewerMetaLabel)
        rootView.addSubview(viewerFileLabel)
    }

    private func setupProfile() {
        profileCardView.wantsLayer = true
        profileCardView.layer?.backgroundColor = Palette.card.cgColor
        profileCardView.layer?.cornerRadius = 12
        profileCardView.layer?.shadowColor = NSColor.black.cgColor
        profileCardView.layer?.shadowOpacity = 0.08
        profileCardView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        profileCardView.layer?.shadowRadius = 10
        profileCardView.layer?.masksToBounds = false

        profileWebView.setValue(false, forKey: "drawsBackground")
        profileWebView.wantsLayer = true
        profileWebView.layer?.cornerRadius = 12
        profileWebView.layer?.masksToBounds = true
        profileWebView.layer?.backgroundColor = Palette.card.cgColor
        profileCardView.addSubview(profileWebView)
        rootView.addSubview(profileCardView)
    }

    private func setupStatusBar() {
        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = Palette.secondary
        pathLabel.font = .systemFont(ofSize: 10, weight: .medium)
        pathLabel.textColor = Palette.secondary
        pathLabel.alignment = .right
        rootView.addSubview(statusLabel)
        rootView.addSubview(pathLabel)
    }

    private func setupEmptyState() {
        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = Palette.secondary
        emptyLabel.alignment = .center
        rootView.addSubview(emptyLabel)
        rootView.addSubview(openButton)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func windowDidResize(_ notification: Notification) {
        layoutViews()
    }

    private func layoutViews() {
        guard let content = window?.contentView else { return }
        let bounds = content.bounds
        let isViewer = viewMode == .fullscreen
        let topHeight: CGFloat = isViewer ? 0 : 44
        let statusHeight: CGFloat = isViewer ? 0 : 26
        let sidebarWidth: CGFloat = viewMode == .fullscreen ? 0 : min(270, max(220, bounds.width * 0.18))
        let profileWidth = currentProfileWidth(for: bounds)
        let gap: CGFloat = 0

        topBar.frame = NSRect(x: 0, y: bounds.height - topHeight, width: bounds.width, height: topHeight)
        modeControl.frame = NSRect(x: (bounds.width - 285) / 2, y: bounds.height - 35, width: 285, height: 26)
        openButton.frame = .zero

        statusLabel.frame = NSRect(x: 14, y: 5, width: bounds.width * 0.45, height: 16)
        pathLabel.frame = NSRect(x: bounds.width * 0.48, y: 5, width: bounds.width * 0.50 - 18, height: 16)

        let contentY = statusHeight
        let contentHeight = bounds.height - topHeight - statusHeight
        let sidebarHeaderHeight: CGFloat = viewMode == .fullscreen ? 0 : 46
        libraryPathLabel.frame = NSRect(x: 16, y: contentY + contentHeight - 32, width: max(80, sidebarWidth - 62), height: 18)
        changeLibraryButton.frame = NSRect(x: max(16, sidebarWidth - 44), y: contentY + contentHeight - 38, width: 30, height: 30)
        sidebarScroll.frame = NSRect(x: 0, y: contentY, width: sidebarWidth, height: max(0, contentHeight - sidebarHeaderHeight))
        sidebarDivider.frame = NSRect(x: sidebarWidth, y: contentY, width: 1, height: contentHeight)

        let rightX = bounds.width - profileWidth
        let cardInset: CGFloat = 8
        profileCardView.frame = NSRect(
            x: rightX + cardInset,
            y: contentY + cardInset,
            width: max(0, profileWidth - cardInset * 2),
            height: max(0, contentHeight - cardInset * 2)
        )
        profileWebView.frame = profileCardView.bounds
        profileCardView.layer?.shadowPath = CGPath(roundedRect: profileCardView.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
        profileDivider.frame = profileWidth > 0 ? NSRect(x: rightX - 1, y: contentY, width: 1, height: contentHeight) : .zero

        let mainX = sidebarWidth + gap
        let mainWidth = bounds.width - sidebarWidth - profileWidth - gap
        let toolbarHeight: CGFloat = viewMode == .fullscreen ? 0 : 54
        let toolbarY = contentY + contentHeight - toolbarHeight
        toolbarStrip.frame = NSRect(x: mainX, y: toolbarY, width: max(0, mainWidth), height: toolbarHeight)

        let buttonGap: CGFloat = 6
        let buttonSide: CGFloat = 36
        let buttonsWidth = buttonSide * 3 + buttonGap * 2
        let buttonsX = mainX + mainWidth - buttonsWidth - 18
        let searchX = mainX + 24
        let searchWidth = min(240, buttonsX - searchX - 18)
        if searchWidth >= 130 {
            searchField.frame = NSRect(x: searchX, y: toolbarY + 13, width: searchWidth, height: 28)
        } else {
            searchField.frame = .zero
        }
        densityButton.frame = NSRect(x: buttonsX, y: toolbarY + 9, width: buttonSide, height: buttonSide)
        slideshowButton.frame = NSRect(x: densityButton.frame.maxX + buttonGap, y: toolbarY + 9, width: buttonSide, height: buttonSide)
        profileButton.frame = NSRect(x: slideshowButton.frame.maxX + buttonGap, y: toolbarY + 9, width: buttonSide, height: buttonSide)

        let mainFrame = NSRect(x: mainX, y: contentY, width: mainWidth, height: contentHeight)
        switch viewMode {
        case .split:
            collectionScroll.frame = NSRect(x: mainFrame.minX, y: mainFrame.minY, width: mainFrame.width, height: mainFrame.height - toolbarHeight)
            previewImageView.frame = .zero
        case .tabbed:
            let showingProfileTab = modeControl.selectedSegment == ViewMode.tabbed.rawValue && profileVisible
            collectionScroll.frame = showingProfileTab ? .zero : mainFrame
            if showingProfileTab {
                profileCardView.frame = mainFrame.insetBy(dx: cardInset, dy: cardInset)
                profileWebView.frame = profileCardView.bounds
                profileCardView.layer?.shadowPath = CGPath(roundedRect: profileCardView.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
            } else if viewMode == .tabbed {
                profileCardView.frame = .zero
                profileWebView.frame = .zero
            }
            previewImageView.frame = .zero
        case .fullscreen:
            previewImageView.frame = mainFrame.insetBy(dx: 36, dy: 64)
            collectionScroll.frame = .zero
        }

        layoutViewerOverlay(bounds: bounds, profileWidth: profileWidth)
        emptyLabel.frame = NSRect(x: mainX + 20, y: contentY + contentHeight / 2 + 8, width: max(260, mainWidth - 40), height: 40)
        if !emptyLabel.isHidden {
            openButton.frame = NSRect(x: bounds.midX - 72, y: contentY + contentHeight / 2 - 34, width: 144, height: 32)
        }
    }

    private func currentProfileWidth(for bounds: NSRect) -> CGFloat {
        if viewMode == .fullscreen {
            return viewerProfileVisible ? min(380, max(320, bounds.width * 0.28)) : 0
        }
        return (profileVisible && viewMode != .tabbed) ? min(360, max(300, bounds.width * 0.25)) : 0
    }

    private func layoutViewerOverlay(bounds: NSRect, profileWidth: CGFloat) {
        let isViewer = viewMode == .fullscreen
        let viewerWidth = bounds.width - profileWidth
        viewerTopBar.frame = isViewer ? NSRect(x: 0, y: bounds.height - 56, width: viewerWidth, height: 56) : .zero
        viewerBottomBar.frame = isViewer ? NSRect(x: 0, y: 0, width: viewerWidth, height: 46) : .zero
        viewerTopGradient.frame = viewerTopBar.bounds
        viewerBottomGradient.frame = viewerBottomBar.bounds
        viewerTitleLabel.frame = isViewer ? NSRect(x: 28, y: bounds.height - 32, width: max(160, viewerWidth * 0.40), height: 18) : .zero
        viewerMetaLabel.frame = isViewer ? NSRect(x: 28, y: bounds.height - 49, width: max(160, viewerWidth * 0.40), height: 14) : .zero

        viewerExitButton.frame = isViewer ? NSRect(x: viewerWidth - 80, y: bounds.height - 42, width: 56, height: 30) : .zero
        viewerProfileButton.frame = isViewer ? NSRect(x: viewerWidth - 176, y: bounds.height - 42, width: 84, height: 30) : .zero
        viewerPrevButton.frame = isViewer ? NSRect(x: 36, y: bounds.midY - 24, width: 48, height: 48) : .zero
        viewerNextButton.frame = isViewer ? NSRect(x: viewerWidth - 84, y: bounds.midY - 24, width: 48, height: 48) : .zero
        viewerFileLabel.frame = isViewer ? NSRect(x: 120, y: 14, width: max(180, viewerWidth - 240), height: 18) : .zero
    }

    private func currentModel() -> ModelFolder? {
        guard models.indices.contains(selectedModelIndex) else { return nil }
        return models[selectedModelIndex]
    }

    private func currentImage() -> ImageAsset? {
        guard filteredImages.indices.contains(selectedImageIndex) else { return nil }
        return filteredImages[selectedImageIndex]
    }

    @objc func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Library Folder"
        panel.message = "Select the root folder that contains model folders and profile.md files."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = browserRoot?.url
        panel.prompt = "Use Folder"

        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.openArchive(url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            openArchive(url)
        }
    }

    private func openArchive(_ url: URL, resetBrowser: Bool = true) {
        sidebarSubtitleCache.removeAll()
        searchDebounceWorkItem?.cancel()
        searchDebounceWorkItem = nil

        let rootURL = url.standardizedFileURL
        if resetBrowser {
            browserRoot = FolderNode(url: rootURL)
            browserRoot?.loadChildren()
            suppressBrowserSelection = true
            sidebar.reloadData()
            if let browserRoot {
                sidebar.expandItem(browserRoot)
            }
            suppressBrowserSelection = false
        }

        let scannedModels = store.scan(rootURL)
        let displayURL = resetBrowser ? (scannedModels.first?.url ?? rootURL) : rootURL
        models = displayURL == rootURL ? scannedModels : store.scan(displayURL)
        selectedModelIndex = 0
        selectBrowserURL(displayURL)
        loadSelectedModel()
        updateContentVisibility()
        libraryPathLabel.stringValue = rootURL.lastPathComponent
        window?.title = "Arkiv — \(rootURL.lastPathComponent)"
    }

    private func selectBrowserURL(_ url: URL) {
        guard let browserRoot else { return }
        browserRoot.loadChildren()
        guard let node = findBrowserNode(url.standardizedFileURL, in: browserRoot) else { return }
        var parent = node.parent
        while let currentParent = parent {
            sidebar.expandItem(currentParent)
            parent = currentParent.parent
        }
        let row = sidebar.row(forItem: node)
        guard row >= 0 else { return }
        suppressBrowserSelection = true
        sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressBrowserSelection = false
    }

    private func findBrowserNode(_ url: URL, in node: FolderNode) -> FolderNode? {
        if node.url == url {
            return node
        }
        guard isAncestorOrSame(node.url, of: url) else {
            return nil
        }
        node.loadChildren()
        for child in node.children {
            guard isAncestorOrSame(child.url, of: url) else { continue }
            if let match = findBrowserNode(url, in: child) {
                return match
            }
        }
        return nil
    }

    private func isAncestorOrSame(_ ancestor: URL, of url: URL) -> Bool {
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard ancestorComponents.count <= urlComponents.count else { return false }
        return zip(ancestorComponents, urlComponents).allSatisfy(==)
    }

    private func loadSelectedModel() {
        searchField.stringValue = ""
        filteredImages = currentModel()?.images ?? []
        selectedImageIndex = 0
        collectionView.reloadData()
        if !filteredImages.isEmpty {
            collectionView.selectItems(at: Set([IndexPath(item: 0, section: 0)]), scrollPosition: .top)
            ImageCache.shared.warm(Array(filteredImages.prefix(36).map(\.url)), side: density.itemSide)
        }
        window?.makeFirstResponder(nil)
        loadProfile()
        loadPreview()
        updateStatus()
        emptyLabel.isHidden = !models.isEmpty
    }

    private func loadProfile() {
        guard let model = currentModel() else {
            profileWebView.loadHTMLString(MarkdownHTMLRenderer.render(""), baseURL: nil)
            return
        }

        guard let profileURL = model.profileURL,
              let markdown = try? String(contentsOf: profileURL, encoding: .utf8) else {
            let fallback = "# \(model.name)\n\nNo profile.md found in this folder."
            profileWebView.loadHTMLString(MarkdownHTMLRenderer.render(fallback), baseURL: model.url)
            return
        }

        profileWebView.loadHTMLString(MarkdownHTMLRenderer.render(markdown), baseURL: profileURL.deletingLastPathComponent())
    }

    private func loadPreview() {
        guard viewMode == .fullscreen, let image = currentImage() else {
            if viewMode != .fullscreen {
                previewImageView.image = nil
            }
            return
        }

        previewImageView.image = nil
        ImageCache.shared.preview(for: image.url) { [weak self] nsImage in
            guard let self, self.currentImage()?.url == image.url else { return }
            self.previewImageView.image = nsImage
        }
    }

    private func updateStatus() {
        let modelName = currentModel()?.name ?? "No archive"
        let selected = filteredImages.isEmpty ? 0 : selectedImageIndex + 1
        let totalBytes = filteredImages.reduce(Int64(0)) { $0 + $1.byteCount }
        statusLabel.stringValue = "\(modelName)  ·  \(selected) of \(filteredImages.count)"
        pathLabel.stringValue = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        updateViewerLabels()
    }

    private func updateModeButtons() {
        modeControl.selectedSegment = viewMode.rawValue
        profileButton.isActive = profileVisible
        viewerProfileButton.isActive = viewerProfileVisible
        slideshowButton.isActive = slideshowTimer != nil
        densityButton.image = NSImage(systemSymbolName: densitySymbolName, accessibilityDescription: "Grid density")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        densityButton.needsDisplay = true
        slideshowButton.needsDisplay = true
        profileButton.needsDisplay = true
        viewerProfileButton.needsDisplay = true
        updateViewerLabels()
    }

    private var densitySymbolName: String {
        switch density {
        case .compact:
            return "square.grid.3x3"
        case .comfortable:
            return "square.grid.2x2"
        case .spacious:
            return "square.grid.3x3.fill"
        }
    }

    private func updateContentVisibility() {
        let hasArchive = !models.isEmpty
        let isViewer = viewMode == .fullscreen
        sidebarScroll.isHidden = !hasArchive || isViewer
        libraryPathLabel.isHidden = !hasArchive || isViewer
        changeLibraryButton.isHidden = !hasArchive || isViewer
        collectionScroll.isHidden = !hasArchive || isViewer || (viewMode == .tabbed && profileVisible)
        previewImageView.isHidden = !hasArchive || !isViewer
        profileCardView.isHidden = !hasArchive || (isViewer ? !viewerProfileVisible : (!profileVisible && viewMode != .tabbed))
        toolbarStrip.isHidden = !hasArchive || isViewer
        searchField.isHidden = !hasArchive || isViewer || (viewMode == .tabbed && profileVisible)
        densityButton.isHidden = searchField.isHidden
        slideshowButton.isHidden = !hasArchive || isViewer || (viewMode == .tabbed && profileVisible)
        profileButton.isHidden = !hasArchive || isViewer
        let profileWidth = window?.contentView.map { currentProfileWidth(for: $0.bounds) } ?? 0
        sidebarDivider.isHidden = !hasArchive || isViewer
        profileDivider.isHidden = !hasArchive || isViewer || profileWidth == 0
        topBar.isHidden = isViewer
        modeControl.isHidden = isViewer
        openButton.isHidden = hasArchive || isViewer
        statusLabel.isHidden = isViewer
        pathLabel.isHidden = isViewer
        for view in [viewerTopBar, viewerBottomBar, viewerTitleLabel, viewerMetaLabel, viewerFileLabel, viewerExitButton, viewerProfileButton, viewerPrevButton, viewerNextButton] {
            view.isHidden = !hasArchive || !isViewer
        }
        emptyLabel.isHidden = hasArchive
        rootView.color = isViewer ? Palette.dark : Palette.bg
        layoutViews()
    }

    @objc private func modeChanged() {
        viewMode = ViewMode(rawValue: modeControl.selectedSegment) ?? .split
        if viewMode == .tabbed {
            profileVisible = false
        }
        if viewMode == .fullscreen {
            openViewer(at: selectedImageIndex)
            return
        }
        updateModeButtons()
        updateContentVisibility()
    }

    @objc private func toggleDensity() {
        density = density.next
        if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            layout.itemSize = NSSize(width: density.itemSide, height: density.itemSide + 28)
            layout.invalidateLayout()
        }
        collectionView.reloadData()
        updateModeButtons()
    }

    @objc private func toggleProfile() {
        if viewMode == .tabbed {
            profileVisible.toggle()
        } else {
            profileVisible.toggle()
        }
        updateModeButtons()
        updateContentVisibility()
    }

    @objc private func toggleViewerProfile() {
        viewerProfileVisible.toggle()
        updateModeButtons()
        updateContentVisibility()
    }

    @objc private func exitViewer() {
        stopSlideshow()
        viewMode = .split
        viewerProfileVisible = false
        updateModeButtons()
        updateContentVisibility()
        loadPreview()
        window?.makeFirstResponder(nil)
    }

    @objc private func previousImage() {
        advanceImage(-1)
    }

    @objc private func nextImage() {
        advanceImage(1)
    }

    @objc private func toggleSlideshow() {
        if slideshowTimer == nil {
            openViewer(at: selectedImageIndex)
            slideshowButton.title = "Stop"
            slideshowButton.isActive = true
            slideshowTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: true) { [weak self] _ in
                self?.advanceImage(1)
            }
        } else {
            stopSlideshow()
        }
    }

    private func stopSlideshow() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
        slideshowButton.title = "Slideshow"
        slideshowButton.isActive = false
        slideshowButton.needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applySearch(query)
        }
        searchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func applySearch(_ query: String) {
        let images = currentModel()?.images ?? []
        if query.isEmpty {
            filteredImages = images
        } else {
            filteredImages = images.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
        }
        selectedImageIndex = 0
        collectionView.reloadData()
        if !filteredImages.isEmpty {
            collectionView.selectItems(at: Set([IndexPath(item: 0, section: 0)]), scrollPosition: .top)
        }
        updateStatus()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredImages.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ImageCollectionItem.identifier, for: indexPath)
        guard let imageItem = item as? ImageCollectionItem else { return item }
        imageItem.configure(asset: filteredImages[indexPath.item], index: indexPath.item, side: density.itemSide, isCurrent: indexPath.item == selectedImageIndex)
        return imageItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !suppressCollectionSelectionHandler else { return }
        guard let indexPath = indexPaths.first else { return }
        selectedImageIndex = indexPath.item
        collectionView.reloadData()
        updateStatus()
    }

    func openCollectionItem(at indexPath: IndexPath) {
        openViewer(at: indexPath.item)
    }

    private func openViewer(at index: Int, showProfile: Bool = false) {
        guard filteredImages.indices.contains(index) else { return }
        selectedImageIndex = index
        viewMode = .fullscreen
        viewerProfileVisible = showProfile
        updateModeButtons()
        updateContentVisibility()
        loadPreview()
        updateStatus()
        window?.makeFirstResponder(collectionView)
    }

    private func updateViewerLabels() {
        guard let model = currentModel(), currentImage() != nil else {
            viewerTitleLabel.stringValue = ""
            viewerMetaLabel.stringValue = ""
            viewerFileLabel.stringValue = ""
            return
        }
        viewerTitleLabel.stringValue = model.name
        viewerMetaLabel.stringValue = "\(selectedImageIndex + 1) of \(filteredImages.count)"
        viewerFileLabel.stringValue = "\(selectedImageIndex + 1)  /  \(filteredImages.count)"
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return browserRoot == nil ? 0 : 1
        }
        let node = item as? FolderNode
        node?.loadChildren()
        return node?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return browserRoot!
        }
        let node = item as? FolderNode
        node?.loadChildren()
        return node?.children[index] as Any
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FolderNode else { return false }
        node.loadChildren()
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SidebarItem")
        let view = outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarItemView ?? SidebarItemView()
        view.identifier = identifier
        guard let node = item as? FolderNode else { return view }
        view.nameLabel.stringValue = node.name
        view.subtitleLabel.stringValue = folderSubtitle(for: node.url)
        view.isHighlighted = outlineView.row(forItem: item) == outlineView.selectedRow
        return view
    }

    private func folderSubtitle(for url: URL) -> String {
        let url = url.standardizedFileURL
        if let model = models.first(where: { $0.url == url }) {
            let subtitle = "\(model.images.count) images" + (model.profileURL != nil ? " · profile.md" : "")
            sidebarSubtitleCache[url] = subtitle
            return subtitle
        }

        if let cached = sidebarSubtitleCache[url] {
            return cached
        }

        let profileExists = FileManager.default.fileExists(atPath: url.appendingPathComponent("profile.md").path)
        let subtitle = profileExists ? "profile.md" : "folder"
        sidebarSubtitleCache[url] = subtitle
        return subtitle
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressBrowserSelection else { return }
        let row = sidebar.selectedRow
        guard row >= 0, let node = sidebar.item(atRow: row) as? FolderNode else { return }
        openArchive(node.url, resetBrowser: false)
        sidebar.reloadData()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if isSearchEditing() {
            return false
        }

        switch event.keyCode {
        case KeyCode.leftArrow:
            advanceImage(-1)
            return true
        case KeyCode.rightArrow, KeyCode.space:
            advanceImage(1)
            return true
        case KeyCode.home:
            jumpToImage(0)
            return true
        case KeyCode.end:
            jumpToImage(max(0, filteredImages.count - 1))
            return true
        case KeyCode.escape:
            if slideshowTimer != nil {
                stopSlideshow()
                return true
            }
            if viewMode == .fullscreen {
                exitViewer()
                return true
            }
        case KeyCode.return_:
            if viewMode != .fullscreen {
                openViewer(at: selectedImageIndex)
                return true
            }
        default:
            return false
        }
        return false
    }

    private func isSearchEditing() -> Bool {
        guard let editor = searchField.currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    private func advanceImage(_ delta: Int) {
        guard !filteredImages.isEmpty else { return }
        let previousImageIndex = selectedImageIndex
        selectedImageIndex = (selectedImageIndex + delta + filteredImages.count) % filteredImages.count
        syncImageSelectionAfterKeyboardMove(previousImageIndex: previousImageIndex)
    }

    private func jumpToImage(_ index: Int) {
        guard filteredImages.indices.contains(index) else { return }
        let previousImageIndex = selectedImageIndex
        selectedImageIndex = index
        syncImageSelectionAfterKeyboardMove(previousImageIndex: previousImageIndex)
    }

    private func syncImageSelectionAfterKeyboardMove(previousImageIndex: Int) {
        if viewMode == .fullscreen {
            loadPreview()
        } else {
            suppressCollectionSelectionHandler = true
            collectionView.selectItems(at: Set([IndexPath(item: selectedImageIndex, section: 0)]), scrollPosition: .centeredVertically)
            suppressCollectionSelectionHandler = false
            let reloadIndexPaths = [previousImageIndex, selectedImageIndex]
                .filter { filteredImages.indices.contains($0) }
                .map { IndexPath(item: $0, section: 0) }
            collectionView.reloadItems(at: Set(reloadIndexPaths))
        }
        updateStatus()
    }
}
