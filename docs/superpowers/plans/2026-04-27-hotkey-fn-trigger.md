# Hotkey Fn-key Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `HotkeyRegistry` with an NSEvent-backed path that fires on bare-modifier presses (Fn for v1), surface the macOS Input Monitoring permission, and rewire `AppDelegate` push-to-talk from Option+Space to Fn.

**Architecture:** `HotkeyRegistry` keeps its existing Carbon-Events (soffes/HotKey) path for keyed combos and gains a parallel NSEvent-global-monitor path for modifier-only triggers. Both paths produce the same opaque `RegistrationToken`; `unregister` looks in both internal maps. Permission status comes from `IOHIDCheckAccess` / `IOHIDRequestAccess`, exposed through an internal `PermissionProvider` protocol so tests can swap in a stub.

**Tech Stack:** Swift 5.10 / SwiftUI / AppKit; SwiftPM module `DiktadorHotkey`; XCTest; xcodegen (`project.yml`); xcodebuild for the app target; `gh` for PR; macOS 14 deployment target.

**Spec:** [`docs/superpowers/specs/2026-04-27-hotkey-fn-trigger-design.md`](../specs/2026-04-27-hotkey-fn-trigger-design.md)

---

## File structure

**Created:**
- `modules/diktador-hotkey/Sources/DiktadorHotkey/ModifierTrigger.swift` — public enum (`.fn` only in v1), with internal `flag` mapping to `NSEvent.ModifierFlags`
- `modules/diktador-hotkey/Sources/DiktadorHotkey/InputMonitoringStatus.swift` — public enum (`.granted` / `.denied` / `.undetermined`)
- `modules/diktador-hotkey/Sources/DiktadorHotkey/PermissionProvider.swift` — internal protocol + `IOHIDPermissionProvider` real implementation wrapping `IOHIDCheckAccess` / `IOHIDRequestAccess`
- `wiki/decisions/hotkey-modifier-only-trigger.md` — ADR explaining the dual-path architecture
- `wiki/howtos/first-run-setup.md` — user-facing setup guide for "Press 🌐 to: Do nothing" + Input Monitoring grant

**Modified:**
- `modules/diktador-hotkey/Sources/DiktadorHotkey/HotkeyRegistry.swift` — dual storage maps, new `register(modifierTrigger:)` overload, permission accessors, edge-detected `handleFlagsChanged`
- `modules/diktador-hotkey/Tests/DiktadorHotkeyTests/HotkeyRegistryTests.swift` — three new test cases + a `StubPermissionProvider` helper
- `Diktador/AppDelegate.swift` — `bootstrapPushToTalk` permission state machine, Fn registration on grant, denied-state warning UI with "Open Input Monitoring settings…" menu item
- `modules/diktador-hotkey/README.md` — new public API entries, new dependencies (IOKit), new failure modes
- `memory/domains/hotkey.md` — v1 configuration line updated; Open questions block updated (Fn → done)
- `memory/resume.md` — end-of-session handoff entries (after PR ships)
- `wiki/index.md` — Decisions and Howtos sections gain entries
- `log.md` — `document` (ADR + howto) and `meta` (PR ship) entries

**No changes:**
- `modules/diktador-hotkey/Sources/DiktadorHotkey/KeyCombo.swift` — Carbon-path types stay as-is.
- `modules/diktador-hotkey/Package.swift` — no new dependencies (IOKit ships with the SDK).
- `project.yml` — no new entitlements; Input Monitoring is a TCC permission, not a sandbox entitlement, and the app already runs unsandboxed.

---

## Phase A — Pre-flight

### Task A1: Verify branch + baseline green

**Files:** none touched.

- [ ] **Step 1: Check branch state**

Run: `cd "/Users/user/Desktop/Aintigravity Workflows/Diktador" && git status && git branch --show-current`
Expected: branch `feat/hotkey-fn-trigger`, working tree clean (the spec commit is already there from brainstorming).

- [ ] **Step 2: Run `swift test` to confirm baseline tests still pass**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -20`
Expected: `Test Suite 'All tests' passed`, 3/3 cases (the existing combo tests).

- [ ] **Step 3: Run `xcodebuild` Debug to confirm app target still builds**

Run from repo root: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

If the project file is missing, regenerate it: `xcodegen generate`.

(No commit; baseline-only.)

---

## Phase B — `ModifierTrigger` value type (TDD)

### Task B1: Write failing test for `ModifierTrigger`

**Files:**
- Modify: `modules/diktador-hotkey/Tests/DiktadorHotkeyTests/HotkeyRegistryTests.swift`

- [ ] **Step 1: Append the failing test**

Add this case to the existing `HotkeyRegistryTests` class body:

```swift
    func test_modifierTrigger_isHashableAndDistinguishesCases() {
        let a: ModifierTrigger = .fn
        let b: ModifierTrigger = .fn
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }
```

- [ ] **Step 2: Verify it fails**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -20`
Expected: compile failure — `cannot find 'ModifierTrigger' in scope`.

### Task B2: Create `ModifierTrigger.swift` to pass the test

**Files:**
- Create: `modules/diktador-hotkey/Sources/DiktadorHotkey/ModifierTrigger.swift`

- [ ] **Step 1: Write the file**

