import AppKit
import HotKey

/// Owns the live set of global hotkey registrations and their callbacks.
/// Two parallel paths share one `RegistrationToken` type: a Carbon-Events
/// path via soffes/HotKey for keyed `KeyCombo`s, and an NSEvent-global-monitor
/// path for bare `ModifierTrigger`s.
public final class HotkeyRegistry {
    public struct RegistrationToken: Hashable, Sendable {
        fileprivate let id: UUID
    }

    // HotKey retains its own keyDownHandler/keyUpHandler closures, so the registry only
    // needs to hold the HotKey instance to keep the registration alive.
    private var carbonEntries: [UUID: HotKey] = [:]
    private var monitorEntries: [UUID: ModifierMonitorEntry] = [:]
    private let permissionProvider: PermissionProvider

    public init() {
        self.permissionProvider = IOHIDPermissionProvider()
    }

    /// Test-only initializer that swaps in a stub permission provider.
    internal init(permissionProvider: PermissionProvider) {
        self.permissionProvider = permissionProvider
    }

    public var activeRegistrationCount: Int {
        carbonEntries.count + monitorEntries.count
    }

    // MARK: Permission

    public var inputMonitoringPermission: InputMonitoringStatus {
        permissionProvider.currentStatus()
    }

    public func requestInputMonitoringPermission(
        completion: @escaping (InputMonitoringStatus) -> Void
    ) {
        permissionProvider.requestAccess(completion: completion)
    }

    // MARK: KeyCombo (Carbon path) — unchanged from PR #2

    /// Registers a key combo and returns a token used to later unregister it.
    public func register(
        combo: KeyCombo,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) -> RegistrationToken {
        let hotKey = HotKey(key: combo.key, modifiers: combo.modifiers)
        hotKey.keyDownHandler = onPress
        hotKey.keyUpHandler = onRelease
        let id = UUID()
        carbonEntries[id] = hotKey
        return RegistrationToken(id: id)
    }

    // MARK: ModifierTrigger (NSEvent path)

    /// Registers a bare-modifier trigger and returns a token used to later unregister it.
    /// `onPress` fires on the modifier's down-edge, `onRelease` on its up-edge.
    /// Requires Input Monitoring permission to fire while another app is frontmost.
    public func register(
        modifierTrigger: ModifierTrigger,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) -> RegistrationToken {
        let id = UUID()
        var entry = ModifierMonitorEntry(
            trigger: modifierTrigger,
            globalHandle: nil,
            localHandle: nil,
            isPressed: false,
            onPress: onPress,
            onRelease: onRelease
        )

        let globalHandler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlagsChanged(event: event, tokenID: id)
        }
        let localHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.handleFlagsChanged(event: event, tokenID: id)
            return event
        }

        entry.globalHandle = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged,
            handler: globalHandler
        )
        entry.localHandle = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: localHandler
        )

        if entry.globalHandle == nil {
            NSLog("[hotkey] failed to install global monitor for \(modifierTrigger)")
        }

        monitorEntries[id] = entry
        return RegistrationToken(id: id)
    }

    private func handleFlagsChanged(event: NSEvent, tokenID: UUID) {
        guard var entry = monitorEntries[tokenID] else { return }
        let isPressedNow = event.modifierFlags.contains(entry.trigger.flag)
        guard isPressedNow != entry.isPressed else { return }
        entry.isPressed = isPressedNow
        monitorEntries[tokenID] = entry
        if isPressedNow {
            entry.onPress()
        } else {
            entry.onRelease()
        }
    }

    // MARK: Unregister

    /// Removes the registration associated with the token (no-op if unknown).
    public func unregister(_ token: RegistrationToken) {
        if carbonEntries.removeValue(forKey: token.id) != nil { return }
        if let entry = monitorEntries.removeValue(forKey: token.id) {
            if let global = entry.globalHandle { NSEvent.removeMonitor(global) }
            if let local = entry.localHandle { NSEvent.removeMonitor(local) }
        }
    }
}

// MARK: - ModifierMonitorEntry

private struct ModifierMonitorEntry {
    let trigger: ModifierTrigger
    var globalHandle: Any?
    var localHandle: Any?
    var isPressed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
}
