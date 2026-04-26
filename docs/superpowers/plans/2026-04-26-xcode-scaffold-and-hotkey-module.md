# Xcode Scaffold + Hotkey Module — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a buildable `Diktador.app` menu bar app that responds to a global **Right-Option hold** by toggling its menu bar icon between "idle" and "listening" states. No transcription, no recording — purely the input-detection plumbing wrapped in the first proper Diktador module (`hotkey`).

**Architecture:** Single Xcode project at workspace root (`Diktador.xcodeproj`). The `hotkey` module is a local Swift Package at `modules/hotkey/` consumed by the main app target. The third-party [`soffes/HotKey`](https://github.com/soffes/HotKey) library (Carbon Events wrapper) is the only dependency in the module; the rest of the app talks to our `HotkeyRegistry` API, never to `HotKey` directly. This keeps fault isolation per `AGENTS.md` rule 4 (one public surface per module).

**Tech Stack:** Swift 5.10+, SwiftUI (menu bar), AppKit (`NSStatusItem`), soffes/HotKey via SPM, XCTest, macOS 14+ deployment target.

**Prereq:** PR #1 (workspace bootstrap) merged to `main` so the schema, `/go` skill, and ADR are visible from the trunk before this work branches.

---

## File structure (decomposition lock-in)

| Path | Responsibility |
|---|---|
| `Diktador.xcodeproj/` | Xcode project (generated; commit it; gitignore xcuserdata). Single workspace, single app target. |
| `Diktador/DiktadorApp.swift` | SwiftUI app entry. Sets up the AppDelegate and otherwise idles. |
| `Diktador/AppDelegate.swift` | Owns the `NSStatusItem`, instantiates `HotkeyRegistry`, swaps icon on press/release. |
| `Diktador/Info.plist` | `LSUIElement = YES` (no Dock icon); minimum macOS 14. |
| `Diktador/Assets.xcassets/StatusIdle.imageset/` | Menu bar icon, idle state (template image, monochrome). |
| `Diktador/Assets.xcassets/StatusListening.imageset/` | Menu bar icon, listening state (template image, monochrome with red dot). |
| `modules/hotkey/Package.swift` | Swift Package manifest. Declares `Hotkey` library + `HotkeyTests` test target. Depends on `soffes/HotKey`. |
| `modules/hotkey/Sources/Hotkey/HotkeyRegistry.swift` | The module's single public type. Wraps `HotKey`, exposes `register(combo:onPress:onRelease:) -> RegistrationToken`, `unregister(_:)`. |
| `modules/hotkey/Sources/Hotkey/KeyCombo.swift` | Public re-export of `HotKey.KeyCombo` so the rest of the app never imports `HotKey` directly. |
| `modules/hotkey/Tests/HotkeyTests/HotkeyRegistryTests.swift` | XCTest cases for registry state (registration storage, unregister removes, double-register rejected). The actual key-press → callback path is verified end-to-end in Phase G via computer use, since OS hotkeys can't fire from a unit test. |
| `modules/hotkey/README.md` | Per `AGENTS.md` template: Purpose / Public API / Dependencies / Known failure modes. |
| `memory/domains/hotkey.md` | Operational notes that don't belong in the module README (debugging tricks, OS quirks discovered during build). |

---

## Phase A — Branch and prep (~3 min)

### Task A1: Create feature branch off updated main

**Files:** none

- [ ] **Step 1:** Confirm PR #1 is merged

```bash
gh pr view 1 --json state,mergedAt
```
Expected: `"state":"MERGED"` and a non-null `mergedAt`. If still open, **stop** and merge it before continuing — branching from `feat/initialize-workspace` would create a stacked PR.

- [ ] **Step 2:** Sync local main and branch

```bash
cd "/Users/user/Desktop/Aintigravity Workflows/Diktador"
git checkout main
git pull origin main
git checkout -b feat/hotkey-module
```

- [ ] **Step 3:** Verify branch state

```bash
git status
git log --oneline -3
```
Expected: clean working tree; latest commit is the merge of PR #1 on main.

---

## Phase B — Xcode project scaffold (~12 min)

### Task B1: Create the Xcode project

**Files:** Creates `Diktador.xcodeproj/`, `Diktador/`.

- [ ] **Step 1:** Open Xcode → File → New → Project

  - Template: **macOS** → **App**
  - Product Name: `Diktador`
  - Team: (your personal team or "None" — signing is not needed for personal use)
  - Organization Identifier: `com.noelferrer`
  - Bundle Identifier (auto-derived): `com.noelferrer.Diktador`
  - Interface: **SwiftUI**
  - Language: **Swift**
  - Storage: **None**
  - Include Tests: **No** (the hotkey module brings its own tests; the app target has no logic worth testing yet)
  - Save location: the workspace root, `/Users/user/Desktop/Aintigravity Workflows/Diktador/`. **Uncheck** "Create Git repository on my Mac" — the repo already exists.

- [ ] **Step 2:** Set deployment target

  Select the project in the navigator → `Diktador` target → **General** tab → **Minimum Deployments** → macOS = `14.0`.

- [ ] **Step 3:** Make it a menu bar app (no Dock icon)

  Open `Diktador/Info.plist` (or the **Info** tab on the target). Add:
  - Key: `Application is agent (UIElement)` (`LSUIElement`)
  - Type: Boolean
  - Value: `YES`

- [ ] **Step 4:** Verify it builds

  ```bash
  cd "/Users/user/Desktop/Aintigravity Workflows/Diktador"
  xcodebuild -project Diktador.xcodeproj -scheme Diktador -destination 'platform=macOS' build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5:** Add `xcuserdata/` to `.gitignore` (already covered by the existing `.gitignore`'s `xcuserdata/` line — verify)

  ```bash
  grep -n "xcuserdata" .gitignore
  ```
  Expected: at least one line matching. If not, add it.

- [ ] **Step 6:** Commit

  ```bash
  git add Diktador.xcodeproj Diktador/
  git status  # confirm xcuserdata is NOT staged
  git commit -m "Scaffold Diktador Xcode project as menu bar app (LSUIElement)"
  ```

### Task B2: Replace default ContentView/window logic with menu bar setup

**Files:**
- Modify: `Diktador/DiktadorApp.swift`
- Create: `Diktador/AppDelegate.swift`
- Delete: `Diktador/ContentView.swift` (Xcode generates it; we don't need it yet)

- [ ] **Step 1:** Replace `Diktador/DiktadorApp.swift` contents

```swift
import SwiftUI

@main
struct DiktadorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

Note: `Settings { EmptyView() }` gives us a menu-bar-only app with no main window. A real settings window will replace `EmptyView()` in a later module.

- [ ] **Step 2:** Create `Diktador/AppDelegate.swift`

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Diktador")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Diktador (idle)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        self.statusItem = item
    }
}
```

We use the SF Symbol `mic` as a temporary icon. Custom assets land in Task B3.

- [ ] **Step 3:** Delete the unused ContentView

```bash
rm Diktador/ContentView.swift
```
Then in Xcode: select `ContentView.swift` in the navigator → Delete → Move to Trash. (If you only `rm` from disk, the project still references the file and the build will fail.)

- [ ] **Step 4:** Build and run

```bash
xcodebuild -project Diktador.xcodeproj -scheme Diktador -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Then run the built `.app`:
```bash
open "$(xcodebuild -project Diktador.xcodeproj -scheme Diktador -showBuildSettings 2>/dev/null | awk '/CONFIGURATION_BUILD_DIR/ {print $3}' | head -1)/Diktador.app"
```
Expected: a microphone icon appears in the menu bar; clicking it shows "Diktador (idle)" + "Quit". No Dock icon.

