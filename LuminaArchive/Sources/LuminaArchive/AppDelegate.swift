import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

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
        mainMenu.addItem(appItem)
        mainMenu.addItem(fileItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Arkiv", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open Archive...", action: #selector(MainWindowController.openFolder), keyEquivalent: "o")
        openItem.target = mainWindowController
        fileMenu.addItem(openItem)
        fileItem.submenu = fileMenu
        NSApp.mainMenu = mainMenu
    }
}
