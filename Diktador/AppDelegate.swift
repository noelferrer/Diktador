import AppKit
import DiktadorHotkey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let idleTitle = "Diktador (idle)"
    private static let listeningTitle = "Diktador (listening…)"
    private static let permissionNeededTitle = "Diktador (needs Input Monitoring)"
    private static let openSettingsTitle = "Open Input Monitoring settings…"

    private static let inputMonitoringPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )

    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyRegistry()
    private var pushToTalkToken: HotkeyRegistry.RegistrationToken?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bootstrapPushToTalk()
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

    private func bootstrapPushToTalk() {
        switch hotkeys.inputMonitoringPermission {
        case .granted:
            registerFnPushToTalk()
        case .undetermined:
            hotkeys.requestInputMonitoringPermission { [weak self] _ in
                self?.bootstrapPushToTalk()
            }
        case .denied:
            showPermissionDeniedState()
        }
    }

    private func registerFnPushToTalk() {
        // Bare Fn (🌐) held = listening. The user must set
        // System Settings → Keyboard → Press 🌐 to → Do nothing
        // for the press not to ALSO trigger Apple's globe-key action.
        // See wiki/howtos/first-run-setup.md.
        pushToTalkToken = hotkeys.register(
            modifierTrigger: .fn,
            onPress: { [weak self] in self?.setListening(true) },
            onRelease: { [weak self] in self?.setListening(false) }
        )
    }

    private func showPermissionDeniedState() {
        statusItem?.button?.image = Self.warningImage
        statusItem?.menu?.items.first?.title = Self.permissionNeededTitle

        let openSettings = NSMenuItem(
            title: Self.openSettingsTitle,
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        openSettings.target = self
        statusItem?.menu?.insertItem(openSettings, at: 1)
    }

    @objc private func openInputMonitoringSettings() {
        if let url = Self.inputMonitoringPaneURL {
            NSWorkspace.shared.open(url)
        }
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

    static var warningImage: NSImage? {
        let image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: "Diktador (needs Input Monitoring)"
        )
        image?.isTemplate = true
        return image
    }
}
