import AppKit
import DiktadorHotkey
import DiktadorRecorder

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let idleTitle = "Diktador (idle)"
    private static let listeningTitle = "Diktador (listening…)"
    private static let inputMonitoringNeededTitle = "Diktador (needs Input Monitoring)"
    private static let microphoneNeededTitle = "Diktador (needs Microphone)"
    private static let openInputMonitoringSettingsTitle = "Open Input Monitoring settings…"
    private static let openMicrophoneSettingsTitle = "Open Microphone settings…"

    private static let inputMonitoringPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )
    private static let microphonePaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )

    private var statusItem: NSStatusItem?
    private var statusRowItem: NSMenuItem?
    private var openInputMonitoringSettingsItem: NSMenuItem?
    private var openMicrophoneSettingsItem: NSMenuItem?
    private var lastRecordingItem: NSMenuItem?
    private var statusFlashGeneration: Int = 0

    private let hotkeys = HotkeyRegistry()
    private let recorder = Recorder()
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
            checkMicrophonePermission()
        case .undetermined:
            hotkeys.requestInputMonitoringPermission { [weak self] _ in
                self?.bootstrapPushToTalk()
            }
        case .denied:
            showInputMonitoringDeniedState()
        }
    }

    private func checkMicrophonePermission() {
        switch recorder.microphonePermission {
        case .granted:
            registerFnPushToTalk()
        case .undetermined:
            recorder.requestMicrophonePermission { [weak self] _ in
                self?.checkMicrophonePermission()
            }
        case .denied:
            showMicrophoneDeniedState()
        }
    }

    private func registerFnPushToTalk() {
        // Bare Fn (🌐) held = listening + recording. The user must set
        // System Settings → Keyboard → Press 🌐 to → Do nothing
        // for the press not to ALSO trigger Apple's globe-key action.
        // See wiki/howtos/first-run-setup.md.
        pushToTalkToken = hotkeys.register(
            modifierTrigger: .fn,
            onPress: { [weak self] in self?.handlePress() },
            onRelease: { [weak self] in self?.handleRelease() }
        )
    }

    private func handlePress() {
        setListening(true)
        do {
            try recorder.start()
        } catch {
            setListening(false)
            NSLog("[app] recorder.start failed: \(error)")
            flashFailure(error)
        }
    }

    private func handleRelease() {
        setListening(false)
        recorder.stop { [weak self] result in
            self?.handleRecordingResult(result)
        }
    }

    private func handleRecordingResult(_ result: Result<RecordingResult, Error>) {
        switch result {
        case .success(let recording):
            let title = String(
                format: "Last recording: %.1fs — Reveal in Finder",
                recording.duration
            )
            if let item = lastRecordingItem {
                item.title = title
                item.representedObject = recording.fileURL
            } else {
                let item = NSMenuItem(
                    title: title,
                    action: #selector(revealLastRecording(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = recording.fileURL
                statusItem?.menu?.insertItem(item, at: 1)
                lastRecordingItem = item
            }
        case .failure(let error):
            NSLog("[app] recorder.stop failed: \(error)")
            flashFailure(error)
        }
    }

    /// Briefly shows an error in the status row, then reverts to the idle title
    /// after 3 s — but only if no newer status update arrives in the meantime.
    /// The generation counter cancels stale reverts so a fresh recording started
    /// inside the 3 s window doesn't get clobbered by an older revert closure.
    private func flashFailure(_ error: Error) {
        statusFlashGeneration += 1
        let generation = statusFlashGeneration
        statusRowItem?.title = "Recording failed: \(error)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.statusFlashGeneration == generation else { return }
            self.statusRowItem?.title = Self.idleTitle
        }
    }

    @objc private func revealLastRecording(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func showInputMonitoringDeniedState() {
        statusItem?.button?.image = Self.warningImage
        statusRowItem?.title = Self.inputMonitoringNeededTitle

        guard openInputMonitoringSettingsItem == nil else { return }
        let item = NSMenuItem(
            title: Self.openInputMonitoringSettingsTitle,
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        item.target = self
        statusItem?.menu?.insertItem(item, at: 1)
        openInputMonitoringSettingsItem = item
    }

    private func showMicrophoneDeniedState() {
        statusItem?.button?.image = Self.warningImage
        statusRowItem?.title = Self.microphoneNeededTitle

        guard openMicrophoneSettingsItem == nil else { return }
        let item = NSMenuItem(
            title: Self.openMicrophoneSettingsTitle,
            action: #selector(openMicrophoneSettings),
            keyEquivalent: ""
        )
        item.target = self
        statusItem?.menu?.insertItem(item, at: 1)
        openMicrophoneSettingsItem = item
    }

    @objc private func openInputMonitoringSettings() {
        if let url = Self.inputMonitoringPaneURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openMicrophoneSettings() {
        if let url = Self.microphonePaneURL {
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
        description: "Diktador (needs permission)"
    )
}