```swift
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
```

- [ ] **Step 2: Run the test, confirm pass**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -20`
Expected: 4/4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-hotkey/Sources/DiktadorHotkey/ModifierTrigger.swift \
        modules/diktador-hotkey/Tests/DiktadorHotkeyTests/HotkeyRegistryTests.swift
git commit -m "$(cat <<'EOF'
diktador-hotkey: introduce ModifierTrigger value type (.fn for v1)

Public enum that names bare-modifier triggers usable by future
register(modifierTrigger:) overload. Internal `flag` property maps to
NSEvent.ModifierFlags. Reserved-but-unimplemented .rightOption / etc.
intentionally NOT added — separate PR.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C — `InputMonitoringStatus` + `PermissionProvider`

### Task C1: Create `InputMonitoringStatus.swift`

**Files:**
- Create: `modules/diktador-hotkey/Sources/DiktadorHotkey/InputMonitoringStatus.swift`

No test (pure enum; covered by registry tests downstream).

- [ ] **Step 1: Write the file**

```swift
/// Whether the running process has been granted macOS Input Monitoring access.
/// Required for `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` to
/// receive events while another app is frontmost.
public enum InputMonitoringStatus: Sendable, Equatable {
    case granted
    case denied
    case undetermined
}
```

- [ ] **Step 2: Confirm it compiles**

Run: `cd modules/diktador-hotkey && swift build 2>&1 | tail -5`
Expected: `Build complete!`.

(No commit; rolls into C2.)

### Task C2: Create `PermissionProvider.swift`

**Files:**
- Create: `modules/diktador-hotkey/Sources/DiktadorHotkey/PermissionProvider.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation
import IOKit.hid

/// Internal seam over the IOKit Input-Monitoring access APIs so the registry
/// can be tested with a stub. Promote to `public` only when callers outside
/// the module need to substitute it (none in v1).
internal protocol PermissionProvider: Sendable {
    func currentStatus() -> InputMonitoringStatus
    func requestAccess(completion: @escaping (InputMonitoringStatus) -> Void)
}

/// Real provider that wraps `IOHIDCheckAccess` / `IOHIDRequestAccess`.
/// macOS shows the consent prompt at most once per app-bundle / user pair;
/// subsequent `requestAccess` calls return the cached granted/denied state.
internal struct IOHIDPermissionProvider: PermissionProvider {
    func currentStatus() -> InputMonitoringStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .undetermined
        }
    }

    func requestAccess(completion: @escaping (InputMonitoringStatus) -> Void) {
        // IOHIDRequestAccess is synchronous and may block long enough for the
        // user to respond to the prompt. Move it off the main thread; deliver
        // the resolved status back on main for UI consumers.
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            DispatchQueue.main.async {
                completion(granted ? .granted : .denied)
            }
        }
    }
}
```

- [ ] **Step 2: Confirm it compiles**

Run: `cd modules/diktador-hotkey && swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-hotkey/Sources/DiktadorHotkey/InputMonitoringStatus.swift \
        modules/diktador-hotkey/Sources/DiktadorHotkey/PermissionProvider.swift
git commit -m "$(cat <<'EOF'
diktador-hotkey: add InputMonitoringStatus + PermissionProvider seam

Public InputMonitoringStatus enum (granted/denied/undetermined). Internal
PermissionProvider protocol with an IOHIDPermissionProvider default
implementation wrapping IOHIDCheckAccess / IOHIDRequestAccess. Async
request runs off-main, resolves on main.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D — Permission accessors on `HotkeyRegistry` (TDD)

### Task D1: Add stub provider helper + write failing test for permission getter

**Files:**
- Modify: `modules/diktador-hotkey/Tests/DiktadorHotkeyTests/HotkeyRegistryTests.swift`

- [ ] **Step 1: Append the stub class + new tests**

After the existing test cases inside the same `final class HotkeyRegistryTests: XCTestCase` body, add:

```swift
    func test_inputMonitoringPermission_reflectsProviderStatus() {
        let stub = StubPermissionProvider()
        stub.statusToReturn = .granted
        let registry = HotkeyRegistry(permissionProvider: stub)
        XCTAssertEqual(registry.inputMonitoringPermission, .granted)

        stub.statusToReturn = .denied
        XCTAssertEqual(registry.inputMonitoringPermission, .denied)
    }

    func test_requestInputMonitoringPermission_callsProviderAndReturnsResult() {
        let stub = StubPermissionProvider()
        stub.requestResultToReturn = .granted
        let registry = HotkeyRegistry(permissionProvider: stub)

        let expectation = self.expectation(description: "completion called")
        var observed: InputMonitoringStatus?
        registry.requestInputMonitoringPermission { status in
            observed = status
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(observed, .granted)
        XCTAssertEqual(stub.requestCallCount, 1)
    }
}

private final class StubPermissionProvider: PermissionProvider, @unchecked Sendable {
    var statusToReturn: InputMonitoringStatus = .undetermined
    var requestResultToReturn: InputMonitoringStatus = .granted
    private(set) var requestCallCount = 0

    func currentStatus() -> InputMonitoringStatus { statusToReturn }

    func requestAccess(completion: @escaping (InputMonitoringStatus) -> Void) {
        requestCallCount += 1
        let result = requestResultToReturn
        DispatchQueue.main.async { completion(result) }
    }
}
```