- [ ] **Step 5:** Commit

```bash
git add Diktador/
git commit -m "Wire menu bar icon and quit menu via NSStatusItem"
```

### Task B3: Add custom menu bar icon assets

**Files:**
- Create: `Diktador/Assets.xcassets/StatusIdle.imageset/Contents.json`
- Create: `Diktador/Assets.xcassets/StatusIdle.imageset/idle.pdf` (or 1x/2x/3x PNG triplet)
- Create: `Diktador/Assets.xcassets/StatusListening.imageset/Contents.json`
- Create: `Diktador/Assets.xcassets/StatusListening.imageset/listening.pdf`

For the first build, we can defer custom assets and stay on SF Symbols (`mic` and `mic.fill`). This task is **optional for v1** — if you want to ship Phase G with SF Symbols only, skip directly to B4 and use `mic` / `mic.fill` in `AppDelegate.swift`. If you want custom assets:

- [ ] **Step 1:** In Xcode, open `Assets.xcassets`. Right-click → New Image Set. Name it `StatusIdle`. Drag in a 22x22 monochrome PNG (or PDF) for the idle state. In the Attributes inspector → **Render As: Template Image**.
- [ ] **Step 2:** Repeat for `StatusListening` (red dot or filled mic).
- [ ] **Step 3:** Update `AppDelegate.swift` `applicationDidFinishLaunching` to use the assets:

```swift
item.button?.image = NSImage(named: "StatusIdle")
item.button?.image?.isTemplate = true
```

- [ ] **Step 4:** Build, run, verify icon renders correctly in both light and dark menu bar themes.
- [ ] **Step 5:** Commit `git commit -m "Add StatusIdle/StatusListening menu bar icon assets"`.

### Task B4: Switch to SF Symbol pair (skip if B3 was done)

If skipping B3, update `AppDelegate.swift` so the app uses two states (`mic` for idle, `mic.fill` for listening) and exposes a method to swap. This sets up the Phase E wire-up.

- [ ] **Step 1:** Update `Diktador/AppDelegate.swift`

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Diktador (idle)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        self.statusItem = item
    }

    func setListening(_ listening: Bool) {
        statusItem?.button?.image = listening ? Self.listeningImage : Self.idleImage
        statusItem?.button?.image?.isTemplate = true
        statusItem?.menu?.items.first?.title = listening ? "Diktador (listening…)" : "Diktador (idle)"
    }

    private static var idleImage: NSImage? {
        NSImage(systemSymbolName: "mic", accessibilityDescription: "Diktador")
    }

    private static var listeningImage: NSImage? {
        NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Diktador (listening)")
    }
}
```

- [ ] **Step 2:** Build and run

```bash
xcodebuild -project Diktador.xcodeproj -scheme Diktador -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: success; visual unchanged (icon still `mic`).

- [ ] **Step 3:** Commit

```bash
git add Diktador/AppDelegate.swift
git commit -m "Add idle/listening icon toggle on AppDelegate (SF Symbols)"
```

---

## Phase C — Hotkey module package (~6 min)

### Task C1: Create the Swift Package skeleton

**Files:**
- Create: `modules/hotkey/Package.swift`
- Create: `modules/hotkey/Sources/Hotkey/.keep`
- Create: `modules/hotkey/Tests/HotkeyTests/.keep`

- [ ] **Step 1:** Create the directory tree

```bash
mkdir -p modules/hotkey/Sources/Hotkey modules/hotkey/Tests/HotkeyTests
touch modules/hotkey/Sources/Hotkey/.keep modules/hotkey/Tests/HotkeyTests/.keep
```

- [ ] **Step 2:** Write `modules/hotkey/Package.swift`

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Hotkey",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Hotkey", targets: ["Hotkey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "Hotkey",
            dependencies: [
                .product(name: "HotKey", package: "HotKey"),
            ]
        ),
        .testTarget(
            name: "HotkeyTests",
            dependencies: ["Hotkey"]
        ),
    ]
)
```

- [ ] **Step 3:** Resolve and build the package standalone

```bash
cd modules/hotkey
swift package resolve 2>&1 | tail -3
swift build 2>&1 | tail -3
cd ../..
```
Expected: dependency `HotKey` fetched; build succeeds (will warn that the target has no source files yet; that's fine until C2).

- [ ] **Step 4:** Commit the package skeleton (we'll commit again after the implementation lands)

```bash
git add modules/hotkey/
git commit -m "Add hotkey module package skeleton (Swift Package, soffes/HotKey dep)"
```

### Task C2: Add the package as a local dependency to the app target

**Files:** modifies `Diktador.xcodeproj/project.pbxproj` (via Xcode UI).

- [ ] **Step 1:** In Xcode → File → Add Package Dependencies → **Add Local…** → select `modules/hotkey/` → Add Package. Confirm `Hotkey` library is checked under the `Diktador` app target.

- [ ] **Step 2:** Build to verify the link works

```bash
xcodebuild -project Diktador.xcodeproj -scheme Diktador -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. Xcode will show `Hotkey` and `HotKey` (the soffes one) as resolved packages.

- [ ] **Step 3:** Commit

