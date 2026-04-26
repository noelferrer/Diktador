---
title: Hotkey Fn-key trigger + Input Monitoring permission flow
type: design
created: 2026-04-27
updated: 2026-04-27
status: draft
module: diktador-hotkey
---

# Hotkey Fn-key trigger + Input Monitoring permission flow

## Context

PR #2 shipped `HotkeyRegistry` over soffes/HotKey (Carbon Events). Carbon does not model the **Fn (🌐 globe)** key as a modifier and does not expose **sided** modifiers (Right-Option, Right-Command, etc.). The bare-Fn-held push-to-talk is the canonical Mac dictation UX (Whisper Flow, Glaido, macOS built-in dictation), and the user explicitly asked for it during Phase G of the previous PR.

This spec extends `HotkeyRegistry` with a parallel code path built on `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`, surfaces the **Input Monitoring** TCC permission required by that monitor, and rewires the v1 `AppDelegate` push-to-talk to use bare Fn. Right-side modifiers (`.rightOption`, etc.) share the same NSEvent foundation but ship in a follow-up — same mechanism, different API enumeration.

## Scope

In scope:

1. New `ModifierTrigger` value type — `.fn` only for v1.
2. New `register(modifierTrigger:onPress:onRelease:) -> RegistrationToken` overload on `HotkeyRegistry`.
3. New `InputMonitoringStatus` enum + `inputMonitoringPermission` getter on `HotkeyRegistry`.
4. New `requestInputMonitoringPermission(completion:)` method that triggers the macOS system prompt.
5. NSEvent global-flagsChanged path internal to `HotkeyRegistry`, with edge detection (Fn-down vs Fn-up).
6. `AppDelegate` rewired: Fn replaces Option+Space as the v1 push-to-talk. First-launch permission prompt + a "needs Input Monitoring" status-menu warning when denied.
7. Tests: `ModifierTrigger` value semantics; registry routing (Carbon path unchanged when given a `KeyCombo`, NSEvent path taken when given a `ModifierTrigger`); `RegistrationToken` lifecycle remains uniform across both paths.
8. Documentation: README "Public API", "Dependencies", "Known failure modes" updated; `memory/domains/hotkey.md` updated; new ADR `wiki/decisions/hotkey-modifier-only-trigger.md`.

Deliberately out of scope:

- Right-side modifiers (Right-Option-only, etc.). Filed for the follow-up PR.
- Conflict detection (still a v2 settings-module concern).
- User-configurable hotkey selection (settings module).
- Suppression of macOS's "Press 🌐 to" system action — a Mac-wide constraint, not solvable from a global monitor. Surfaced in the FAQ as required user setup ("Press 🌐 to → Do nothing").

## Architecture

`HotkeyRegistry` retains its single-class structure; no new module. Two parallel internal storage maps, one type-of-token for both:

```swift
private var carbonEntries:  [UUID: HotKey] = [:]            // soffes/HotKey instances
private var monitorEntries: [UUID: ModifierMonitorEntry] = [:]  // NSEvent monitors + state
```

`RegistrationToken` is unchanged — the `id: UUID` already carries enough to disambiguate; lookup tries both maps in `unregister`.

`ModifierMonitorEntry` (file-private struct) holds:

- `trigger: ModifierTrigger`
- `monitorHandle: Any` — the opaque return of `NSEvent.addGlobalMonitorForEvents`
- `localMonitorHandle: Any?` — paired local monitor so the registry also fires when Diktador itself has focus (global monitor is global-only, intentionally)
- `isPressed: Bool` — last seen edge state for the trigger's flag
- `onPress` / `onRelease` closures

### Components

1. **`ModifierTrigger` enum** (public, in a new file `ModifierTrigger.swift`):
   ```swift
   public enum ModifierTrigger: Hashable, Sendable {
       case fn
       // .rightOption, .rightCommand, etc. — reserved for the follow-up PR
   }
   ```
   Internal helper `private var flag: NSEvent.ModifierFlags` maps each case to the corresponding flag (`.function` for `.fn`).

2. **`InputMonitoringStatus` enum** (public, in a new file `InputMonitoringStatus.swift`):
   ```swift
   public enum InputMonitoringStatus: Sendable {
       case granted
       case denied
       case undetermined
   }
   ```
   Mapped from `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` results: `kIOHIDAccessTypeGranted` → `.granted`, `kIOHIDAccessTypeDenied` → `.denied`, `kIOHIDAccessTypeUnknown` → `.undetermined`.