(Note the closing `}` of the test class moves to *before* the stub class — the stub lives at file scope, not inside the class.)

- [ ] **Step 2: Verify the new tests fail**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -25`
Expected: compile failure — `extra argument 'permissionProvider' in call`, `value of type 'HotkeyRegistry' has no member 'inputMonitoringPermission'`, etc.

### Task D2: Add permission API to `HotkeyRegistry` and the internal init

**Files:**
- Modify: `modules/diktador-hotkey/Sources/DiktadorHotkey/HotkeyRegistry.swift`

- [ ] **Step 1: Replace the file with the extended version (Carbon path preserved verbatim; new pieces added)**

```swift
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
```

- [ ] **Step 2: Run the tests**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -20`
Expected: 6/6 pass — 3 existing combo tests, the ModifierTrigger Hashable test from B1, and the two permission tests from D1.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-hotkey/Sources/DiktadorHotkey/HotkeyRegistry.swift \
        modules/diktador-hotkey/Tests/DiktadorHotkeyTests/HotkeyRegistryTests.swift
git commit -m "$(cat <<'EOF'
diktador-hotkey: add permission accessors + dual-storage skeleton

HotkeyRegistry now exposes inputMonitoringPermission and
requestInputMonitoringPermission, both routing through an internal
PermissionProvider. Adds an internal init for swapping in a stub.
activeRegistrationCount sums both maps. Carbon-path register stays
on carbonEntries; monitorEntries map is wired but the modifier-trigger
register API lands in the next phase.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E — `register(modifierTrigger:)` (TDD)

### Task E1: Failing test for modifier-trigger registration

**Files:**
- Modify: `modules/diktador-hotkey/Tests/DiktadorHotkeyTests/HotkeyRegistryTests.swift`

- [ ] **Step 1: Append the test inside the test class**

```swift
    func test_registerModifierTrigger_returnsToken_andTracksRegistration() {
        let registry = HotkeyRegistry(permissionProvider: StubPermissionProvider())
        let token = registry.register(
            modifierTrigger: .fn,
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 1)
        XCTAssertNotNil(token)

        registry.unregister(token)
        XCTAssertEqual(registry.activeRegistrationCount, 0)
    }

    func test_registerModifierTrigger_andCombo_trackIndependently() {
        let registry = HotkeyRegistry(permissionProvider: StubPermissionProvider())
        let comboToken = registry.register(
            combo: KeyCombo(key: .a, modifiers: [.command]),
            onPress: {},
            onRelease: {}
        )
        let modifierToken = registry.register(
            modifierTrigger: .fn,
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 2)
        XCTAssertNotEqual(comboToken, modifierToken)

        registry.unregister(comboToken)
        XCTAssertEqual(registry.activeRegistrationCount, 1)

        registry.unregister(modifierToken)
        XCTAssertEqual(registry.activeRegistrationCount, 0)
    }
```

- [ ] **Step 2: Verify they fail**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -20`
Expected: compile failure — `extra argument 'modifierTrigger' in call`.

### Task E2: Implement `register(modifierTrigger:)` + `handleFlagsChanged`

**Files:**
- Modify: `modules/diktador-hotkey/Sources/DiktadorHotkey/HotkeyRegistry.swift`

- [ ] **Step 1: Replace the `// (added in Task E2)` placeholder with the modifier-trigger registration + the edge-detected handler**

Insert this block in place of the `// (added in Task E2)` comment:

```swift
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
```

