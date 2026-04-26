import AppKit
@_exported import enum HotKey.Key
import HotKey

public typealias Modifier = NSEvent.ModifierFlags

/// A key plus modifier flags that together describe a global hotkey combination.
public struct KeyCombo: Hashable, @unchecked Sendable {
    public let key: Key
    public let modifiers: Modifier

    public init(key: Key, modifiers: Modifier) {
        self.key = key
        self.modifiers = modifiers
    }

    public static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
        lhs.key == rhs.key && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }
}
