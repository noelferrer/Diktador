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
    private var statusRowItem: NSMenuItem?
    private var openSettingsItem: NSMenuItem?
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
        let statusRow = NSMenuItem(title: Self.idleTitle, action: nil, keyEquivalent: "")
        menu.addItem(statusRow)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu

        self.statusItem = item
        self.statusRowItem = statusRow
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
        statusRowItem?.title = Self.permissionNeededTitle

        guard openSettingsItem == nil else { return }
        let item = NSMenuItem(
            title: Self.openSettingsTitle,
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        item.target = self
        statusItem?.menu?.insertItem(item, at: 1)
        openSettingsItem = item
    }

    @objc private func openInputMonitoringSettings() {
        if let url = Self.inputMonitoringPaneURL {
            NSWorkspace.shared.open(url)
        }
    }

    func setListening(_ listening: Bool) {
        statusItem?.button?.image = listening ? Self.listeningImage : Self.idleImage
        statusRowItem?.title = listening ? Self.listeningTitle : Self.idleTitle
    }

    private static func templateSymbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    static let idleImage = templateSymbol("mic", description: "Diktador")
    static let listeningImage = templateSymbol("mic.fill", description: "Diktador (listening)")
    static let warningImage = templateSymbol(
        "exclamationmark.triangle",
        description: "Diktador (needs Input Monitoring)"
    )
}
