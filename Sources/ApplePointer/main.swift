import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pointerController: PointerController?
    private var settingsWindowController: SettingsWindowController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PointerController()
        let settings = SettingsWindowController(pointerController: controller)
        self.pointerController = controller
        self.settingsWindowController = settings
        self.menuBarController = MenuBarController(
            pointerController: controller,
            settingsWindowController: settings
        )
        installMainMenu()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettingsFromMenu(_:)),
            keyEquivalent: ","
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit ApplePointer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu(_ sender: AnyObject?) {
        settingsWindowController?.showSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController?.showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        pointerController?.shutdown()
    }
}

@MainActor
private func runApp() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}

runApp()