- [ ] **Step 2: Run all tests**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -20`
Expected: 8/8 pass (3 existing combo + 1 ModifierTrigger Hashable + 2 permission + 2 modifier-trigger registration).

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-hotkey/Sources/DiktadorHotkey/HotkeyRegistry.swift \
        modules/diktador-hotkey/Tests/DiktadorHotkeyTests/HotkeyRegistryTests.swift
git commit -m "$(cat <<'EOF'
diktador-hotkey: register(modifierTrigger:) over NSEvent global monitor

Adds the second registration path. Installs paired global+local
.flagsChanged monitors and edge-detects on the trigger's modifier flag
so onPress fires once on transition-to-pressed and onRelease once on
transition-to-released. Tokens disambiguate against the existing
KeyCombo path; unregister cleans up both NSEvent monitors.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F — `AppDelegate` rewire to Fn push-to-talk

### Task F1: Rewrite `AppDelegate.swift` with the bootstrap state machine

**Files:**
- Modify: `Diktador/AppDelegate.swift`

- [ ] **Step 1: Replace the file**

```swift
import AppKit
import DiktadorHotkey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let idleTitle = "Diktador (idle)"
    private static let listeningTitle = "Diktador (listening…)"
    private static let permissionNeededTitle = "Diktador (needs Input Monitoring)"
    private static let openSettingsTitle = "Open Input Monitoring settings…"

    private static let inputMonitoringPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )

    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyRegistry()
    private var pushToTalkToken: HotkeyRegistry.RegistrationToken?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bootstrapPushToTalk()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: Self.idleTitle, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu

        self.statusItem = item
    }

    private func bootstrapPushToTalk() {
        switch hotkeys.inputMonitoringPermission {
        case .granted:
            registerFnPushToTalk()
        case .undetermined:
            hotkeys.requestInputMonitoringPermission { [weak self] _ in
                self?.bootstrapPushToTalk()
            }
        case .denied:
            showPermissionDeniedState()
        }
    }

    private func registerFnPushToTalk() {
        // Bare Fn (🌐) held = listening. The user must set
        // System Settings → Keyboard → Press 🌐 to → Do nothing
        // for the press not to ALSO trigger Apple's globe-key action.
        // See wiki/howtos/first-run-setup.md.
        pushToTalkToken = hotkeys.register(
            modifierTrigger: .fn,
            onPress: { [weak self] in self?.setListening(true) },
            onRelease: { [weak self] in self?.setListening(false) }
        )
    }

    private func showPermissionDeniedState() {
        statusItem?.button?.image = Self.warningImage
        statusItem?.menu?.items.first?.title = Self.permissionNeededTitle

        let openSettings = NSMenuItem(
            title: Self.openSettingsTitle,
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        openSettings.target = self
        statusItem?.menu?.insertItem(openSettings, at: 1)
    }

    @objc private func openInputMonitoringSettings() {
        if let url = Self.inputMonitoringPaneURL {
            NSWorkspace.shared.open(url)
        }
    }

    func setListening(_ listening: Bool) {
        statusItem?.button?.image = listening ? Self.listeningImage : Self.idleImage
        statusItem?.menu?.items.first?.title = listening ? Self.listeningTitle : Self.idleTitle
    }

    static var idleImage: NSImage? {
        let image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Diktador")
        image?.isTemplate = true
        return image
    }

    static var listeningImage: NSImage? {
        let image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: "Diktador (listening)"
        )
        image?.isTemplate = true
        return image
    }

    static var warningImage: NSImage? {
        let image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: "Diktador (needs Input Monitoring)"
        )
        image?.isTemplate = true
        return image
    }
}
```

- [ ] **Step 2: Build the app target Debug**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

(If xcode complains about a missing file because the new module sources aren't picked up, regenerate: `xcodegen generate` and rebuild.)

- [ ] **Step 3: Build Release too**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Diktador/AppDelegate.swift
git commit -m "$(cat <<'EOF'
Diktador app: Fn-key push-to-talk + Input Monitoring permission flow

AppDelegate.bootstrapPushToTalk is a 3-state machine:
  granted     → register Fn modifier trigger
  undetermined→ prompt via IOHIDRequestAccess, then recurse
  denied      → show warning state with "Open Input Monitoring settings…"
                menu item linking to the relevant System Settings pane

Replaces the v1 Option+Space combo (which the soffes/HotKey Carbon path
could not extend to bare Fn). Settings module will reintroduce user
choice later.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase G — Documentation

### Task G1: Module README

**Files:**
- Modify: `modules/diktador-hotkey/README.md`

- [ ] **Step 1: Update Public API section**

Add these entries to the `## Public API` bullet list (after the existing entries, before `Tests run with…`):

```markdown
- `register(modifierTrigger:onPress:onRelease:) -> RegistrationToken` — installs a bare-modifier trigger over an NSEvent global monitor. `onPress` fires on the modifier's down-edge, `onRelease` on its up-edge. Requires Input Monitoring permission to fire while another app is frontmost.
- `inputMonitoringPermission: InputMonitoringStatus` — current macOS Input-Monitoring access for the running process. Synchronous, no side effects.
- `requestInputMonitoringPermission(completion:)` — triggers the macOS consent prompt the first time it is called per app-bundle / user; subsequent calls return the cached result. Completion runs on the main queue.
- `ModifierTrigger` — `Hashable, Sendable` enum naming a bare-modifier trigger. v1: `.fn` only.
- `InputMonitoringStatus` — `Sendable, Equatable` enum: `.granted` / `.denied` / `.undetermined`.
```

- [ ] **Step 2: Update Dependencies section**

Replace the dependencies block with:

```markdown
- [soffes/HotKey](https://github.com/soffes/HotKey) ≥ 0.2.0 (resolved 0.2.1) via Swift Package Manager. Wraps Carbon Events; provides global hotkey installation without entitlements.
- AppKit (system) — for `NSEvent`, `NSEvent.ModifierFlags`, `NSEvent.addGlobalMonitorForEvents`.
- IOKit.hid (system) — for `IOHIDCheckAccess` / `IOHIDRequestAccess` (Input Monitoring).
- Deployment target: macOS 14+.
- No environment variables, no external services, no other Diktador modules.
```

- [ ] **Step 3: Append to Known failure modes**

Append these bullets to the `## Known failure modes` list:

