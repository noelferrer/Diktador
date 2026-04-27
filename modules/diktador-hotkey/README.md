# diktador-hotkey

## Purpose

Owns global hotkey registration for Diktador: hands callers a token-keyed registry that turns a `KeyCombo` plus key-down / key-up handlers into a system-wide shortcut.

## Public API

Import: `import DiktadorHotkey`. SwiftPM library and target are named `DiktadorHotkey`; the conceptual module is still `hotkey` (see "Known failure modes" below for the rename rationale).

- `HotkeyRegistry()` — instantiate. One registry per owner; `AppDelegate` owns the live one in v1.
- `register(combo:onPress:onRelease:) -> RegistrationToken` — installs the combo. `onPress` fires on key-down, `onRelease` on key-up. The returned token is the only way to remove the registration.
- `unregister(_ token:)` — removes the registration tied to `token`. No-op if the token is unknown. Subsequent press / release events for that combo no longer fire callbacks.
- `activeRegistrationCount: Int` — count of live registrations. Diagnostic and test surface; not for production logic.
- `KeyCombo(key: Key, modifiers: Modifier)` — value type describing a combo. `Hashable`, `@unchecked Sendable`.
- `Key` — re-exported `enum HotKey.Key` from soffes/HotKey via `@_exported import enum HotKey.Key`. Callers write `Key.f13`, not `HotKey.Key.f13`.
- `Modifier` — typealias for `NSEvent.ModifierFlags`.
- `RegistrationToken` — opaque `Hashable, Sendable` handle returned by `register`.
- `register(modifierTrigger:onPress:onRelease:) -> RegistrationToken` — installs a bare-modifier trigger over an NSEvent global monitor. `onPress` fires on the modifier's down-edge, `onRelease` on its up-edge. Requires Input Monitoring permission to fire while another app is frontmost.
- `inputMonitoringPermission: InputMonitoringStatus` — current macOS Input-Monitoring access for the running process. Synchronous, no side effects.
- `requestInputMonitoringPermission(completion:)` — returns immediately; the macOS consent prompt is driven on a background queue and `completion` fires on the main queue with the resolved status. Triggers the consent prompt the first time it is called per app-bundle / user; subsequent calls return the cached result without re-prompting.
- `ModifierTrigger` — `Hashable, Sendable` enum naming a bare-modifier trigger. v1: `.fn` only.
- `InputMonitoringStatus` — `Sendable, Equatable` enum: `.granted` / `.denied` / `.undetermined`.

Tests run with `swift test` from `modules/diktador-hotkey/`.

## Dependencies

