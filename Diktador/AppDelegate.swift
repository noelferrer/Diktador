import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Diktador (idle)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu

        self.statusItem = item
    }

    /// Toggle the menu-bar icon and first menu row between idle and listening states.
    /// Phase E will call this from the hotkey callback; for now it is unwired.
    func setListening(_ listening: Bool) {
        statusItem?.button?.image = listening ? Self.listeningImage : Self.idleImage
        statusItem?.menu?.items.first?.title = listening
            ? "Diktador (listening…)"
            : "Diktador (idle)"
    }

    static var idleImage: NSImage? {
        let image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Diktador")
        image?.isTemplate = true
        return image
    }

    static var listeningImage: NSImage? {
        let image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: "Diktador (listening)"
        )
        image?.isTemplate = true
        return image
    }
}
