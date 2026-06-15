import AppKit
import WebKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    private static let recentLibrariesKey = "RecentLibraries"
    private static let lastLibraryKey = "LastLibraryPath"
    private static let ratingValues = ["--", "-+", "=", "+", "++", "+++"]
    static var recentLibraryURLs: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: recentLibrariesKey) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    private let store = ArchiveStore()
    private var browserRoot: FolderNode?
    private var suppressBrowserSelection = false
    private var keyMonitor: Any?
    private var models: [ModelFolder] = []
    private var filteredImages: [ImageAsset] = []
    private var selectedModelIndex = 0
    private var selectedImageIndex = 0
    private var selectedImageIndexes: Set<Int> = []
    private var viewMode: ViewMode = .grid
    private var density: Density = .spacious
    private var profileVisible = true
    private var viewerProfileVisible = false
    private var slideshowTimer: Timer?
    private var sidebarSubtitleCache: [URL: String] = [:]
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var suppressCollectionSelectionHandler = false
    private let scanQueue = DispatchQueue(label: "com.arkiv.scan", qos: .userInitiated)
    private var scanGeneration = 0
    private var isScanning = false
    private var archiveMessage: String?
    private var currentLibraryURL: URL?
    private var pendingOpenViewerAfterScan = false
    private var pendingViewerProfileAfterScan = false

    private let rootView = BackgroundView()
    private let topBar = NSVisualEffectView()
    private let modeControl = NSSegmentedControl(labels: ["Grid", "Profile", "Viewer"], trackingMode: .selectOne, target: nil, action: nil)
    private let openButton = RoundedButton(title: "Choose Library", target: nil, action: nil)
    private let densityButton = IconButton(symbol: "square.grid.3x3.fill", tooltip: "Grid density")
    private let slideshowButton = IconButton(symbol: "play.fill", tooltip: "Slideshow")
    private let profileButton = IconButton(symbol: "text.alignleft", tooltip: "Profile")
    private let searchField = NSSearchField()
    private let sidebar = FolderOutlineView()
    private let sidebarScroll = NSScrollView()
    private let sidebarDivider = NSView()
    private let libraryPathLabel = NSTextField(labelWithString: "No folder selected")
    private let changeLibraryButton = NSButton()
    private let toolbarStrip = BackgroundView()
    private let contextNameLabel = NSTextField(labelWithString: "")
    private let contextCountLabel = NSTextField(labelWithString: "")
    private lazy var ratingControl = NSSegmentedControl(labels: Self.ratingValues, trackingMode: .selectOne, target: nil, action: nil)
    private let sendToCorpusButton = RoundedButton(title: "Send to Corpus", target: nil, action: nil)
    private let collectionView = DoubleClickCollectionView()
    private let collectionScroll = NSScrollView()
    private let previewScrollView = NSScrollView()
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
    private let homeStateView = HomeStateView()
    private let emptyLabel = NSTextField(labelWithString: "Open or drop an archive folder to begin.")
    private let loadingIndicator = NSProgressIndicator()

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
        rootView.onFolderDrop = { [weak self] url in
            self?.openArchive(url)
        }
        rootView.onAppearanceChange = { [weak self] in
            self?.updateDynamicColors()
        }
        window.contentView = rootView

        setupTopBar()
        setupSidebar()
        setupDividers()
        setupToolbarStrip()
        setupCollection()
        setupPreview()
        setupViewerOverlay()
        setupProfile()
        setupEmptyState()
        layoutViews()
        updateModeButtons()
        updateContentVisibility()
        installKeyMonitor()
        updateDynamicColors()

        let arguments = Array(CommandLine.arguments.dropFirst())
        let shouldOpenViewer = arguments.contains("--viewer")
        let shouldOpenViewerProfile = arguments.contains("--viewer-profile")
        let shouldSkipRestore = arguments.contains("--no-restore")
        if let argument = arguments.first(where: { !$0.hasPrefix("--") }) {
            pendingOpenViewerAfterScan = shouldOpenViewer
            pendingViewerProfileAfterScan = shouldOpenViewerProfile
            openArchive(URL(fileURLWithPath: argument))
        } else if !shouldSkipRestore, let lastPath = UserDefaults.standard.string(forKey: Self.lastLibraryKey) {
            openArchive(URL(fileURLWithPath: lastPath))
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
        sidebar.rowHeight = 32
        sidebar.intercellSpacing = NSSize(width: 0, height: 0)
        sidebar.backgroundColor = .clear
        sidebar.selectionHighlightStyle = .none
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.contextMenuProvider = { [weak self] row in
            self?.menuForSidebarRow(row)
        }
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
        toolbarStrip.color = Palette.bg
        contextNameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        contextNameLabel.textColor = Palette.text
        contextNameLabel.lineBreakMode = .byTruncatingTail
        contextCountLabel.font = .systemFont(ofSize: 12, weight: .regular)
        contextCountLabel.textColor = Palette.tertiary

        ratingControl.target = self
        ratingControl.action = #selector(ratingChanged)
        ratingControl.segmentStyle = .rounded
        ratingControl.font = .systemFont(ofSize: 12, weight: .medium)
        ratingControl.toolTip = "Rate current folder"
        ratingControl.setAccessibilityLabel("Rating")
        for index in Self.ratingValues.indices {
            ratingControl.setToolTip("Rate \(Self.ratingValues[index])", forSegment: index)
        }

        sendToCorpusButton.target = self
        sendToCorpusButton.action = #selector(showSendToCorpusMenu(_:))
        sendToCorpusButton.fillColor = Palette.accent
        sendToCorpusButton.textColor = .white
        sendToCorpusButton.activeFillColor = Palette.accent
        sendToCorpusButton.activeTextColor = .white
        sendToCorpusButton.toolTip = "Choose how to send selected images to CorpusVault"
        sendToCorpusButton.setAccessibilityLabel("Send selected images to CorpusVault")

        toolbarStrip.addSubview(contextNameLabel)
        toolbarStrip.addSubview(contextCountLabel)
        toolbarStrip.addSubview(ratingControl)
        rootView.addSubview(toolbarStrip, positioned: .below, relativeTo: searchField)
        rootView.addSubview(sendToCorpusButton)
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
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.menuForImage(at: indexPath)
        }
        collectionView.itemClickHandler = { [weak self] indexPath, commandPressed in
            self?.collectionClicked(indexPath: indexPath, commandPressed: commandPressed)
        }
        collectionView.itemDoubleClickHandler = { [weak self] indexPath in
            self?.openCollectionItem(at: indexPath)
        }
        collectionView.dragSelectionHandler = { [weak self] indexPaths in
            self?.collectionDragSelected(indexPaths: indexPaths)
        }
        collectionView.isSelectable = false
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [Palette.bg]
        collectionView.allowsEmptySelection = true
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
        previewImageView.menu = makeImageContextMenu()

        previewScrollView.documentView = previewImageView
        previewScrollView.allowsMagnification = true
        previewScrollView.minMagnification = 0.2
        previewScrollView.maxMagnification = 20.0
        previewScrollView.drawsBackground = false
        previewScrollView.hasVerticalScroller = false
        previewScrollView.hasHorizontalScroller = false
        rootView.addSubview(previewScrollView)
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
        viewerPrevButton.setAccessibilityLabel("Previous image")
        viewerNextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .semibold))
        viewerNextButton.title = ""
        viewerNextButton.setAccessibilityLabel("Next image")
        viewerExitButton.setAccessibilityLabel("Exit viewer")
        viewerProfileButton.setAccessibilityLabel("Profile")

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

    private func setupEmptyState() {
        homeStateView.onOpenFolder = { [weak self] in
            self?.openFolder()
        }
        homeStateView.onOpenRecent = { [weak self] url in
            self?.openArchive(url)
        }
        rootView.addSubview(homeStateView)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func updateDynamicColors() {
        rootView.color = viewMode == .viewer ? Palette.dark : Palette.bg
        collectionView.backgroundColors = [Palette.bg]
        previewImageView.layer?.backgroundColor = Palette.dark.cgColor
        previewScrollView.backgroundColor = Palette.dark
        profileCardView.layer?.backgroundColor = Palette.card.cgColor
        profileWebView.layer?.backgroundColor = Palette.card.cgColor
        for divider in [sidebarDivider, profileDivider] {
            divider.layer?.backgroundColor = Palette.border.cgColor
        }
        contextNameLabel.textColor = Palette.text
        contextCountLabel.textColor = Palette.tertiary
        libraryPathLabel.textColor = Palette.secondary
        emptyLabel.textColor = Palette.secondary
        openButton.fillColor = Palette.accent
        sendToCorpusButton.fillColor = Palette.accent
        sendToCorpusButton.textColor = .white
        homeStateView.refreshColors()
        collectionView.reloadData()
        sidebar.reloadData()
        rootView.needsDisplay = true
    }

    func windowDidResize(_ notification: Notification) {
        layoutViews()
    }

    private func layoutViews() {
        guard let content = window?.contentView else { return }
        let bounds = content.bounds
        let isViewer = viewMode == .viewer
        let topHeight: CGFloat = isViewer ? 0 : 44
        let statusHeight: CGFloat = 0
        let sidebarWidth: CGFloat = viewMode == .viewer ? 0 : min(240, max(180, bounds.width * 0.17))
        let profileWidth = currentProfileWidth(for: bounds)
        let gap: CGFloat = 0

        topBar.frame = NSRect(x: 0, y: bounds.height - topHeight, width: bounds.width, height: topHeight)
        modeControl.frame = NSRect(x: (bounds.width - 285) / 2, y: bounds.height - 35, width: 285, height: 26)
        openButton.frame = .zero

        let contentY = statusHeight
        let contentHeight = bounds.height - topHeight - statusHeight
        let sidebarHeaderHeight: CGFloat = viewMode == .viewer ? 0 : 46
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
        let toolbarHeight: CGFloat = viewMode == .viewer ? 0 : 52
        let toolbarY = contentY + contentHeight - toolbarHeight
        toolbarStrip.frame = NSRect(x: mainX, y: toolbarY, width: max(0, mainWidth), height: toolbarHeight)

        let buttonGap: CGFloat = 6
        let buttonSide: CGFloat = 36
        let sendWidth: CGFloat = mainWidth < 680 ? 0 : 148
        let buttonsWidth = buttonSide * 3 + buttonGap * 2 + (sendWidth > 0 ? sendWidth + 10 : 0)
        let buttonsX = mainX + mainWidth - buttonsWidth - 18

        let ratingWidth: CGFloat = mainWidth < 620 ? 226 : 252
        let ratingMaxX = mainWidth - buttonsWidth - 30
        let ratingX = max(20, min(232, ratingMaxX - ratingWidth))
        ratingControl.frame = NSRect(x: ratingX, y: 12, width: max(0, ratingWidth), height: 28)

        let labelWidth = max(0, ratingX - 32)
        contextNameLabel.frame = NSRect(x: 20, y: 17, width: labelWidth, height: 18)
        contextCountLabel.frame = NSRect(x: 20, y: 5, width: labelWidth, height: 14)

        let searchMinWidth: CGFloat = 130
        let searchGap: CGFloat = 12
        let searchX = mainX + ratingControl.frame.maxX + searchGap
        let searchMaxWidth = buttonsX - searchX - searchGap
        let searchWidth = min(220, searchMaxWidth)
        if searchWidth >= searchMinWidth {
            searchField.frame = NSRect(x: searchX, y: toolbarY + 12, width: searchWidth, height: 28)
        } else {
            searchField.frame = .zero
        }
        if sendWidth > 0 {
            sendToCorpusButton.frame = NSRect(x: buttonsX, y: toolbarY + 8, width: sendWidth, height: buttonSide)
            sendToCorpusButton.isHidden = toolbarStrip.isHidden
        } else {
            sendToCorpusButton.frame = .zero
            sendToCorpusButton.isHidden = true
        }
        let iconButtonsX = buttonsX + (sendWidth > 0 ? sendWidth + 10 : 0)
        densityButton.frame = NSRect(x: iconButtonsX, y: toolbarY + 8, width: buttonSide, height: buttonSide)
        slideshowButton.frame = NSRect(x: densityButton.frame.maxX + buttonGap, y: toolbarY + 8, width: buttonSide, height: buttonSide)
        profileButton.frame = NSRect(x: slideshowButton.frame.maxX + buttonGap, y: toolbarY + 8, width: buttonSide, height: buttonSide)

        let mainFrame = NSRect(x: mainX, y: contentY, width: mainWidth, height: contentHeight)
        switch viewMode {
        case .grid:
            collectionScroll.frame = NSRect(x: mainFrame.minX, y: mainFrame.minY, width: mainFrame.width, height: mainFrame.height - toolbarHeight)
            previewScrollView.frame = .zero
        case .profile:
            let showingProfileTab = modeControl.selectedSegment == ViewMode.profile.rawValue && profileVisible
            collectionScroll.frame = showingProfileTab ? .zero : mainFrame
            if showingProfileTab {
                profileCardView.frame = mainFrame.insetBy(dx: cardInset, dy: cardInset)
                profileWebView.frame = profileCardView.bounds
                profileCardView.layer?.shadowPath = CGPath(roundedRect: profileCardView.bounds, cornerWidth: 12, cornerHeight: 12, transform: nil)
            } else if viewMode == .profile {
                profileCardView.frame = .zero
                profileWebView.frame = .zero
            }
            previewScrollView.frame = .zero
        case .viewer:
            previewScrollView.frame = mainFrame
            previewImageView.frame = NSRect(origin: .zero, size: mainFrame.size)
            collectionScroll.frame = .zero
        }

        layoutViewerOverlay(bounds: bounds, profileWidth: profileWidth)
        if !homeStateView.isHidden {
            if hasHomeOverlayAcrossWindow {
                homeStateView.frame = NSRect(x: 0, y: contentY, width: bounds.width, height: contentHeight)
            } else {
                homeStateView.frame = NSRect(x: mainX, y: contentY, width: mainWidth, height: max(0, contentHeight - toolbarHeight))
            }
        }
    }

    private var hasHomeOverlayAcrossWindow: Bool {
        models.isEmpty || isScanning
    }

    private func currentProfileWidth(for bounds: NSRect) -> CGFloat {
        if viewMode == .viewer {
            return viewerProfileVisible ? min(460, max(380, bounds.width * 0.30)) : 0
        }
        return (profileVisible && viewMode != .profile) ? min(500, max(420, bounds.width * 0.30)) : 0
    }

    private func layoutViewerOverlay(bounds: NSRect, profileWidth: CGFloat) {
        let isViewer = viewMode == .viewer
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
        currentLibraryURL = rootURL
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        archiveMessage = "Scanning \(rootURL.lastPathComponent)..."
        updateContentVisibility()

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

        libraryPathLabel.stringValue = rootURL.lastPathComponent
        window?.title = rootURL.lastPathComponent
        window?.representedURL = rootURL

        scanQueue.async { [weak self] in
            guard let self else { return }
            let rootModels = self.store.scan(rootURL)
            let displayURL = resetBrowser ? (rootModels.first?.url ?? rootURL) : rootURL
            let displayModels = displayURL == rootURL ? rootModels : self.store.scan(displayURL)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                self.finishOpeningArchive(rootURL: rootURL, displayURL: displayURL, models: displayModels)
            }
        }
    }

    private func finishOpeningArchive(rootURL: URL, displayURL: URL, models scannedModels: [ModelFolder]) {
        isScanning = false
        models = scannedModels
        selectedModelIndex = 0
        archiveMessage = models.isEmpty ? "No images found in \(rootURL.lastPathComponent)." : nil
        if !models.isEmpty {
            noteRecentLibrary(rootURL)
            selectBrowserURL(displayURL)
            loadSelectedModel()
            if pendingOpenViewerAfterScan {
                pendingOpenViewerAfterScan = false
                openViewer(at: selectedImageIndex, showProfile: pendingViewerProfileAfterScan)
                pendingViewerProfileAfterScan = false
            }
        } else {
            filteredImages = []
            selectedImageIndex = 0
            collectionView.reloadData()
            loadProfile()
            updateStatus()
        }
        updateContentVisibility()
    }

    private func noteRecentLibrary(_ url: URL) {
        let path = url.path
        var paths = UserDefaults.standard.stringArray(forKey: Self.recentLibrariesKey) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > 10 {
            paths = Array(paths.prefix(10))
        }
        UserDefaults.standard.set(paths, forKey: Self.recentLibrariesKey)
        UserDefaults.standard.set(path, forKey: Self.lastLibraryKey)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
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
        selectedImageIndexes = filteredImages.isEmpty ? [] : [0]
        collectionView.reloadData()
        if !filteredImages.isEmpty {
            syncCollectionSelection()
            collectionView.scrollToItems(at: Set([IndexPath(item: 0, section: 0)]), scrollPosition: .top)
            ImageCache.shared.warm(Array(filteredImages.prefix(36).map(\.url)), side: density.itemSide)
        }
        window?.makeFirstResponder(nil)
        loadProfile()
        loadPreview()
        updateStatus()
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
        guard viewMode == .viewer, let image = currentImage() else {
            if viewMode != .viewer {
                previewImageView.image = nil
            }
            return
        }

        previewScrollView.magnification = 1.0
        previewImageView.image = nil
        ImageCache.shared.preview(for: image.url) { [weak self] nsImage in
            guard let self, self.currentImage()?.url == image.url else { return }
            self.previewImageView.image = nsImage
        }
    }

    private func updateStatus() {
        contextNameLabel.stringValue = currentModel()?.name ?? ""
        let count = filteredImages.count
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let total = currentModel()?.images.count ?? 0
            contextCountLabel.stringValue = count == 0 ? "No matches" : "\(count) of \(total) images"
        } else {
            let selectedCount = selectedImageIndexes.count
            if selectedCount > 1 {
                contextCountLabel.stringValue = "\(selectedCount) selected · \(count) images"
            } else {
                contextCountLabel.stringValue = count == 0 ? "No images" : "\(count) images"
            }
        }
        updateSendToCorpusButton()
        updateViewerLabels()
        updateRatingControl()
        updateContentVisibility()
    }

    private func updateSendToCorpusButton() {
        let count = selectedImageIndexes.filter { filteredImages.indices.contains($0) }.count
        sendToCorpusButton.isEnabled = count > 0
        sendToCorpusButton.alphaValue = count > 0 ? 1 : 0.45
        sendToCorpusButton.title = count > 1 ? "Send \(count) to Corpus" : "Send to Corpus"
        sendToCorpusButton.needsDisplay = true
    }

    private func updateModeButtons() {
        modeControl.selectedSegment = viewMode.rawValue
        profileButton.isActive = profileVisible
        viewerProfileButton.isActive = viewerProfileVisible
        slideshowButton.isActive = slideshowTimer != nil
        densityButton.image = NSImage(systemSymbolName: densitySymbolName, accessibilityDescription: "Grid density")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        densityButton.toolTip = "Grid density: \(density.title)"
        densityButton.setAccessibilityLabel("Grid density")
        densityButton.setAccessibilityValue(density.title)
        slideshowButton.image = NSImage(systemSymbolName: slideshowTimer == nil ? "play.fill" : "pause.fill", accessibilityDescription: "Slideshow")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        slideshowButton.toolTip = slideshowTimer == nil ? "Start slideshow" : "Pause slideshow"
        slideshowButton.setAccessibilityLabel("Slideshow")
        slideshowButton.setAccessibilityValue(slideshowTimer == nil ? "stopped" : "running")
        profileButton.setAccessibilityLabel("Profile")
        profileButton.setAccessibilityValue(profileVisible ? "visible" : "hidden")
        viewerProfileButton.setAccessibilityLabel("Profile")
        viewerProfileButton.setAccessibilityValue(viewerProfileVisible ? "visible" : "hidden")
        densityButton.needsDisplay = true
        slideshowButton.needsDisplay = true
        profileButton.needsDisplay = true
        viewerProfileButton.needsDisplay = true
        updateViewerLabels()
        updateRatingControl()
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
        let isViewer = viewMode == .viewer
        sidebarScroll.isHidden = !hasArchive || isViewer || isScanning
        libraryPathLabel.isHidden = !hasArchive || isViewer || isScanning
        changeLibraryButton.isHidden = !hasArchive || isViewer || isScanning
        collectionScroll.isHidden = !hasArchive || isViewer || isScanning || (viewMode == .profile && profileVisible)
        previewScrollView.isHidden = !hasArchive || !isViewer
        profileCardView.isHidden = !hasArchive || isScanning || (isViewer ? !viewerProfileVisible : (!profileVisible && viewMode != .profile))
        toolbarStrip.isHidden = !hasArchive || isViewer || isScanning
        contextNameLabel.isHidden = toolbarStrip.isHidden
        contextCountLabel.isHidden = toolbarStrip.isHidden
        ratingControl.isHidden = toolbarStrip.isHidden
        if sendToCorpusButton.frame.isEmpty {
            sendToCorpusButton.isHidden = true
        } else {
            sendToCorpusButton.isHidden = toolbarStrip.isHidden
        }
        ratingControl.isEnabled = hasArchive && !isScanning
        searchField.isHidden = !hasArchive || isViewer || isScanning || (viewMode == .profile && profileVisible)
        densityButton.isHidden = searchField.isHidden
        slideshowButton.isHidden = !hasArchive || isViewer || (viewMode == .profile && profileVisible)
        profileButton.isHidden = !hasArchive || isViewer || isScanning
        let profileWidth = window?.contentView.map { currentProfileWidth(for: $0.bounds) } ?? 0
        sidebarDivider.isHidden = !hasArchive || isViewer
        profileDivider.isHidden = !hasArchive || isViewer || profileWidth == 0
        topBar.isHidden = isViewer || !hasArchive || isScanning
        modeControl.isHidden = topBar.isHidden
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let showResultMessage = hasArchive && filteredImages.isEmpty && !isViewer && !(viewMode == .profile && profileVisible)
        let showStartupMessage = !hasArchive || isScanning
        openButton.isHidden = true
        loadingIndicator.isHidden = true
        emptyLabel.isHidden = true
        for view in [viewerTopBar, viewerBottomBar, viewerTitleLabel, viewerMetaLabel, viewerFileLabel, viewerExitButton, viewerProfileButton, viewerPrevButton, viewerNextButton] {
            view.isHidden = !hasArchive || !isViewer
        }
        homeStateView.isHidden = !(showStartupMessage || showResultMessage)
        if isScanning {
            homeStateView.configure(.loading(archiveMessage ?? "Scanning..."))
        } else if !hasArchive {
            if let archiveMessage {
                homeStateView.configure(.message(archiveMessage, showOpenButton: true))
            } else {
                homeStateView.configure(.welcome(recents: Self.recentLibraryURLs))
            }
        } else if !query.isEmpty {
            homeStateView.configure(.message("No images match \"\(query)\"", showOpenButton: false))
        } else {
            homeStateView.configure(.message("No images found in this folder.", showOpenButton: false))
        }
        rootView.color = isViewer ? Palette.dark : Palette.bg
        layoutViews()
    }

    @objc private func modeChanged() {
        viewMode = ViewMode(rawValue: modeControl.selectedSegment) ?? .grid
        if viewMode == .profile {
            profileVisible = true
        }
        if viewMode == .viewer {
            openViewer(at: selectedImageIndex)
            return
        }
        updateModeButtons()
        updateContentVisibility()
    }

    @objc func toggleDensity() {
        density = density.next
        applyDensity()
    }

    @objc func useCompactDensity() {
        density = .compact
        applyDensity()
    }

    @objc func useComfortableDensity() {
        density = .comfortable
        applyDensity()
    }

    @objc func useSpaciousDensity() {
        density = .spacious
        applyDensity()
    }

    private func applyDensity() {
        if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            layout.itemSize = NSSize(width: density.itemSide, height: density.itemSide + 28)
            layout.invalidateLayout()
        }
        collectionView.reloadData()
        updateModeButtons()
    }

    @objc func toggleProfile() {
        profileVisible.toggle()
        if profileVisible, viewMode == .profile {
            modeControl.selectedSegment = ViewMode.profile.rawValue
        }
        updateModeButtons()
        updateContentVisibility()
    }

    @objc func toggleViewerProfile() {
        viewerProfileVisible.toggle()
        updateModeButtons()
        updateContentVisibility()
    }

    @objc func exitViewer() {
        stopSlideshow()
        viewMode = .grid
        viewerProfileVisible = false
        updateModeButtons()
        updateContentVisibility()
        loadPreview()
        window?.makeFirstResponder(nil)
    }

    @objc func previousImage() {
        advanceImage(-1)
    }

    @objc func nextImage() {
        advanceImage(1)
    }

    @objc func toggleSlideshow() {
        if slideshowTimer == nil {
            openViewer(at: selectedImageIndex)
            slideshowButton.isActive = true
            slideshowTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: true) { [weak self] _ in
                self?.advanceImage(1)
            }
        } else {
            stopSlideshow()
        }
        updateModeButtons()
    }

    @objc func enterViewer() {
        openViewer(at: selectedImageIndex)
    }

    @objc func focusSearch() {
        guard !searchField.isHidden else { return }
        window?.makeFirstResponder(searchField)
    }

    @objc func copyCurrentImage() {
        guard let image = currentImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let nsImage = NSImage(contentsOf: image.url) {
            pasteboard.writeObjects([nsImage, image.url as NSURL])
        } else {
            pasteboard.writeObjects([image.url as NSURL])
        }
    }

    @objc func showSendToCorpusMenu(_ sender: NSButton) {
        let menu = makeCorpusSendMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }

    @objc func createCorpusVaultProfileFromSelection() {
        guard let model = currentModel() else { return }
        let images = selectedImagesForCorpusExport()
        guard !images.isEmpty else { return }

        do {
            let root = try CorpusVaultExporter.shared.exportImages(model: model, images: images)
            showCorpusVaultExportSuccess(imageCount: images.count, root: root)
        } catch {
            showCorpusVaultExportError(error)
        }
    }

    @objc func sendSelectedImagesToExistingCorpusProfile() {
        let images = selectedImagesForCorpusExport()
        guard !images.isEmpty else { return }

        do {
            let options = try CorpusVaultExporter.shared.destinationOptions()
            guard !options.models.isEmpty, !options.groups.isEmpty else {
                throw CorpusVaultExportError.missingDestination
            }
            presentCorpusDestinationPicker(images: images, models: options.models, groups: options.groups)
        } catch {
            showCorpusVaultExportError(error)
        }
    }

    @objc func createCorpusVaultProfileFromCurrentFolder() {
        guard let model = currentModel() else { return }
        exportFolderToCorpusVault(model)
    }

    @objc func createCorpusVaultProfileFromSidebarFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let normalizedURL = url.standardizedFileURL
        let model = models.first { $0.url == normalizedURL } ?? store.scan(normalizedURL).first
        guard let model else {
            showCorpusVaultExportError(CorpusVaultExportError.noImages)
            return
        }
        exportFolderToCorpusVault(model)
    }

    @objc func selectAllImages() {
        guard !filteredImages.isEmpty else { return }
        selectedImageIndexes = Set(filteredImages.indices)
        selectedImageIndex = filteredImages.indices.first ?? 0
        syncCollectionSelection()
        collectionView.reloadData()
        updateStatus()
    }

    @objc func openRecentLibrary(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        openArchive(URL(fileURLWithPath: path))
    }

    @objc func clearRecentLibraries() {
        UserDefaults.standard.removeObject(forKey: Self.recentLibrariesKey)
        UserDefaults.standard.removeObject(forKey: Self.lastLibraryKey)
    }

    @objc func renameFolder(_ sender: NSMenuItem) {
        guard let oldURL = sender.representedObject as? URL else { return }
        promptForFolderRename(oldURL)
    }

    @objc func ratingChanged() {
        guard Self.ratingValues.indices.contains(ratingControl.selectedSegment),
              let model = currentModel() else {
            updateRatingControl()
            return
        }

        let rating = Self.ratingValues[ratingControl.selectedSegment]
        let baseName = folderNameByRemovingRating(from: model.url.lastPathComponent)
        renameFolder(at: model.url, to: baseName + rating)
    }

    private func stopSlideshow() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
        slideshowButton.isActive = false
        slideshowButton.needsDisplay = true
        updateModeButtons()
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
        selectedImageIndexes = filteredImages.isEmpty ? [] : [0]
        collectionView.reloadData()
        if !filteredImages.isEmpty {
            syncCollectionSelection()
            collectionView.scrollToItems(at: Set([IndexPath(item: 0, section: 0)]), scrollPosition: .top)
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
        let isSelected = selectedImageIndexes.contains(indexPath.item)
        imageItem.configure(asset: filteredImages[indexPath.item], index: indexPath.item, side: density.itemSide, isCurrent: indexPath.item == selectedImageIndex, isSelected: isSelected)
        return imageItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !suppressCollectionSelectionHandler else { return }
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !suppressCollectionSelectionHandler else { return }
    }

    func collectionClicked(indexPath: IndexPath, commandPressed: Bool) {
        guard filteredImages.indices.contains(indexPath.item) else { return }
        selectedImageIndex = indexPath.item
        if commandPressed {
            if selectedImageIndexes.contains(indexPath.item) {
                selectedImageIndexes.remove(indexPath.item)
            } else {
                selectedImageIndexes.insert(indexPath.item)
            }
        } else {
            selectedImageIndexes = [indexPath.item]
        }
        if selectedImageIndexes.isEmpty {
            selectedImageIndexes = [indexPath.item]
        }
        syncCollectionSelection()
        refreshVisibleCollectionItems()
        updateStatus()
    }

    func collectionDragSelected(indexPaths: Set<IndexPath>) {
        let indexes = Set(indexPaths.map(\.item).filter { filteredImages.indices.contains($0) })
        guard !indexes.isEmpty else { return }
        selectedImageIndexes = indexes
        selectedImageIndex = indexes.min() ?? selectedImageIndex
        syncCollectionSelection()
        refreshVisibleCollectionItems()
        updateStatus()
    }

    private func refreshVisibleCollectionItems() {
        let visible = collectionView.indexPathsForVisibleItems()
        guard !visible.isEmpty else { return }
        for indexPath in visible where filteredImages.indices.contains(indexPath.item) {
            guard let imageItem = collectionView.item(at: indexPath) as? ImageCollectionItem else { continue }
            imageItem.updateSelection(
                isCurrent: indexPath.item == selectedImageIndex,
                isSelected: selectedImageIndexes.contains(indexPath.item)
            )
        }
    }

    private func syncCollectionSelection() {
        suppressCollectionSelectionHandler = true
        collectionView.deselectAll(nil)
        suppressCollectionSelectionHandler = false
    }

    func openCollectionItem(at indexPath: IndexPath) {
        openViewer(at: indexPath.item)
    }

    private func openViewer(at index: Int, showProfile: Bool = false) {
        guard filteredImages.indices.contains(index) else { return }
        selectedImageIndex = index
        viewMode = .viewer
        viewerProfileVisible = showProfile
        updateModeButtons()
        updateContentVisibility()
        loadPreview()
        updateStatus()
        window?.makeFirstResponder(collectionView)
    }

    private func menuForImage(at indexPath: IndexPath?) -> NSMenu? {
        guard let indexPath, filteredImages.indices.contains(indexPath.item) else { return nil }
        selectImageForContextMenu(at: indexPath.item)
        return makeImageContextMenu()
    }

    private func makeImageContextMenu() -> NSMenu {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy Image", action: #selector(copyCurrentImage), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        menu.addItem(.separator())
        appendCorpusSendItems(to: menu)
        return menu
    }

    private func makeCorpusSendMenu() -> NSMenu {
        let menu = NSMenu()
        appendCorpusSendItems(to: menu)
        return menu
    }

    private func appendCorpusSendItems(to menu: NSMenu) {
        let selectedCount = selectedImagesForCorpusExport().count

        let appendItem = NSMenuItem(
            title: selectedCount > 1 ? "Add \(selectedCount) Images to Existing CorpusVault Profile..." : "Add Selection to Existing CorpusVault Profile...",
            action: #selector(sendSelectedImagesToExistingCorpusProfile),
            keyEquivalent: ""
        )
        appendItem.target = self
        appendItem.isEnabled = selectedCount > 0
        menu.addItem(appendItem)

        let createSelectionItem = NSMenuItem(
            title: selectedCount > 1 ? "Create New CorpusVault Profile from \(selectedCount) Images" : "Create New CorpusVault Profile from Selection",
            action: #selector(createCorpusVaultProfileFromSelection),
            keyEquivalent: ""
        )
        createSelectionItem.target = self
        createSelectionItem.isEnabled = selectedCount > 0
        menu.addItem(createSelectionItem)

        menu.addItem(.separator())

        let folderItem = NSMenuItem(
            title: "Create New CorpusVault Profile from Current Folder",
            action: #selector(createCorpusVaultProfileFromCurrentFolder),
            keyEquivalent: ""
        )
        folderItem.target = self
        folderItem.isEnabled = currentModel() != nil
        menu.addItem(folderItem)
    }

    private func selectImageForContextMenu(at index: Int) {
        guard filteredImages.indices.contains(index) else { return }
        if selectedImageIndexes.contains(index) {
            selectedImageIndex = index
            refreshVisibleCollectionItems()
            updateStatus()
            return
        }
        let previousImageIndex = selectedImageIndex
        selectedImageIndex = index
        selectedImageIndexes = [index]
        syncCollectionSelection()
        let reloadIndexPaths = [previousImageIndex, selectedImageIndex]
            .filter { filteredImages.indices.contains($0) }
            .map { IndexPath(item: $0, section: 0) }
        collectionView.reloadItems(at: Set(reloadIndexPaths))
        updateStatus()
    }

    private func updateViewerLabels() {
        guard let model = currentModel(), let image = currentImage() else {
            viewerTitleLabel.stringValue = ""
            viewerMetaLabel.stringValue = ""
            viewerFileLabel.stringValue = ""
            return
        }
        viewerTitleLabel.stringValue = model.name
        viewerMetaLabel.stringValue = "\(selectedImageIndex + 1) of \(filteredImages.count)"
        viewerFileLabel.stringValue = "\(image.url.lastPathComponent) · \(image.formattedByteCount)"
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
        let subtitle = folderSubtitle(for: node.url)
        view.nameLabel.stringValue = node.name
        view.subtitleLabel.stringValue = subtitle
        view.toolTip = subtitle
        view.setAccessibilityLabel("\(view.nameLabel.stringValue), \(subtitle)")
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
        refreshSidebarRows()
    }

    private func menuForSidebarRow(_ row: Int) -> NSMenu? {
        guard let node = sidebar.item(atRow: row) as? FolderNode else { return nil }
        guard node.url.path != "/" else { return nil }

        let menu = NSMenu()
        let renameItem = NSMenuItem(title: "Rename Folder...", action: #selector(renameFolder(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = node.url
        menu.addItem(renameItem)
        menu.addItem(.separator())
        let corpusItem = NSMenuItem(title: "Create CorpusVault Profile from Folder", action: #selector(createCorpusVaultProfileFromSidebarFolder(_:)), keyEquivalent: "")
        corpusItem.target = self
        corpusItem.representedObject = node.url
        menu.addItem(corpusItem)
        return menu
    }

    private func promptForFolderRename(_ oldURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Rename Folder"
        alert.informativeText = oldURL.path
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = oldURL.lastPathComponent
        input.selectText(nil)
        alert.accessoryView = input

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak input] response in
            guard response == .alertFirstButtonReturn, let input else { return }
            self?.renameFolder(at: oldURL, to: input.stringValue)
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func renameFolder(at oldURL: URL, to proposedName: String) {
        let newName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidFolderName(newName) else {
            showRenameError("Use a folder name that is not empty and does not contain '/'.")
            return
        }

        let oldURL = oldURL.standardizedFileURL
        guard newName != oldURL.lastPathComponent else { return }

        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            showRenameError("A folder named \"\(newName)\" already exists.")
            return
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            showRenameError(error.localizedDescription)
            return
        }

        store.clearCache()
        sidebarSubtitleCache.removeAll()
        rebuildBrowserTree(afterRenaming: oldURL, to: newURL)
        openArchive(newURL, resetBrowser: false)
    }

    private func updateRatingControl() {
        guard let name = currentModel()?.url.lastPathComponent,
              let rating = ratingSuffix(in: name),
              let index = Self.ratingValues.firstIndex(of: rating) else {
            ratingControl.selectedSegment = -1
            return
        }
        ratingControl.selectedSegment = index
    }

    private func folderNameByRemovingRating(from name: String) -> String {
        guard let rating = ratingSuffix(in: name) else { return name }
        return String(name.dropLast(rating.count))
    }

    private func ratingSuffix(in name: String) -> String? {
        for rating in Self.ratingValues.sorted(by: { $0.count > $1.count }) {
            if name.hasSuffix(rating) {
                return rating
            }
        }
        return nil
    }

    private func isValidFolderName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    private func rebuildBrowserTree(afterRenaming oldURL: URL, to newURL: URL) {
        let oldRootURL = browserRoot?.url.standardizedFileURL
        let rootURL = oldRootURL == oldURL ? newURL : (oldRootURL ?? newURL)
        browserRoot = FolderNode(url: rootURL)
        browserRoot?.loadChildren()

        suppressBrowserSelection = true
        sidebar.reloadData()
        if let browserRoot {
            sidebar.expandItem(browserRoot)
        }
        suppressBrowserSelection = false
        selectBrowserURL(newURL)
    }

    private func showRenameError(_ message: String) {
        updateRatingControl()
        let alert = NSAlert()
        alert.messageText = "Could Not Rename Folder"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func selectedImagesForCorpusExport() -> [ImageAsset] {
        let selected = selectedImageIndexes
            .sorted()
            .compactMap { filteredImages.indices.contains($0) ? filteredImages[$0] : nil }
        if !selected.isEmpty {
            return selected
        }
        return currentImage().map { [$0] } ?? []
    }

    private func presentCorpusDestinationPicker(
        images: [ImageAsset],
        models: [CorpusVaultModelChoice],
        groups: [CorpusVaultGroupChoice]
    ) {
        let modelPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28), pullsDown: false)
        for model in models {
            modelPopup.addItem(withTitle: model.name)
            modelPopup.lastItem?.representedObject = model.id
            modelPopup.lastItem?.toolTip = model.id
        }

        let groupPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28), pullsDown: false)
        for group in groups {
            groupPopup.addItem(withTitle: group.name)
            groupPopup.lastItem?.representedObject = group.id
            groupPopup.lastItem?.toolTip = group.folder
        }

        let modelLabel = NSTextField(labelWithString: "Corpus model")
        modelLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        let groupLabel = NSTextField(labelWithString: "Pose group")
        groupLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        let stack = NSStackView(views: [modelLabel, modelPopup, groupLabel, groupPopup])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 112)

        let alert = NSAlert()
        alert.messageText = "Send to CorpusVault"
        alert.informativeText = "Append \(images.count) selected image\(images.count == 1 ? "" : "s") to an existing model."
        alert.alertStyle = .informational
        alert.accessoryView = stack
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak modelPopup, weak groupPopup] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let modelID = modelPopup?.selectedItem?.representedObject as? String,
                  let groupID = groupPopup?.selectedItem?.representedObject as? String else {
                self?.showCorpusVaultExportError(CorpusVaultExportError.missingDestination)
                return
            }
            self?.appendImagesToCorpusVault(images, modelID: modelID, groupID: groupID)
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func appendImagesToCorpusVault(_ images: [ImageAsset], modelID: String, groupID: String) {
        do {
            let root = try CorpusVaultExporter.shared.appendImages(images, toModelID: modelID, groupID: groupID)
            showCorpusVaultAppendSuccess(imageCount: images.count, root: root)
        } catch {
            showCorpusVaultExportError(error)
        }
    }

    private func exportFolderToCorpusVault(_ model: ModelFolder) {
        do {
            let root = try CorpusVaultExporter.shared.exportFolder(model: model)
            showCorpusVaultExportSuccess(imageCount: model.images.count, root: root)
        } catch {
            showCorpusVaultExportError(error)
        }
    }

    private func showCorpusVaultAppendSuccess(imageCount: Int, root: URL) {
        let alert = NSAlert()
        alert.messageText = "Sent to CorpusVault"
        alert.informativeText = "Appended \(imageCount) image\(imageCount == 1 ? "" : "s") into \(root.path)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showCorpusVaultExportSuccess(imageCount: Int, root: URL) {
        let alert = NSAlert()
        alert.messageText = "Created CorpusVault Profile"
        alert.informativeText = "Imported \(imageCount) image\(imageCount == 1 ? "" : "s") into \(root.path)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showCorpusVaultExportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could Not Create CorpusVault Profile"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
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
        case KeyCode.upArrow:
            advanceSidebarSelection(-1)
            return true
        case KeyCode.downArrow:
            advanceSidebarSelection(1)
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
            if viewMode == .viewer {
                exitViewer()
                return true
            }
        case KeyCode.return_:
            if viewMode != .viewer {
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

    private func advanceSidebarSelection(_ delta: Int) {
        guard sidebar.numberOfRows > 0 else { return }
        let selectableRows = sidebarSelectableRows()
        guard !selectableRows.isEmpty else { return }

        let currentRow = sidebar.selectedRow
        let currentPosition = selectableRows.firstIndex(of: currentRow)
        let nextPosition: Int
        if let currentPosition {
            nextPosition = min(max(currentPosition + delta, 0), selectableRows.count - 1)
        } else {
            nextPosition = delta > 0 ? 0 : selectableRows.count - 1
        }

        let nextRow = selectableRows[nextPosition]
        guard nextRow != currentRow else { return }
        sidebar.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        sidebar.scrollRowToVisible(nextRow)
        refreshSidebarRows()
    }

    private func sidebarSelectableRows() -> [Int] {
        let rows = Array(0..<sidebar.numberOfRows)
        guard let browserRoot, rows.count > 1 else { return rows }
        return rows.filter { row in
            guard let node = sidebar.item(atRow: row) as? FolderNode else { return false }
            return node !== browserRoot
        }
    }

    private func refreshSidebarRows() {
        guard sidebar.numberOfRows > 0 else { return }
        sidebar.reloadData(
            forRowIndexes: IndexSet(integersIn: 0..<sidebar.numberOfRows),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    private func jumpToImage(_ index: Int) {
        guard filteredImages.indices.contains(index) else { return }
        let previousImageIndex = selectedImageIndex
        selectedImageIndex = index
        syncImageSelectionAfterKeyboardMove(previousImageIndex: previousImageIndex)
    }

    private func syncImageSelectionAfterKeyboardMove(previousImageIndex: Int) {
        if viewMode == .viewer {
            loadPreview()
        } else {
            selectedImageIndexes = [selectedImageIndex]
            syncCollectionSelection()
            collectionView.scrollToItems(at: Set([IndexPath(item: selectedImageIndex, section: 0)]), scrollPosition: .centeredVertically)
            refreshVisibleCollectionItems()
        }
        updateStatus()
    }
}
