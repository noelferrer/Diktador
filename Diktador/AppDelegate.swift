import AppKit
import DiktadorHotkey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let idleTitle = "Diktador (idle)"
    private static let listeningTitle = "Diktador (listening…)"

    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyRegistry()
    private var pushToTalkToken: HotkeyRegistry.RegistrationToken?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        registerPushToTalk()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: Self.idleTitle, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu

        self.statusItem = item
    }

    private func registerPushToTalk() {
        // v1 hardcoded default; the settings module will replace this. Bare Fn-key triggers
        // and sided modifiers (the ideal Mac dictation UX) need NSEvent.addGlobalMonitorForEvents,
        // which Carbon Events / soffes/HotKey can't reach — filed as the next focused PR.
        let combo = KeyCombo(key: .space, modifiers: [.option])
        pushToTalkToken = hotkeys.register(
            combo: combo,
            onPress: { [weak self] in self?.setListening(true) },
            onRelease: { [weak self] in self?.setListening(false) }
        )
    }

    func setListening(_ listening: Bool) {
        statusItem?.button?.image = listening ? Self.listeningImage : Self.idleImage
        statusItem?.menu?.items.first?.title = listening ? Self.listeningTitle : Self.idleTitle
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
