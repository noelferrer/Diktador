import AppKit
import DiktadorHotkey
import DiktadorRecorder
import DiktadorTranscriber

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let idleTitle = "Diktador (idle)"
    private static let listeningTitle = "Diktador (listening…)"
    private static let inputMonitoringNeededTitle = "Diktador (needs Input Monitoring)"
    private static let microphoneNeededTitle = "Diktador (needs Microphone)"
    private static let openInputMonitoringSettingsTitle = "Open Input Monitoring settings…"
    private static let openMicrophoneSettingsTitle = "Open Microphone settings…"
    private static let transcriberLoadingTitle = "Transcription: loading model…"
    private static let transcriberReadyTitle = "Transcription: ready"
    private static let transcriberTranscribingTitle = "Transcription: transcribing…"
    private static let transcriberFailedTitle = "Transcription: model unavailable — see Console"
    private static let transcriberInferenceFailedTitle = "Transcription failed — see Console"
    private static let transcriberNoSpeechTitle = "Transcription: no speech detected"

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
    private var transcriberStatusItem: NSMenuItem?
    private var lastTranscriptItem: NSMenuItem?
    private var statusFlashGeneration: Int = 0
    private var transcriptionGeneration: Int = 0

    private let hotkeys = HotkeyRegistry()
    private let recorder = Recorder()
    @MainActor private lazy var transcriber = WhisperKitTranscriber()
    private var pushToTalkToken: HotkeyRegistry.RegistrationToken?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bootstrapPushToTalk()
        Task { @MainActor [weak self] in
            await self?.loadTranscriptionModel()
        }
    }

    @MainActor
    private func loadTranscriptionModel() async {
        transcriberStatusItem?.title = Self.transcriberLoadingTitle
        do {
            try await transcriber.loadModel()
            transcriberStatusItem?.title = Self.transcriberReadyTitle
        } catch {
            transcriberStatusItem?.title = Self.transcriberFailedTitle
            NSLog("[app] transcriber.loadModel failed: \(error)")
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage

        let menu = NSMenu()
        let statusRow = NSMenuItem(title: Self.idleTitle, action: nil, keyEquivalent: "")
        menu.addItem(statusRow)
        menu.addItem(.separator())
        let transcriberStatus = NSMenuItem(title: Self.transcriberLoadingTitle, action: nil, keyEquivalent: "")
        menu.addItem(transcriberStatus)
        self.transcriberStatusItem = transcriberStatus
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
            let url = recording.fileURL
            Task { @MainActor [weak self] in
                await self?.runTranscription(for: url)
            }
        case .failure(let error):
            NSLog("[app] recorder.stop failed: \(error)")
            flashFailure(error)
        }
    }

    @MainActor
    private func runTranscription(for audioFileURL: URL) async {
        transcriptionGeneration += 1
        let generation = transcriptionGeneration
        transcriberStatusItem?.title = Self.transcriberTranscribingTitle
        do {
            let transcript = try await transcriber.transcribe(audioFileURL: audioFileURL)
            guard generation == transcriptionGeneration else { return }
            copyTranscriptToPasteboard(transcript)
            updateLastTranscriptItem(transcript)
            transcriberStatusItem?.title = Self.transcriberReadyTitle
        } catch TranscriberError.emptyTranscript {
            guard generation == transcriptionGeneration else { return }
            transcriberStatusItem?.title = Self.transcriberNoSpeechTitle
            NSLog("[app] transcription returned no speech for \(audioFileURL.lastPathComponent)")
        } catch TranscriberError.modelLoadFailed(let message) {
            guard generation == transcriptionGeneration else { return }
            transcriberStatusItem?.title = Self.transcriberFailedTitle
            NSLog("[app] transcription unavailable: \(message)")
        } catch {
            guard generation == transcriptionGeneration else { return }
            transcriberStatusItem?.title = Self.transcriberInferenceFailedTitle
            NSLog("[app] transcription failed: \(error)")
        }
    }

    @MainActor
    private func copyTranscriptToPasteboard(_ transcript: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
    }

    @MainActor
    private func updateLastTranscriptItem(_ transcript: String) {
        let title = Self.lastTranscriptMenuTitle(for: transcript)
        if let item = lastTranscriptItem {
            item.title = title
            item.representedObject = transcript
            return
        }
        let item = NSMenuItem(
            title: title,
            action: #selector(copyLastTranscript(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = transcript
        // Insert above "Last recording" if present, else above the Quit-area separator.
        let menu = statusItem?.menu
        if let recordingItem = lastRecordingItem,
           let menu, let idx = menu.items.firstIndex(of: recordingItem) {
            menu.insertItem(item, at: idx)
        } else if let menu {
            // Insert just before the final separator+Quit pair.
            let insertAt = max(menu.items.count - 2, 0)
            menu.insertItem(item, at: insertAt)
        }
        lastTranscriptItem = item
    }

    @MainActor
    @objc private func copyLastTranscript(_ sender: NSMenuItem) {
        guard let transcript = sender.representedObject as? String else { return }
        copyTranscriptToPasteboard(transcript)
    }

    private static func lastTranscriptMenuTitle(for transcript: String) -> String {
        let head = transcript.prefix(61)
        let single = String(head).replacingOccurrences(of: "\n", with: " ")
        let trimmed = head.count > 60 ? String(single.prefix(60)) + "…" : single
        return "Last transcript: \"\(trimmed)\" — Copied"
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