3. **`HotkeyRegistry` extensions**:
   - `var inputMonitoringPermission: InputMonitoringStatus { get }` — synchronous, no side effects.
   - `func requestInputMonitoringPermission(completion: @escaping (InputMonitoringStatus) -> Void)` — calls `IOHIDRequestAccess`. macOS shows the consent prompt at most once per app-bundle/user pair; subsequent calls return the cached granted/denied state without re-prompting. The completion runs on the main queue.
   - `func register(modifierTrigger:onPress:onRelease:) -> RegistrationToken` — installs paired global+local NSEvent monitors keyed off `.flagsChanged`. Stores entry in `monitorEntries` and returns a fresh token. If `addGlobalMonitorForEvents` returns `nil` (rare; system unable to install monitor), the entry is stored with a `nil` global handle so unregister still cleans up cleanly, and a `[hotkey] failed to install global monitor for <trigger>` line is logged. The token is real either way; the caller's contract is unchanged.
   - `unregister(_:)` — extended to look in both maps; on `monitorEntries` removal, calls `NSEvent.removeMonitor` for whichever handles are non-nil.

   **Test seam.** `HotkeyRegistry` adds a second initializer `internal init(permissionProvider: PermissionProvider)` alongside the existing `public init()`. `PermissionProvider` is an internal protocol over `inputMonitoringPermission` and `requestInputMonitoringPermission`; the default real implementation wraps `IOHIDCheckAccess` / `IOHIDRequestAccess`. Tests construct the registry with a stub. Public surface is unchanged.

4. **`AppDelegate` rewiring**:
   - On `applicationDidFinishLaunching`: configure status item, then call `bootstrapPushToTalk()`.
   - `bootstrapPushToTalk()` checks `hotkeys.inputMonitoringPermission`:
     - `.granted` → register Fn trigger immediately, idle icon, normal flow.
     - `.undetermined` → call `requestInputMonitoringPermission`; on completion, recurse into `bootstrapPushToTalk()`.
     - `.denied` → swap status item to a warning state ("Diktador (needs Input Monitoring)"), add a menu item that opens System Settings → Privacy & Security → Input Monitoring (`x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`). No fallback hotkey in v1.

## Data flow

### Registration (Fn trigger):

```
AppDelegate.bootstrapPushToTalk()
  └─ HotkeyRegistry.register(modifierTrigger: .fn,
                             onPress: { setListening(true) },
                             onRelease: { setListening(false) })
       ├─ NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) → global handle
       ├─ NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) → local handle
       └─ monitorEntries[uuid] = ModifierMonitorEntry(...)
  → returns RegistrationToken
```

### Press (Fn down):

```
[user holds Fn]
  └─ NSEvent global+local monitor fires with event.modifierFlags
       └─ entry.handleFlagsChanged(event):
            let isPressedNow = event.modifierFlags.contains(.function)
            if isPressedNow && !entry.isPressed:
                entry.isPressed = true
                entry.onPress()
            if !isPressedNow && entry.isPressed:
                entry.isPressed = false
                entry.onRelease()
```

`onPress` triggers `AppDelegate.setListening(true)` → status icon flips to `mic.fill`.

### Release (Fn up):

Symmetric. `onRelease` → `setListening(false)` → icon flips back.

### Unregister:

```
HotkeyRegistry.unregister(token)
  └─ if entries[token.id] exists: drop HotKey instance (Carbon path)
  └─ else if monitorEntries[token.id] exists:
       ├─ NSEvent.removeMonitor(globalHandle)
       ├─ NSEvent.removeMonitor(localHandle) if present
       └─ monitorEntries.removeValue(forKey: token.id)
```

## Error handling / failure modes (new)

These extend the existing README failure-modes list:

- **Input Monitoring denied.** `register(modifierTrigger:)` still returns a valid token, but the OS silently delivers no `.flagsChanged` events to the monitor. Symptom: Fn press is dead. Mitigation: `AppDelegate` checks `inputMonitoringPermission` *before* registering and refuses to register on `.denied`, instead surfacing the warning state.

- **Permission revoked at runtime.** macOS allows the user to revoke Input Monitoring while Diktador is running; the app receives no notification. The monitors stay live but stop receiving events. v1 mitigation: none (acceptable; revocation is rare and Diktador will recover on next launch). Note for future: poll `inputMonitoringPermission` on `NSApplication.didBecomeActiveNotification` and re-bootstrap if it changed.

- **Edge missed (held Fn into focus change).** If Fn is held while focus changes — e.g., a Spotlight invocation — the global monitor may receive the up edge but not the down, or vice versa. `isPressed` tracking guards against duplicate `onPress` calls but cannot fabricate a missing `onRelease`. Same advisory as the existing module's "`onRelease` may not fire" note: callers impose their own timeout.

- **macOS "Press 🌐 to" system action.** If the user has Apple's globe-key behavior set to anything other than "Do nothing", pressing Fn will fire both Diktador's handler *and* the system action (start Apple Dictation, show emoji picker, etc.). Cannot be suppressed from a global monitor. **Required user setup**, surfaced in `wiki/howtos/first-run-setup.md` and a status-menu hint.