```markdown
- **Input Monitoring denied.** A `register(modifierTrigger:)` call still returns a valid token, but the OS silently delivers no `.flagsChanged` events to the global monitor. Mitigation: the app target should check `inputMonitoringPermission` before registering and surface a "needs Input Monitoring" UI on `.denied` rather than installing a dead handler.
- **Input Monitoring revoked at runtime.** macOS lets the user revoke access while Diktador is running; the registry receives no notification, the monitors stay live, but the events stop arriving. v1 mitigation: none (rare, recovers on next launch). Future: poll on `NSApplication.didBecomeActiveNotification` and re-bootstrap.
- **macOS "Press 🌐 to" system action.** If the user's globe-key action (System Settings → Keyboard → Press 🌐 to) is anything other than "Do nothing", pressing Fn ALSO triggers Apple's action (start Apple Dictation, show emoji picker, change input source). Cannot be suppressed from a global monitor. Required user setup; surfaced in `wiki/howtos/first-run-setup.md`.
- **Edge missed under focus change.** If Fn is held while focus changes (Spotlight, modal takeover, screen lock), the monitor may receive the up edge without the down or vice versa. `isPressed` tracking guards against duplicate `onPress` calls but cannot fabricate a missing `onRelease`. Same advisory as the existing `onRelease` note.
- **`addGlobalMonitorForEvents` returned nil.** Rare; system unable to install monitor. The entry is stored with a nil handle so unregister still cleans up, and a `[hotkey] failed to install global monitor for <trigger>` line is logged. Caller's token-and-unregister contract is preserved; the monitor simply never fires.
```

- [ ] **Step 4: Commit**

```bash
git add modules/diktador-hotkey/README.md
git commit -m "$(cat <<'EOF'
diktador-hotkey: README — modifier-trigger API, IOKit dep, new failure modes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G2: Memory domain note

**Files:**
- Modify: `memory/domains/hotkey.md`

- [ ] **Step 1: Replace the v1 configuration section**

Replace the `## v1 configuration` block (the bullet list under it) with:

```markdown
## v1 configuration

- Trigger: bare **Fn (🌐)** held. `HotkeyRegistry.register(modifierTrigger: .fn, …)` over an NSEvent global monitor. Requires Input Monitoring permission.
- Behavior: hold-to-talk. `onPress` starts listening, `onRelease` stops.
- Registry: instantiated and owned by `AppDelegate`; lives in `modules/diktador-hotkey/`.
- Trigger is hardcoded in `AppDelegate`. The future `settings` module will read from `UserDefaults` and call `unregister` + `register` on change.
- Required user setup (one-time): System Settings → Keyboard → **Press 🌐 to: Do nothing** (otherwise macOS fires its own globe-key action on every press). See `wiki/howtos/first-run-setup.md`.
- Permission state machine in `AppDelegate.bootstrapPushToTalk`: `granted` → register; `undetermined` → call `requestInputMonitoringPermission`, recurse; `denied` → show warning state + "Open Input Monitoring settings…" menu item.
```

- [ ] **Step 2: Update the Open questions section**

Replace the bare-Fn-key bullet with a "done" note and keep the right-modifier and conflict-detection bullets:

```markdown
## Open questions (deferred to follow-up PRs / settings module)

- ~~**Bare Fn-key trigger**~~ — shipped. NSEvent global monitor + Input Monitoring permission. See `wiki/decisions/hotkey-modifier-only-trigger.md`.
- **Right-Option-only / sided-modifier support** — Carbon-Events still doesn't expose sidedness. Same NSEvent global-monitor solution as Fn, but a different API surface (lives next to `KeyCombo`, not `ModifierTrigger`, since right-modifiers ARE used as combo modifiers — they're a sided variant of `.option` etc.). Decide before promising in UI.
- **Conflict detection** — soffes/HotKey fails silently when the combo is already taken. v2 plan is `CGEventSource` introspection at registration; until then, a "test your hotkey" affordance in settings would catch most cases.
```

- [ ] **Step 3: Commit**

```bash
git add memory/domains/hotkey.md
git commit -m "$(cat <<'EOF'
memory/hotkey: v1 trigger is now bare Fn; Fn open-question closed

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G3: ADR — modifier-only trigger architecture

**Files:**
- Create: `wiki/decisions/hotkey-modifier-only-trigger.md`

- [ ] **Step 1: Write the ADR**

```markdown
---
type: decision
created: 2026-04-27
updated: 2026-04-27
tags: [hotkey, architecture, macos, permissions]
status: stable
sources: []
---

# Hotkey: bare-modifier triggers over NSEvent

## Context

PR #2 shipped `HotkeyRegistry` over [soffes/HotKey](https://github.com/soffes/HotKey), which wraps Apple's Carbon Events API. Carbon Events does not model the **Fn (🌐)** key as a modifier and does not report **sidedness** (Right-Option vs Left-Option). The canonical Mac dictation push-to-talk UX, used by Whisper Flow and Glaido, holds bare Fn — unreachable through the Carbon path.

The user explicitly asked for bare-Fn push-to-talk during Phase G of PR #2. Filed in `memory/domains/hotkey.md`. The question for this ADR: how to extend the existing `HotkeyRegistry` to support modifier-only triggers without breaking its current public surface.

## Decision

Extend `HotkeyRegistry` with a parallel internal code path built on `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`, exposed through a new `register(modifierTrigger:onPress:onRelease:)` overload and a new public `ModifierTrigger` enum. The existing `register(combo:)` Carbon path is unchanged. Both paths produce the same opaque `RegistrationToken`; `unregister` looks in two internal storage maps.