```bash
git add Diktador.xcodeproj
git commit -m "Link hotkey module to Diktador app target as local SPM dependency"
```

---

## Phase D — Hotkey module API (TDD, ~14 min)

### Task D1: Failing test — registry stores callbacks under a token

**Files:**
- Create: `modules/hotkey/Tests/HotkeyTests/HotkeyRegistryTests.swift`

- [ ] **Step 1:** Write the failing test

```swift
import XCTest
@testable import Hotkey

final class HotkeyRegistryTests: XCTestCase {
    func test_register_returnsToken_andTracksRegistration() {
        let registry = HotkeyRegistry()
        let token = registry.register(
            combo: KeyCombo(key: .a, modifiers: [.command]),
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 1)
        XCTAssertNotNil(token)
    }
}
```

- [ ] **Step 2:** Run, verify failure

```bash
cd modules/hotkey
swift test --filter HotkeyRegistryTests/test_register_returnsToken_andTracksRegistration 2>&1 | tail -10
cd ../..
```
Expected: build error — `HotkeyRegistry` not defined.

### Task D2: Minimal implementation to pass D1

**Files:**
- Create: `modules/hotkey/Sources/Hotkey/HotkeyRegistry.swift`
- Create: `modules/hotkey/Sources/Hotkey/KeyCombo.swift`

- [ ] **Step 1:** Create `modules/hotkey/Sources/Hotkey/KeyCombo.swift`

```swift
import HotKey

public typealias Key = HotKey.Key
public typealias Modifier = NSEvent.ModifierFlags

public struct KeyCombo: Hashable, Sendable {
    public let key: Key
    public let modifiers: Modifier

    public init(key: Key, modifiers: Modifier) {
        self.key = key
        self.modifiers = modifiers
    }
}
```

- [ ] **Step 2:** Create `modules/hotkey/Sources/Hotkey/HotkeyRegistry.swift`

```swift
import AppKit
import HotKey

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

    public func unregister(_ token: RegistrationToken) {
        entries.removeValue(forKey: token.id)
    }
}
```

- [ ] **Step 3:** Run test, verify it passes

```bash
cd modules/hotkey
swift test --filter HotkeyRegistryTests/test_register_returnsToken_andTracksRegistration 2>&1 | tail -5
cd ../..
```
Expected: PASS.

- [ ] **Step 4:** Commit

```bash
git add modules/hotkey/Sources/ modules/hotkey/Tests/
git commit -m "Add HotkeyRegistry with register() returning a token"
```

### Task D3: Failing test — unregister removes the entry

- [ ] **Step 1:** Append to `HotkeyRegistryTests.swift`

```swift
extension HotkeyRegistryTests {
    func test_unregister_removesEntry() {
        let registry = HotkeyRegistry()
        let token = registry.register(
            combo: KeyCombo(key: .b, modifiers: [.option]),
            onPress: {},
            onRelease: {}
        )
        XCTAssertEqual(registry.activeRegistrationCount, 1)

        registry.unregister(token)

        XCTAssertEqual(registry.activeRegistrationCount, 0)
    }
}
```

- [ ] **Step 2:** Run, verify it passes (the implementation in D2 already covers this)

```bash
cd modules/hotkey
swift test 2>&1 | tail -5
cd ../..
```
Expected: 2 tests pass. (TDD purist note: this test was anticipated by D2's implementation. If you want to enforce strict red-green-refactor, write D3's test before adding `unregister` in D2 and split the implementation.)

- [ ] **Step 3:** Commit

```bash
git add modules/hotkey/Tests/HotkeyTests/HotkeyRegistryTests.swift
git commit -m "Test that unregister removes the registry entry"
```

### Task D4: Failing test — registering an already-registered combo on the same registry returns a fresh token but does not collide

- [ ] **Step 1:** Append to `HotkeyRegistryTests.swift`

```swift
extension HotkeyRegistryTests {
    func test_registeringTwice_yieldsDistinctTokens() {
        let registry = HotkeyRegistry()
        let combo = KeyCombo(key: .c, modifiers: [.command])
        let t1 = registry.register(combo: combo, onPress: {}, onRelease: {})
        let t2 = registry.register(combo: combo, onPress: {}, onRelease: {})
        XCTAssertNotEqual(t1, t2)
        XCTAssertEqual(registry.activeRegistrationCount, 2)
    }
}
```

