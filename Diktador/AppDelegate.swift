import AppKit
import DiktadorHotkey

final class AppDelegate: NSObject, NSApplicationDelegate {
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

    private func registerPushToTalk() {
        // v1 default: Option+Space push-to-talk. Hardcoded; settings module will replace this.
        // Mirrors Whisper Flow's classic default; Cmd+Space is Spotlight, so Option+Space is free.
        // soffes/HotKey doesn't distinguish left vs right modifiers; sided-modifier support and
        // bare-Fn-key triggers (the ideal Mac dictation UX) require dropping down to
        // NSEvent.addGlobalMonitorForEvents in a follow-up PR.
        let combo = KeyCombo(key: .space, modifiers: [.option])
        pushToTalkToken = hotkeys.register(
            combo: combo,
            onPress: { [weak self] in self?.setListening(true) },
            onRelease: { [weak self] in self?.setListening(false) }
        )
    }

    /// Toggle the menu-bar icon and first menu row between idle and listening states.
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