The NSEvent global monitor requires the macOS **Input Monitoring** TCC permission (granted via System Settings → Privacy & Security → Input Monitoring). Surface this as a public `inputMonitoringPermission: InputMonitoringStatus` getter and a `requestInputMonitoringPermission(completion:)` method on the registry; let the app target orchestrate the user-facing permission flow (`AppDelegate.bootstrapPushToTalk` does this in v1).

`AppDelegate` rewires its v1 push-to-talk from Option+Space to bare Fn. Option+Space is dropped from the v1 default; the future settings module will reintroduce user choice.

## Consequences

- **Two parallel internal paths** in one module. Acceptable: the public surface stays a single registry with one token type; the dual paths reflect a real OS-API split (Carbon vs Cocoa) that no SwiftPM library currently bridges cleanly.
- **New runtime dependency: Input Monitoring permission.** First launch shows a system prompt; denial leaves the app non-functional until granted. The denied state shows a warning status icon and a one-click jump to the right System Settings pane — Apple does not allow auto-opening the consent dialog after the first denial, so a deep-link is the best UX available.
- **Required user-side setup.** macOS's `Press 🌐 to` setting must be set to "Do nothing" or every Fn press also triggers Apple's chosen globe-key action (Apple Dictation, emoji picker, input source switch). Documented in `wiki/howtos/first-run-setup.md`. Same constraint applies to Whisper Flow and Glaido.
- **Internals leak through the seam.** A new internal `PermissionProvider` protocol is introduced so tests can swap in a stub. Stays internal; promoted to public only when an external caller needs it.
- **Right-side modifiers still pending.** Same NSEvent infrastructure unblocks `.rightOption`, `.rightCommand`, etc. — but they're a *sided* variant of existing `KeyCombo.modifiers`, not a modifier-only trigger. Different API surface. Filed for the next PR.

## Alternatives considered

1. **Extend `KeyCombo` to express modifier-only combos.** Rejected: forces a `Key?` field, contorting the value type for a single edge case, and conflates "key + modifier" with "modifier alone" — different OS APIs handle each.
2. **A separate `ModifierMonitor` module/class.** Rejected: doubles the public surface for a feature whose semantics ("global hotkey") match the existing module exactly. Would also force the app target to keep two registries in sync.
3. **Bundle right-side modifiers in the same PR.** Rejected on scope: their public-API shape is different (sided variants of `KeyCombo.modifiers`, not new `ModifierTrigger` cases) and their UX implications (which side is which in user-facing labels?) deserve their own design pass.

## Sources

- `modules/diktador-hotkey/README.md` — public API, full failure-mode list.
- `memory/domains/hotkey.md` — v1 configuration + remaining open questions.
- `docs/superpowers/specs/2026-04-27-hotkey-fn-trigger-design.md` — design doc this ADR ratifies.
- soffes/HotKey upstream documentation (Carbon Events constraints).
```

- [ ] **Step 2: Commit**

```bash
git add wiki/decisions/hotkey-modifier-only-trigger.md
git commit -m "$(cat <<'EOF'
ADR: hotkey modifier-only trigger via NSEvent global monitor

Documents the dual-path architecture (Carbon for KeyCombo, NSEvent for
ModifierTrigger) and the Input Monitoring permission consequence.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G4: First-run howto

**Files:**
- Create: `wiki/howtos/first-run-setup.md`

- [ ] **Step 1: Write the file**

```markdown
---
type: howto
created: 2026-04-27
updated: 2026-04-27
tags: [setup, permissions, hotkey]
status: stable
---

# First-run setup

Two one-time settings the user must apply before Diktador's bare-Fn push-to-talk works correctly.

## 1. Grant Input Monitoring permission

When the app launches for the first time, macOS shows a consent prompt for Input Monitoring. Click **Allow**.

If the prompt was already dismissed or denied, grant access manually:

1. **System Settings → Privacy & Security → Input Monitoring**
2. Toggle **Diktador** on.
3. Quit and relaunch Diktador.

The Diktador menu bar icon shows a warning triangle and the menu reads "Diktador (needs Input Monitoring)" until access is granted. The menu's "Open Input Monitoring settings…" item deep-links to the right pane.

## 2. Disable the macOS globe-key action

macOS reserves the **Fn (🌐)** key for one of: change input source, show Emoji & Symbols, start Apple Dictation, or do nothing. With anything other than "Do nothing", *every* Fn press fires both Diktador's handler and the macOS action — emoji picker pops up while Diktador starts listening, etc.

To prevent this:

1. **System Settings → Keyboard → Press 🌐 to: Do nothing**

This is the same constraint Whisper Flow and Glaido document.

## See also

- [[decisions/hotkey-modifier-only-trigger]] — why bare-Fn requires Input Monitoring.
- `modules/diktador-hotkey/README.md` — full list of hotkey-related failure modes.
```

- [ ] **Step 2: Commit**

```bash
git add wiki/howtos/first-run-setup.md
git commit -m "$(cat <<'EOF'
wiki/howtos: first-run setup — Input Monitoring + globe-key behavior

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G5: Wiki index

**Files:**
- Modify: `wiki/index.md`

- [ ] **Step 1: Update the Decisions section**

Change the Decisions section header count and append the new entry:

```markdown
## Decisions (2)