- [soffes/HotKey](https://github.com/soffes/HotKey) ≥ 0.2.0 (resolved 0.2.1) via Swift Package Manager. Wraps Carbon Events; provides global hotkey installation without entitlements.
- AppKit (system) — for `NSEvent`, `NSEvent.ModifierFlags`, `NSEvent.addGlobalMonitorForEvents`.
- IOKit.hid (system) — for `IOHIDCheckAccess` / `IOHIDRequestAccess` (Input Monitoring).
- Deployment target: macOS 14+.
- No environment variables, no external services, no other Diktador modules.

The SwiftPM identifiers `DiktadorHotkey` (package directory `modules/diktador-hotkey/`, library, target, tests target) deviate from the conceptual name `hotkey` to dodge two SwiftPM bugs: identity collision when the package directory matches a transitive dependency name ([apple/swift-package-manager#8471](https://github.com/apple/swift-package-manager/issues/8471)), and APFS case-insensitivity collisions between a target named `HotKey` and the soffes/HotKey product ([apple/swift-package-manager#7931](https://github.com/apple/swift-package-manager/issues/7931)). Do not rename back.

## Known failure modes

- **`HotKey.Key` reference fails to compile.** soffes/HotKey exports both a top-level `class HotKey` and a top-level `enum Key`, so `HotKey.Key` resolves to a non-existent member of the class. `KeyCombo.swift` works around it with `@_exported import enum HotKey.Key`, which lets callers write `Key.f13` directly. The unusual import is intentional; do not "clean it up."
- **Synthesized `Hashable` on `KeyCombo` fails.** `NSEvent.ModifierFlags` is an `OptionSet` over `UInt` and is not `Hashable`. `KeyCombo` provides explicit `==` and `hash(into:)` keyed off `modifiers.rawValue`. Adding new stored properties to `KeyCombo` requires updating both.
- **`HotKey.Key` is not `Sendable`.** `KeyCombo` is marked `@unchecked Sendable`. Sound for v1: `Key` is a payload-less enum and `ModifierFlags` is a struct over `UInt` — both value types with no shared mutable state. Revisit if upstream changes.
- **No internal thread safety.** `HotkeyRegistry` is a `final class` with an unlocked dictionary, owned by `AppDelegate` on the main thread. Cross-thread `register` / `unregister` will race the dictionary. Acceptable for v1; add a lock or actor when a non-main-thread caller appears.
- **Silent registration conflict.** If the OS or another app has already claimed the combo, soffes/HotKey installs the hotkey but the callback never fires; no error is returned. v1 mitigation: pick uncommon combos (Option+Space is the v1 default — Spotlight is Cmd+Space, so Option+Space is generally free). v2 plan: surface conflicts via `CGEventSource` introspection at registration time. Symptom: hotkey "doesn't work" with no log line — verify by trying a different combo.
- **No left/right modifier distinction.** Carbon Events (the layer `HotKey` wraps) does not report sided modifiers, so a Right-Option-only registration is not expressible through this module. Supporting them requires `NSEvent.addGlobalMonitorForEvents`. Tracked as a follow-up in `memory/domains/hotkey.md`.
- **`onRelease` may not fire on every press.** If the OS swallows the key-up event (focus change while the key is held, modal takeover, screen lock, etc.), the registry never sees it and the release callback is skipped. Callers should treat hotkey state as advisory and impose a hard timeout on whatever the press starts (e.g., recorder auto-stop).
- **Repeated `register` of the same combo returns distinct tokens.** Each call installs a new `HotKey` instance and returns a fresh `RegistrationToken`. Both registrations remain live until separately unregistered; `onPress` / `onRelease` fire once per active registration. If you need at-most-one semantics, dedupe at the caller.
- **Input Monitoring denied.** A `register(modifierTrigger:)` call still returns a valid token, but the OS silently delivers no `.flagsChanged` events to the *global* monitor. The paired *local* monitor still fires while Diktador itself is frontmost, so trigger callbacks work in-app even with permission denied — a niche case for a menu-bar app, but technically supported. Mitigation: the app target should check `inputMonitoringPermission` before registering and surface a "needs Input Monitoring" UI on `.denied` rather than installing a half-dead handler.
- **Input Monitoring revoked at runtime.** macOS lets the user revoke access while Diktador is running; the registry receives no notification, the monitors stay live, but the events stop arriving. v1 mitigation: none (rare, recovers on next launch). Future: poll on `NSApplication.didBecomeActiveNotification` and re-bootstrap.
- **macOS "Press 🌐 to" system action.** If the user's globe-key action (System Settings → Keyboard → Press 🌐 to) is anything other than "Do nothing", pressing Fn ALSO triggers Apple's action (start Apple Dictation, show emoji picker, change input source). Cannot be suppressed from a global monitor. Required user setup; surfaced in `wiki/howtos/first-run-setup.md`.
- **Edge missed under focus change.** If Fn is held while focus changes (Spotlight, modal takeover, screen lock), the monitor may receive the up edge without the down or vice versa. `isPressed` tracking guards against duplicate `onPress` calls but cannot fabricate a missing `onRelease`. Same advisory as the existing `onRelease` note.
- **`addGlobalMonitorForEvents` returned nil.** Rare; system unable to install monitor. The entry is stored with a nil handle so unregister still cleans up, and a `[hotkey] failed to install global monitor for <trigger>` line is logged. Caller's token-and-unregister contract is preserved; the monitor simply never fires.
