import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var mainWindowController: MainWindowController?
    private let recentMenu = NSMenu(title: "Open Recent")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let fileItem = NSMenuItem()
        let editItem = NSMenuItem()
        let viewItem = NSMenuItem()
        let windowItem = NSMenuItem()
        let helpItem = NSMenuItem()
        mainMenu.addItem(appItem)
        mainMenu.addItem(fileItem)
        mainMenu.addItem(editItem)
        mainMenu.addItem(viewItem)
        mainMenu.addItem(windowItem)
        mainMenu.addItem(helpItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Arkiv", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Arkiv", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open Archive...", action: #selector(MainWindowController.openFolder), keyEquivalent: "o")
        openItem.target = mainWindowController
        fileMenu.addItem(openItem)
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        let copyItem = NSMenuItem(title: "Copy Image", action: #selector(MainWindowController.copyCurrentImage), keyEquivalent: "c")
        copyItem.target = mainWindowController
        editMenu.addItem(copyItem)
        let selectAllItem = NSMenuItem(title: "Select All Images", action: #selector(MainWindowController.selectAllImages), keyEquivalent: "a")
        selectAllItem.target = mainWindowController
        editMenu.addItem(selectAllItem)
        editMenu.addItem(.separator())
        let sendToExistingItem = NSMenuItem(title: "Add Selection to Existing CorpusVault Profile...", action: #selector(MainWindowController.sendSelectedImagesToExistingCorpusProfile), keyEquivalent: "u")
        sendToExistingItem.target = mainWindowController
        sendToExistingItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(sendToExistingItem)
        let corpusSelectionItem = NSMenuItem(title: "Create New CorpusVault Profile from Selection", action: #selector(MainWindowController.createCorpusVaultProfileFromSelection), keyEquivalent: "c")
        corpusSelectionItem.target = mainWindowController
        corpusSelectionItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(corpusSelectionItem)
        let corpusFolderItem = NSMenuItem(title: "Create New CorpusVault Profile from Current Folder", action: #selector(MainWindowController.createCorpusVaultProfileFromCurrentFolder), keyEquivalent: "")
        corpusFolderItem.target = mainWindowController
        editMenu.addItem(corpusFolderItem)
        editItem.submenu = editMenu

        let viewMenu = NSMenu(title: "View")
        let focusSearchItem = NSMenuItem(title: "Find", action: #selector(MainWindowController.focusSearch), keyEquivalent: "f")
        focusSearchItem.target = mainWindowController
        viewMenu.addItem(focusSearchItem)
        viewMenu.addItem(.separator())
        let densityMenu = NSMenu(title: "Grid Density")
        let compactItem = NSMenuItem(title: "Compact", action: #selector(MainWindowController.useCompactDensity), keyEquivalent: "1")
        compactItem.target = mainWindowController
        compactItem.keyEquivalentModifierMask = [.command, .option]
        densityMenu.addItem(compactItem)
        let comfortableItem = NSMenuItem(title: "Comfortable", action: #selector(MainWindowController.useComfortableDensity), keyEquivalent: "2")
        comfortableItem.target = mainWindowController
        comfortableItem.keyEquivalentModifierMask = [.command, .option]
        densityMenu.addItem(comfortableItem)
        let spaciousItem = NSMenuItem(title: "Spacious", action: #selector(MainWindowController.useSpaciousDensity), keyEquivalent: "3")
        spaciousItem.target = mainWindowController
        spaciousItem.keyEquivalentModifierMask = [.command, .option]
        densityMenu.addItem(spaciousItem)
        let densityItem = NSMenuItem(title: "Grid Density", action: nil, keyEquivalent: "")
        densityItem.submenu = densityMenu
        viewMenu.addItem(densityItem)
        let profileItem = NSMenuItem(title: "Toggle Profile", action: #selector(MainWindowController.toggleProfile), keyEquivalent: "p")
        profileItem.target = mainWindowController
        viewMenu.addItem(profileItem)
        let slideshowItem = NSMenuItem(title: "Start or Pause Slideshow", action: #selector(MainWindowController.toggleSlideshow), keyEquivalent: "l")
        slideshowItem.target = mainWindowController
        viewMenu.addItem(slideshowItem)
        let viewerItem = NSMenuItem(title: "Enter Viewer", action: #selector(MainWindowController.enterViewer), keyEquivalent: "\r")
        viewerItem.target = mainWindowController
        viewerItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(viewerItem)
        viewItem.submenu = viewMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Arkiv Help", action: nil, keyEquivalent: "").isEnabled = false
        helpItem.submenu = helpMenu
        NSApp.mainMenu = mainMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        let urls = MainWindowController.recentLibraryURLs
        if urls.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Libraries", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(MainWindowController.openRecentLibrary(_:)), keyEquivalent: "")
            item.representedObject = url.path
            item.toolTip = url.path
            item.target = mainWindowController
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(MainWindowController.clearRecentLibraries), keyEquivalent: "")
        clearItem.target = mainWindowController
        menu.addItem(clearItem)
    }
}
