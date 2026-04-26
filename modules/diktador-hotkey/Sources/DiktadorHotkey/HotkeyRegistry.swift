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

    // MARK: ModifierTrigger (NSEvent path) — added in this PR; expanded in Phase E

    // (added in Task E2)

    // MARK: Unregister

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
