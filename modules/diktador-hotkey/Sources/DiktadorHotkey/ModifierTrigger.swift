import AppKit

/// A bare-modifier trigger that fires on press / release without an associated key.
/// Use with `HotkeyRegistry.register(modifierTrigger:onPress:onRelease:)`.
public enum ModifierTrigger: Hashable, Sendable {
    case fn
}

extension ModifierTrigger {
    /// The `NSEvent.ModifierFlags` flag whose press/release transition fires the callbacks.
    internal var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        }
    }
}