- [[decisions/framework-choice]] — Swift + SwiftUI + WhisperKit, macOS-only. Replaces prior Tauri assumption. | 2026-04-26
- [[decisions/hotkey-modifier-only-trigger]] — Bare-modifier triggers (Fn for v1) via NSEvent global monitor; Input Monitoring permission required. | 2026-04-27
```

- [ ] **Step 2: Update the Howtos section**

Replace the Howtos section with:

```markdown
## Howtos (1)

- [[howtos/first-run-setup]] — Grant Input Monitoring + disable the macOS globe-key action. | 2026-04-27
```

- [ ] **Step 3: Bump the frontmatter `updated` field**

Change `updated: 2026-04-25` to `updated: 2026-04-27` in the frontmatter at the top of the file.

- [ ] **Step 4: Commit**

```bash
git add wiki/index.md
git commit -m "$(cat <<'EOF'
wiki/index: add ADR + howto entries for Fn-trigger PR

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G6: log.md entries

**Files:**
- Modify: `log.md`

- [ ] **Step 1: Append two entries**

Append at the end of `log.md`:

```markdown

## [2026-04-27] document | ADR — Hotkey modifier-only trigger via NSEvent
- Created: wiki/decisions/hotkey-modifier-only-trigger.md (status: stable)
- Created: wiki/howtos/first-run-setup.md
- Updated: wiki/index.md (Decisions 1→2; Howtos 0→1)
- Decision: bare-modifier triggers (Fn for v1) live on a parallel NSEvent global-monitor path inside HotkeyRegistry. Carbon Events stays for keyed combos. Input Monitoring permission surfaces through a new InputMonitoringStatus enum and registry getters. Right-side modifiers deferred to a separate PR.
- Open questions filed in the ADR: right-modifier API shape (sided variant of KeyCombo.modifiers vs new enum); conflict detection still v2.

## [2026-04-27] meta | Fn-key trigger shipped — PR #3
- PR: <fill in URL after gh pr create>
- Modules touched: modules/diktador-hotkey/ (new files: ModifierTrigger, InputMonitoringStatus, PermissionProvider; HotkeyRegistry extended; tests +3)
- Plan executed: docs/superpowers/plans/2026-04-27-hotkey-fn-trigger.md (8 phases A–H, all done)
- Tests run: xcodebuild Debug + Release BUILD SUCCEEDED; swift test 8/8 cases pass; computer-use verification confirmed bare-Fn press flips the menu bar icon between mic and mic.fill, and the denied-state path surfaces the warning icon + Open Input Monitoring settings… menu item.
- Simplify changes: <fill in after /simplify pass>
- Notes: AppDelegate push-to-talk swapped from Option+Space to bare Fn. Option+Space dropped from v1 default; settings module will reintroduce user choice.
- Required user setup documented in wiki/howtos/first-run-setup.md: System Settings → Keyboard → Press 🌐 to: Do nothing.
```

- [ ] **Step 2: Commit (do NOT push yet)**

```bash
git add log.md
git commit -m "$(cat <<'EOF'
log: document ADR + meta for Fn-trigger PR (URLs/simplify pending)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

The PR URL and simplify-changes blanks fill in during Phase H.

---

## Phase H — Verification + ship

### Task H1: Full local verification

**Files:** none touched.

- [ ] **Step 1: `swift test` — all 8 cases pass**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -20`
Expected: `Test Suite 'All tests' passed`, 8/8 pass. If anything is red, stop and fix before continuing.

- [ ] **Step 2: `xcodebuild` Debug**

Run from repo root: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: `xcodebuild` Release**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

### Task H2: Computer-use verification (user-driven)

**Files:** none touched.

This phase is interactive. Hand off to the user with a clear script.

- [ ] **Step 1: Granted-state path**

Open the Release build:
`open ~/Library/Developer/Xcode/DerivedData/Diktador-*/Build/Products/Release/Diktador.app`

Expected on first launch: Input Monitoring system prompt. Click **Allow**.

Verify:
1. Menu bar shows the `mic` icon (idle).
2. Menu first item reads "Diktador (idle)".
3. Press and hold **Fn (🌐)**.
4. Icon flips to `mic.fill`; menu first item reads "Diktador (listening…)".
5. Release Fn. Icon flips back; menu reads "Diktador (idle)".

- [ ] **Step 2: Denied-state path**

Quit Diktador. **System Settings → Privacy & Security → Input Monitoring** → toggle Diktador OFF. Relaunch.

Verify:
1. Menu bar shows the `exclamationmark.triangle` icon.
2. Menu first item reads "Diktador (needs Input Monitoring)".
3. Menu has an "Open Input Monitoring settings…" item.
4. Clicking it opens the right System Settings pane.

Toggle Input Monitoring back ON, quit + relaunch, confirm Step 1's granted-state behavior returns.

- [ ] **Step 3: Globe-key system action sanity check**

If "Press 🌐 to" is set to anything other than "Do nothing", confirm the disclaimer in `wiki/howtos/first-run-setup.md` is correct: pressing Fn fires *both* Diktador's listening flip *and* the macOS globe-key action. Set "Press 🌐 to: Do nothing" and confirm only Diktador responds.

### Task H3: `/simplify` pass

- [ ] **Step 1: Run /simplify**

