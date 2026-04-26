import AppKit
import HotKey

/// Owns the live set of global hotkey registrations and their callbacks.
public final class HotkeyRegistry {
    public struct RegistrationToken: Hashable, Sendable {
        fileprivate let id: UUID
    }

    // HotKey retains its own keyDownHandler/keyUpHandler closures, so the registry only
    // needs to hold the HotKey instance to keep the registration alive.
    private var entries: [UUID: HotKey] = [:]

    public init() {}

    public var activeRegistrationCount: Int { entries.count }

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
        entries[id] = hotKey
        return RegistrationToken(id: id)
    }

    /// Removes the registration associated with the token (no-op if unknown).
    public func unregister(_ token: RegistrationToken) {
        entries.removeValue(forKey: token.id)
    }
}