- **Multiple `register(modifierTrigger: .fn, ...)` calls.** Each install adds a fresh monitor pair. All pressed-down callbacks fire on each press; all pressed-up callbacks fire on each release. Same at-most-one-or-not semantics as the existing combo path: dedupe at the caller.

- **`activeRegistrationCount`** now sums `carbonEntries.count + monitorEntries.count`. Tests update accordingly.

## Testing strategy

`swift test` from `modules/diktador-hotkey/`. Three new test cases on top of the existing three:

1. **`ModifierTrigger` is `Hashable` and `Sendable` with the expected case identity** — guards against accidental enum reshape.
2. **`register(modifierTrigger:)` returns a unique token, increments `activeRegistrationCount` by 1, and `unregister` brings it back down** — same shape as the existing `KeyCombo` test, exercises the dual-map lookup in `unregister`.
3. **Registering both a `KeyCombo` and a `ModifierTrigger` increments the count by 2 and unregistering each independently decrements correctly** — verifies the two maps don't collide and the token disambiguation works.

Out of scope for unit tests (manual / computer-use verification only):

- The actual NSEvent global monitor firing on Fn press. This requires a hardware key event, the running app, and granted Input Monitoring — none of which the SwiftPM test runner provides. The plan covers a computer-use phase (granted-state path: press Fn, verify icon flip; denied-state path: revoke permission, verify warning state) the same way Phase G of PR #2 verified Option+Space.
- The `IOHIDCheckAccess` / `IOHIDRequestAccess` calls. Permission state is per-app-bundle and per-user, mocking it would require dependency-injecting the permission checker and is not worth the surface area for v1.

A test seam *is* added so this can be unit-tested later: the registry takes an internal `permissionProvider` defaulting to a real `IOHIDPermissionProvider` but accepting any conformer to a `PermissionProvider` protocol. The protocol stays internal in v1; promoted to public when the test demand justifies it.

## Open questions (decided)

- **Drop Option+Space from v1 default?** Yes. Fn is the new sole default. Settings module will reintroduce user choice. Justification: keeping both registered double-spends the user's mental model and complicates the "permission denied" UI.
- **Fallback hotkey on permission denial?** No. Denied state shows a warning + a "fix this" menu item; app is non-functional until granted. Acceptable because Input Monitoring is required for any future modifier-trigger feature anyway.
- **Sided modifiers in this PR?** No. Same NSEvent infrastructure but separate enum surface (`ModifierTrigger.rightOption` doesn't fit naturally next to `.fn` — it's a paired concept with the existing `KeyCombo.modifiers`). Follow-up PR will likely add a third API surface or extend `KeyCombo` with a `sidedness:` parameter.

## Documentation deliverables

- `modules/diktador-hotkey/README.md` — Public API and Dependencies sections updated; new failure modes added.
- `memory/domains/hotkey.md` — v1 configuration updated (Fn replaces Option+Space); Open questions block updated (Fn → done; right-side modifiers → still open; conflict detection → still open).
- `wiki/decisions/hotkey-modifier-only-trigger.md` — new ADR explaining the dual-path architecture (Carbon for keyed combos, NSEvent for modifier-only triggers) and the Input Monitoring permission consequence.
- `wiki/index.md` — Decisions section gets the new ADR.
- `wiki/howtos/first-run-setup.md` — new how-to: "Press 🌐 to: Do nothing" + Input Monitoring grant.
- `wiki/index.md` — Howtos section gets the new how-to.
- `log.md` — entries for `document` (ADR + how-to) and `meta` (PR ship).

## Module-rule check

1. **One feature.** Yes — "trigger callbacks on bare Fn press/release". Fits the existing module purpose (global hotkey registration).
2. **Boundary dependencies.** New: AppKit (already pulled), `IOKit.hid`, ApplicationServices for `IOHIDCheckAccess`. Declared at the top of the registry source.
3. **Own errors.** Permission failures surface through `InputMonitoringStatus`; monitor-creation failures (`nil` from `addGlobalMonitorForEvents`) are logged with the `[hotkey]` prefix and the entry is stored with a nil handle so the token-and-unregister contract still holds — same silent-degradation shape as the existing combo conflict mode.
4. **One public surface per module.** Still `HotkeyRegistry` and the value types it exposes. `ModifierTrigger`, `InputMonitoringStatus` are added to the public surface; nothing leaks from internals.
5. **No shared mutable state.** Two private dictionaries on the registry, accessed only on the main thread (per the existing thread-safety note).
6. **One communication style.** Direct calls. No registry/event escalation needed.
