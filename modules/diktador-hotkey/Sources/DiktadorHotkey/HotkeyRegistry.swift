import AppKit
import HotKey

/// Owns the live set of global hotkey registrations and their callbacks.
public final class HotkeyRegistry {
    public struct RegistrationToken: Hashable, Sendable {
        fileprivate let id: UUID
    }

    private struct Entry {
        let hotKey: HotKey
        let onPress: () -> Void
        let onRelease: () -> Void
    }

    private var entries: [UUID: Entry] = [:]

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
        entries[id] = Entry(hotKey: hotKey, onPress: onPress, onRelease: onRelease)
        return RegistrationToken(id: id)
    }

    /// Removes the registration associated with the token (no-op if unknown).
    public func unregister(_ token: RegistrationToken) {
        entries.removeValue(forKey: token.id)
    }
}