This documents that the registry doesn't dedupe by combo — that's a v2 concern. For v1 the *caller* is responsible for not double-registering.

- [ ] **Step 2:** Run, verify it passes

```bash
cd modules/hotkey
swift test 2>&1 | tail -5
cd ../..
```
Expected: 3 tests pass.

- [ ] **Step 3:** Commit

```bash
git add modules/hotkey/Tests/HotkeyTests/HotkeyRegistryTests.swift
git commit -m "Test distinct tokens for repeated registration of the same combo"
```

---

## Phase E — Wire to the menu bar icon (~6 min)

The hotkey module is now testable. Wire it into the app so a real key press toggles the menu bar icon.

### Task E1: Inject HotkeyRegistry into AppDelegate

**Files:**
- Modify: `Diktador/AppDelegate.swift`

- [ ] **Step 1:** Replace `Diktador/AppDelegate.swift` with:

```swift
import AppKit
import Hotkey

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyRegistry()
    private var pushToTalkToken: HotkeyRegistry.RegistrationToken?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        registerPushToTalk()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Diktador (idle)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        self.statusItem = item
    }

    private func registerPushToTalk() {
        // v1 default: hold Right-Option = listening. Hardcoded; settings UI will replace this in a later module.
        // soffes/HotKey doesn't distinguish left vs right modifiers; we use plain Option for now and refine in the
        // settings module when KeyCombo is user-configurable.
        let combo = KeyCombo(key: .f13, modifiers: [.option])
        pushToTalkToken = hotkeys.register(
            combo: combo,
            onPress: { [weak self] in self?.setListening(true) },
            onRelease: { [weak self] in self?.setListening(false) }
        )
    }

    private func setListening(_ listening: Bool) {
        statusItem?.button?.image = listening ? Self.listeningImage : Self.idleImage
        statusItem?.button?.image?.isTemplate = true
        statusItem?.menu?.items.first?.title = listening ? "Diktador (listening…)" : "Diktador (idle)"
    }

    private static var idleImage: NSImage? {
        NSImage(systemSymbolName: "mic", accessibilityDescription: "Diktador")
    }

    private static var listeningImage: NSImage? {
        NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Diktador (listening)")
    }
}
```

**Note on the hotkey choice:** soffes/HotKey wraps Carbon Events, which doesn't distinguish left- from right-modifier. The ADR proposed Right-Option specifically; supporting that requires raw `NSEvent` monitoring instead of `HotKey`. We use `Option + F13` here as a v1 stand-in (uncommon enough not to collide with system shortcuts; lets us validate the wiring). The "Right-Option only" refinement is filed as a follow-up question in `memory/domains/hotkey.md`.

- [ ] **Step 2:** Build

```bash
xcodebuild -project Diktador.xcodeproj -scheme Diktador -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3:** Run and **manually** verify (this is computer-use territory; documented in Phase G)

```bash
open "$(xcodebuild -project Diktador.xcodeproj -scheme Diktador -showBuildSettings 2>/dev/null | awk '/CONFIGURATION_BUILD_DIR/ {print $3}' | head -1)/Diktador.app"
```

Hold **Option + F13**: menu bar icon flips from `mic` to `mic.fill`, menu first row text updates to "Diktador (listening…)". Release: icon and text revert. (If F13 is unavailable on your keyboard, edit the KeyCombo to `.space` for the smoke test, then revert. Don't ship `.space` — it'll collide with everything.)

- [ ] **Step 4:** Quit the running app

```bash
osascript -e 'tell application "Diktador" to quit' 2>/dev/null || pkill -x Diktador
```

- [ ] **Step 5:** Commit

```bash
git add Diktador/AppDelegate.swift
git commit -m "Wire hotkey module to menu bar icon (Option+F13 push-to-talk)"
```

---

## Phase F — Module README + memory updates (~5 min)

### Task F1: Write the module README

**Files:**
- Create: `modules/hotkey/README.md`

- [ ] **Step 1:** Write `modules/hotkey/README.md`

```markdown
# hotkey

## Purpose

Register a global keyboard shortcut and deliver press/release callbacks. Wraps soffes/HotKey so the rest of the app never imports HotKey directly.

## Public API