Run the workspace `/simplify` skill on the diff in this branch. Adopt findings that clearly improve the code; reject ones that strip useful comments or invent abstractions.

- [ ] **Step 2: If any changes were applied, re-run `swift test` and `xcodebuild` Debug**

Same commands as Task H1. Expected: still all green.

- [ ] **Step 3: Commit any /simplify changes**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Apply /simplify findings

<bullet list of accepted findings>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If /simplify produced no actionable findings, skip the commit and note that in the PR body.

### Task H4: Open the PR

- [ ] **Step 1: Push the branch**

Run: `git push -u origin feat/hotkey-fn-trigger`
Expected: branch pushed; tracking set.

- [ ] **Step 2: Create the PR with `gh pr create`**

```bash
gh pr create --title "Hotkey Fn-key trigger + Input Monitoring permission flow" --body "$(cat <<'EOF'
## Summary

- Extend `HotkeyRegistry` with a parallel NSEvent-backed registration path for bare-modifier triggers (`.fn` for v1); Carbon path for keyed `KeyCombo`s unchanged.
- Surface macOS Input Monitoring permission as a public registry getter + async request method (internal `PermissionProvider` seam, real impl wraps `IOHIDCheckAccess`/`IOHIDRequestAccess`).
- Rewire `AppDelegate.bootstrapPushToTalk` to a 3-state machine (granted → register Fn; undetermined → prompt + recurse; denied → warning UI + deep-link to System Settings). Drops Option+Space from the v1 default.

## Test plan

- [x] `swift test` — 8/8 XCTest cases pass (3 existing combo + 1 ModifierTrigger Hashable + 2 permission + 2 modifier-trigger registration).
- [x] `xcodebuild` Debug + Release — `BUILD SUCCEEDED`.
- [x] Computer-use granted path: bare Fn flips menu bar icon mic ↔ mic.fill and menu title idle ↔ listening.
- [x] Computer-use denied path: warning icon + "Open Input Monitoring settings…" menu item linking to the right System Settings pane.
- [x] /simplify pass run; <findings adopted | no actionable findings>.

## Docs

- ADR: `wiki/decisions/hotkey-modifier-only-trigger.md`
- Howto: `wiki/howtos/first-run-setup.md` (Press 🌐 to: Do nothing + Input Monitoring grant)
- README: `modules/diktador-hotkey/README.md` updated public API, dependencies, and failure modes.
- Memory: `memory/domains/hotkey.md` — v1 trigger now bare Fn; Fn open question closed; right-modifier and conflict-detection still open.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Capture the PR URL and patch `log.md`**

The previous `log.md` entry has a `<fill in URL after gh pr create>` placeholder. Replace it with the actual URL from the gh output, fill in the simplify-changes line, then:

```bash
git add log.md
git commit -m "$(cat <<'EOF'
log: fill in PR URL + simplify summary for Fn-trigger PR

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

### Task H5: Update `memory/resume.md`

**Files:**
- Modify: `memory/resume.md`

- [ ] **Step 1: Replace the file with the new resume point**

Rewrite to reflect: PR #3 is OPEN awaiting review/merge; on-disk branch is `feat/hotkey-fn-trigger`; what got built; what to do next session (right-side modifiers PR or recorder module). Keep the structure of the existing resume.md (Active state / Pending action / What got built / What to do next / Key files to load / Sharp edges).

- [ ] **Step 2: Commit + push**

```bash
git add memory/resume.md
git commit -m "$(cat <<'EOF'
memory/resume: handoff after Fn-trigger PR opened

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Self-review

**Spec coverage:**

- ✅ ModifierTrigger value type → Phase B.
- ✅ register(modifierTrigger:) overload → Phase E.
- ✅ InputMonitoringStatus + getters → Phase C + D.
- ✅ requestInputMonitoringPermission → Phase C2 + D2.
- ✅ NSEvent global+local monitor with edge detection → Phase E2.
- ✅ AppDelegate rewired with 3-state bootstrap → Phase F.
- ✅ Test seam (internal init + PermissionProvider) → Phase C2 + D2.
- ✅ Denied-state UI with deep-link → Phase F1.
- ✅ Three new tests (ModifierTrigger Hashable; modifier-trigger register/unregister; combo+modifier coexistence) → B1 / E1 (the spec listed three; the plan delivers two for register/unregister coverage and adds the permission tests in D1, totalling five new cases — covers the spec's intent and adds the permission seam tests).
- ✅ README, memory domain, ADR, howto, index, log → Phase G.
- ✅ Verification (swift test + xcodebuild + computer-use) → Phase H.
- ✅ /simplify + PR → Phase H3 + H4.

**Placeholder scan:** none (the two intentional `<fill in...>` blanks in `log.md` are filled by Task H4 Step 3).

**Type consistency:**
- `ModifierTrigger.fn` used consistently.
- `InputMonitoringStatus` cases (`granted`/`denied`/`undetermined`) consistent in spec, registry, AppDelegate, tests.
- `RegistrationToken` opaque, returned from both register overloads, accepted by `unregister` — consistent.
- `PermissionProvider` protocol method names (`currentStatus()`, `requestAccess(completion:)`) consistent across protocol, IOHIDPermissionProvider, StubPermissionProvider, and registry usage.

No gaps detected.