- `HotkeyRegistry()` — instantiate.
- `register(combo:onPress:onRelease:) -> RegistrationToken` — register a combo and receive a token.
- `unregister(_ token:)` — remove the registration; subsequent press/release of that combo will no longer fire callbacks.
- `KeyCombo(key: Key, modifiers: Modifier)` — value type for combo definitions; `Key` and `Modifier` are re-exports of `HotKey.Key` and `NSEvent.ModifierFlags`.
- `activeRegistrationCount: Int` — for tests/diagnostics.

Test scheme: `swift test` from `modules/hotkey/`.

## Dependencies

- `soffes/HotKey` (≥ 0.2.0) via Swift Package Manager.
- AppKit (system).
- Deployment target: macOS 14+.

No env vars, no external services.

## Known failure modes

- **Combo conflict at registration** — soffes/HotKey silently fails to fire the callback if the OS or another app has already claimed the combo. There is no error returned. Diagnose by registering a known-unique combo (e.g., `Control+Option+Command+\` ) and checking that fires; if it does, the original combo was claimed elsewhere. v1 mitigation: pick uncommon combos. v2 will surface conflicts via `CGEventSource` introspection.
- **No left-vs-right modifier distinction** — Carbon Events (which `HotKey` wraps) reports modifiers without sidedness. Right-Option-only registrations are not possible through this module; supporting them requires `NSEvent.addGlobalMonitorForEvents`, filed as a follow-up in `memory/domains/hotkey.md`.
- **App not launched in Accessibility-required state** — for some KeyCombo + app-target combinations macOS prompts for Accessibility permission. The hotkey module itself does not need it (Carbon Events bypasses Accessibility), but the `output` module will. If a user reports "hotkey doesn't fire," first check Accessibility settings, *then* check combo conflicts.
- **Repeated press without release** — if the OS swallows the keyUp event (e.g., focus changes during the press), `onRelease` won't fire. The app should treat hotkey state as advisory and have a hard timeout in the recorder module.
```

- [ ] **Step 2:** Commit

```bash
git add modules/hotkey/README.md
git commit -m "Document hotkey module: purpose, API, dependencies, failure modes"
```

### Task F2: Memory entry — domain note

**Files:**
- Create: `memory/domains/hotkey.md`
- Modify: `memory/memory.md` (move `domains/hotkey.md` from Planned to active)

- [ ] **Step 1:** Create `memory/domains/hotkey.md`

```markdown
---
type: memory-domain
domain: hotkey
created: 2026-04-26
updated: 2026-04-26
---

# Hotkey

## Configuration in v1

- Combo: `Option + F13` (placeholder; see Open questions)
- Behavior: hold-to-talk
- Registration: `HotkeyRegistry` in `modules/hotkey/`

## Open questions

- **Right-Option-only vs plain Option** — soffes/HotKey can't distinguish sided modifiers (Carbon Events limitation). The ADR proposed Right-Option as the default; achieving that requires `NSEvent.addGlobalMonitorForEvents` instead. Defer until the settings module exists and the user can pick.
- **F13 availability** — most laptops don't have F13. Settings module needs a UX for picking a non-conflicting combo. Until then, keyboards without F13 must edit `AppDelegate.registerPushToTalk()`.
- **Hotkey conflict detection** — soffes/HotKey silently fails on conflict. v2 should surface this; v1 relies on uncommon defaults.

## Configs

- AppDelegate hardcodes the v1 combo. The future `settings` module will read from `UserDefaults` and re-register on change.
```

- [ ] **Step 2:** Update `memory/memory.md` — move `domains/hotkey.md` from "Planned" to active and refresh the description

Edit the `## Domains` section of `memory/memory.md`:

```markdown
## Domains

- [domains/hotkey.md](domains/hotkey.md) — global shortcut registration via soffes/HotKey, conflicts, sided-modifier limits

Planned (created on demand):
- `domains/recorder.md` — AVAudioEngine capture, VAD, mic permissions
- `domains/transcriber.md` — WhisperKit + Groq dispatcher, model selection, latency
- `domains/output.md` — clipboard-paste + CGEvent fallback, Accessibility quirks
- `domains/settings.md` — UserDefaults + Keychain (Groq key) shape
- `domains/packaging.md` — Xcode bundling, code signing, notarization
```

(Remove the `domains/hotkey.md` line from "Planned" since it now exists.)

- [ ] **Step 3:** Commit

```bash
git add memory/
git commit -m "Add hotkey domain memory; note Right-Option/F13 open questions"
```

---

## Phase G — End-to-end verification (~4 min)

### Task G1: Computer-use verification of the hotkey-to-icon path

This phase **cannot be a unit test** — it requires a real running app, a real keypress, and a real menu bar.

- [ ] **Step 1:** Build a Release configuration `.app`

```bash
xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2:** Locate the built app

```bash
APP_PATH="$(xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release -showBuildSettings 2>/dev/null | awk '/CONFIGURATION_BUILD_DIR/ {print $3}' | head -1)/Diktador.app"
echo "$APP_PATH"
ls -la "$APP_PATH"
```

- [ ] **Step 3:** Launch and verify visually

```bash
open "$APP_PATH"
```

Verification checklist:
- [ ] Menu bar shows a microphone icon. **No Dock icon.**
- [ ] Click the menu bar icon → menu shows "Diktador (idle)" and "Quit". The first row title says **idle**.
- [ ] Hold the configured hotkey combo. **The menu bar icon switches to `mic.fill`** and the menu's first row says **"Diktador (listening…)"**.
- [ ] Release the hotkey. Icon and label revert to idle.
- [ ] Click Quit. The icon disappears.

If any check fails, debug per `modules/hotkey/README.md` "Known failure modes" before continuing.

- [ ] **Step 4:** Capture evidence

Take a screenshot showing the menu bar icon in both states (or one state if your screen tool doesn't support hotkey-held captures). Save as `.tmp/hotkey-verification.png` (gitignored). Reference its existence in the PR body — don't commit the screenshot.

```bash
mkdir -p .tmp
# Use Cmd+Shift+4 to capture the menu bar manually; save to .tmp/hotkey-verification.png
ls -la .tmp/hotkey-verification.png
```

---

## Phase H — Ship via /go (~3 min)

### Task H1: Run the workspace /go skill

- [ ] **Step 1:** Confirm clean test state and one-line summary

```bash
git status
git log --oneline main..HEAD
```
Expected: clean working tree; commit list shows the hotkey module commits since branching.

- [ ] **Step 2:** Invoke `/go`

The workspace `/go` skill will:
- Phase 0: skip (already on `feat/hotkey-module`, remote known)
- Phase 1: run `xcodebuild test -scheme Diktador -destination 'platform=macOS'` for the linked `Hotkey` package + the manual computer-use verification from Phase G
- Phase 2: invoke `/simplify` against the changed Swift files
- Phase 3: open PR `feat/hotkey-module → main` with a Test plan referencing the screenshot from G1
- Phase 4: append meta entry to `log.md` and update today's `memory/daily/<date>.md`

- [ ] **Step 3:** Verify the PR URL is returned and the test plan section reflects the actual computer-use verification, not a TODO list.

---

## Self-review — completed during plan-writing

- **Spec coverage** — All architectural elements from `wiki/decisions/framework-choice.md` relevant to the hotkey module are addressed: Swift Package, soffes/HotKey via SPM, `LSUIElement` menu bar app, macOS 14+ deployment, modular structure with one public surface, dual-state icon (foreshadows the listening UX). Items deliberately deferred and noted in memory: Right-Option-vs-plain-Option, sided modifiers, conflict detection, and persisted user preferences.
- **Placeholder scan** — No "TBD" / "TODO" / "implement later" found. Optional asset task (B3) is explicitly marked optional with a clear opt-out path to B4.
- **Type consistency** — `HotkeyRegistry`, `RegistrationToken`, `KeyCombo`, `Key`, `Modifier`, `register(combo:onPress:onRelease:)`, `unregister(_:)`, `activeRegistrationCount` are referenced consistently across Phase D tasks, the README in F1, and the AppDelegate wiring in E1.
- **Open architectural questions deliberately deferred** to follow-up plans, with each tracked in `memory/domains/hotkey.md`: Right-Option-only support, F13-less keyboards, conflict detection.

---

## Execution handoff

Plan complete. After PR #1 merges, two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for the TDD phases (D1–D4).
2. **Inline Execution** — Execute tasks in this session via `superpowers:executing-plans`, batch with checkpoints. Best for the Xcode UI tasks (B1, C2, G1) since those are interactive on your end.

Which approach?
