# Transcriber Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `diktador-transcriber` SwiftPM module that wraps WhisperKit (model `openai_whisper-base`), exposes a `Transcriber` protocol with a single `WhisperKitTranscriber` impl, and integrates with `AppDelegate` so each push-to-talk recording is auto-transcribed and copied to the system clipboard with a "Last transcript" menu surface.

**Architecture:** New SwiftPM module `modules/diktador-transcriber/` (package + library + target named `DiktadorTranscriber`, lowercase directory). Public `Transcriber` protocol (`loadModel`, `transcribe(audioFileURL:)`, `state`) + public `WhisperKitTranscriber` concrete impl. Internal `WhisperKitDriver` protocol (real impl `LiveWhisperKitDriver` wraps `WhisperKit` from `argmax-oss-swift`); tests inject a stub. State machine on `@MainActor`; happens-before with WhisperKit's own actor isolation via `await`. `AppDelegate` kicks off `transcriber.loadModel()` after `bootstrapPushToTalk`; on each `recorder.stop` success, awaits `transcriber.transcribe(...)`, copies the result to `NSPasteboard.general`, and surfaces it in two new menu items (status line + "Last transcript").

**Tech Stack:** Swift 5.10 / SwiftUI / AppKit / AVFoundation; WhisperKit via `https://github.com/argmaxinc/argmax-oss-swift` (from `0.9.0`, product `WhisperKit`); SwiftPM module `DiktadorTranscriber`; XCTest; xcodegen (`project.yml`); `xcodebuild` for the app target; `gh` for PR; macOS 14 deployment target.

**Spec:** [`docs/superpowers/specs/2026-04-27-transcriber-module-design.md`](../specs/2026-04-27-transcriber-module-design.md)

---

## File structure

**Created:**

- `modules/diktador-transcriber/Package.swift` — SwiftPM manifest. macOS 14+. Depends on `argmaxinc/argmax-oss-swift` from `0.9.0`. Library + target + test target all named `DiktadorTranscriber`.
- `modules/diktador-transcriber/Sources/DiktadorTranscriber/Transcriber.swift` — public protocol `Transcriber`, public `TranscriberState` enum, public `TranscriberError` enum.
- `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift` — public `@MainActor` final class implementing `Transcriber`. Holds the driver and the state machine.
- `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitDriver.swift` — internal `WhisperKitDriver` protocol + `LiveWhisperKitDriver` real impl (the only file that imports `WhisperKit`).
- `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift` — XCTest target. Stub driver covers state machine, error mapping, queue-while-loading.
- `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/StubWhisperKitDriver.swift` — test-only stub driver.
- `modules/diktador-transcriber/README.md` — module README (Purpose / Public API / Dependencies / Known failure modes).
- `wiki/decisions/transcriber-pipeline.md` — ADR (WhisperKit-only v1, base model, eager-load on launch, clipboard-copy debug surface, Groq + VAD deferral).
- `wiki/modules/transcriber.md` — module spec page.
- `memory/domains/transcriber.md` — operational memory note.

**Modified:**

- `Diktador/AppDelegate.swift` — owns a `WhisperKitTranscriber` alongside `Recorder` and `HotkeyRegistry`; spawns `loadModel()` task on launch; new `runTranscription(for:)` invoked from `handleRecordingResult`; new `transcriberStatusItem`, `lastTranscriptItem`, helper update methods; `NSPasteboard.general` write on success.
- `project.yml` — adds the `DiktadorTranscriber` package + product dep on the `Diktador` target. Also adds the `argmax-oss-swift` package at the project level so xcodegen materializes it for the app build. Re-run `xcodegen generate`.
- `wiki/index.md` — Decisions 3→4, Modules 1→2.
- `log.md` — `document` (ADR + module spec) and `meta` (PR ship) entries.
- `memory/resume.md` — rewritten for the post-ship state at the end of the session.

**No changes:**

- `modules/diktador-hotkey/` — untouched.
- `modules/diktador-recorder/` — untouched. The recorder produces the WAV; the transcriber consumes its filesystem output via `URL`. No source coupling.
- `Diktador/Diktador.entitlements` — `com.apple.security.network.client` is **not** added in this PR. WhisperKit's HuggingFace download uses URLSession; under Hardened Runtime the client entitlement is automatically allowed for outbound HTTPS. Only Groq's PR will revisit this.

---

## Phase A — Pre-flight

### Task A1: Verify branch + baseline green

**Files:** none touched.

- [ ] **Step 1: Confirm branch state**

Run: `cd "/Users/user/Desktop/Aintigravity Workflows/Diktador" && git status && git branch --show-current`
Expected: branch `feat/transcriber-module`, working tree clean (the spec commit `c2ab3c7` is already there).

- [ ] **Step 2: Baseline `swift test` for the existing modules**

Run: `(cd modules/diktador-hotkey && swift test 2>&1 | tail -3) && (cd modules/diktador-recorder && swift test 2>&1 | tail -3)`
Expected: both report `Test Suite 'All tests' passed`. Hotkey 8/8, recorder 9/9.

- [ ] **Step 3: Baseline `xcodebuild` Debug**

Run from repo root: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

(No commit — baseline only.)

---

## Phase B — Module skeleton

### Task B1: Create the SwiftPM package

**Files:**
- Create: `modules/diktador-transcriber/Package.swift`
- Create: `modules/diktador-transcriber/Sources/DiktadorTranscriber/.gitkeep`
- Create: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/.gitkeep`

- [ ] **Step 1: Create the directory structure**

Run: `mkdir -p modules/diktador-transcriber/Sources/DiktadorTranscriber modules/diktador-transcriber/Tests/DiktadorTranscriberTests && touch modules/diktador-transcriber/Sources/DiktadorTranscriber/.gitkeep modules/diktador-transcriber/Tests/DiktadorTranscriberTests/.gitkeep`
Expected: directories created.

- [ ] **Step 2: Write `modules/diktador-transcriber/Package.swift`**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiktadorTranscriber",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiktadorTranscriber", targets: ["DiktadorTranscriber"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "DiktadorTranscriber",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .testTarget(
            name: "DiktadorTranscriberTests",
            dependencies: ["DiktadorTranscriber"]
        ),
    ]
)
```

- [ ] **Step 3: Verify the manifest parses**

Run: `cd modules/diktador-transcriber && swift package resolve 2>&1 | tail -10`
Expected: dependencies resolve. WhisperKit (and its transitive deps) get fetched into `.build/`. No build attempted yet — only resolution.

- [ ] **Step 4: Commit**

```bash
cd "/Users/user/Desktop/Aintigravity Workflows/Diktador"
git add modules/diktador-transcriber/Package.swift \
        modules/diktador-transcriber/Sources/DiktadorTranscriber/.gitkeep \
        modules/diktador-transcriber/Tests/DiktadorTranscriberTests/.gitkeep
git commit -m "$(cat <<'EOF'
transcriber: scaffold SwiftPM package + WhisperKit dependency

Empty package manifest pulling argmax-oss-swift (WhisperKit) from 0.9.0.
Module sources arrive in subsequent commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C — Public types (no behaviour, no driver yet)

### Task C1: Public `TranscriberState` + `TranscriberError`

**Files:**
- Create: `modules/diktador-transcriber/Sources/DiktadorTranscriber/Transcriber.swift`
- Test: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Write the failing test (existence + Equatable on the enums)**

Replace the .gitkeep in `Tests/DiktadorTranscriberTests/` with `TranscriberTests.swift`:

```swift
import XCTest
@testable import DiktadorTranscriber

final class TranscriberTests: XCTestCase {
    func test_transcriberState_isEquatable() {
        XCTAssertEqual(TranscriberState.uninitialized, .uninitialized)
        XCTAssertEqual(TranscriberState.loading, .loading)
        XCTAssertEqual(TranscriberState.ready, .ready)
        XCTAssertEqual(TranscriberState.transcribing, .transcribing)
        XCTAssertEqual(
            TranscriberState.failed(.modelLoadFailed(message: "x")),
            TranscriberState.failed(.modelLoadFailed(message: "x"))
        )
        XCTAssertNotEqual(TranscriberState.ready, .loading)
    }

    func test_transcriberError_isEquatable() {
        XCTAssertEqual(
            TranscriberError.modelLoadFailed(message: "boom"),
            TranscriberError.modelLoadFailed(message: "boom")
        )
        XCTAssertEqual(
            TranscriberError.transcriptionFailed(message: "x"),
            TranscriberError.transcriptionFailed(message: "x")
        )
        XCTAssertEqual(
            TranscriberError.audioFileUnreadable(URL(fileURLWithPath: "/a")),
            TranscriberError.audioFileUnreadable(URL(fileURLWithPath: "/a"))
        )
        XCTAssertEqual(TranscriberError.emptyTranscript, .emptyTranscript)
    }
}
```

Also delete the `.gitkeep` files: `rm modules/diktador-transcriber/Sources/DiktadorTranscriber/.gitkeep modules/diktador-transcriber/Tests/DiktadorTranscriberTests/.gitkeep`

- [ ] **Step 2: Run test to confirm it fails (no source yet)**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: compile error — `cannot find type 'TranscriberState' in scope` (or similar).

- [ ] **Step 3: Create `Transcriber.swift` with state, error, and protocol**

```swift
import Foundation

/// State of a transcriber's lifecycle.
public enum TranscriberState: Sendable, Equatable {
    case uninitialized
    case loading
    case ready
    case transcribing
    case failed(TranscriberError)
}

/// Errors a transcriber can throw.
public enum TranscriberError: Error, Sendable, Equatable {
    case modelLoadFailed(message: String)
    case transcriptionFailed(message: String)
    case audioFileUnreadable(URL)
    case emptyTranscript
}

/// Public surface a Diktador transcription backend exposes.
public protocol Transcriber: Sendable {
    @MainActor var state: TranscriberState { get }
    func loadModel() async throws
    func transcribe(audioFileURL: URL) async throws -> String
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 2/2 tests pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/user/Desktop/Aintigravity Workflows/Diktador"
git add modules/diktador-transcriber/Sources/DiktadorTranscriber/Transcriber.swift \
        modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git rm modules/diktador-transcriber/Sources/DiktadorTranscriber/.gitkeep \
       modules/diktador-transcriber/Tests/DiktadorTranscriberTests/.gitkeep 2>/dev/null || true
git commit -m "$(cat <<'EOF'
transcriber: public Transcriber protocol + State/Error enums

Sendable, Equatable value types ready to back the WhisperKit impl.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D — Driver protocol + state machine (TDD against a stub driver)

The state machine is the load-bearing logic. We test it with a stub driver before LiveWhisperKitDriver lands. Each task adds one behaviour + one test pair. Commit after each green test (no batching — TDD discipline matches the recorder's PR pattern).

### Task D1: `WhisperKitDriver` protocol + `StubWhisperKitDriver`

**Files:**
- Create: `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitDriver.swift`
- Create: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/StubWhisperKitDriver.swift`

- [ ] **Step 1: Write the protocol + stub** (this is plumbing; the test arrives in D2 once the transcriber needs it)

`Sources/DiktadorTranscriber/WhisperKitDriver.swift`:
```swift
import Foundation

/// Internal seam that hides the WhisperKit dependency from the
/// transcriber's state machine. Real impl: `LiveWhisperKitDriver`.
internal protocol WhisperKitDriver: Sendable {
    func loadModel(name: String, modelStorage: URL) async throws
    func transcribe(audioFileURL: URL) async throws -> String
}
```

`Tests/DiktadorTranscriberTests/StubWhisperKitDriver.swift`:
```swift
import Foundation
@testable import DiktadorTranscriber

/// Test stub — records calls and returns canned results / errors.
final class StubWhisperKitDriver: WhisperKitDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var _loadModelCalls: [(name: String, modelStorage: URL)] = []
    private var _transcribeCalls: [URL] = []

    var loadModelCalls: [(name: String, modelStorage: URL)] {
        lock.lock(); defer { lock.unlock() }
        return _loadModelCalls
    }
    var transcribeCalls: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _transcribeCalls
    }

    /// Optional delay (in nanoseconds) before loadModel resumes.
    var loadModelDelay: UInt64 = 0
    /// Error to throw from loadModel; nil = succeed.
    var loadModelError: Error?
    /// String to return from transcribe; ignored if transcribeError is set.
    var transcribeResult: String = "stub transcript"
    /// Error to throw from transcribe; nil = return transcribeResult.
    var transcribeError: Error?

    func loadModel(name: String, modelStorage: URL) async throws {
        lock.lock(); _loadModelCalls.append((name: name, modelStorage: modelStorage)); lock.unlock()
        if loadModelDelay > 0 {
            try await Task.sleep(nanoseconds: loadModelDelay)
        }
        if let error = loadModelError { throw error }
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        lock.lock(); _transcribeCalls.append(audioFileURL); lock.unlock()
        if let error = transcribeError { throw error }
        return transcribeResult
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 2/2 existing tests still pass; the new files compile but do not yet add a test case.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitDriver.swift \
        modules/diktador-transcriber/Tests/DiktadorTranscriberTests/StubWhisperKitDriver.swift
git commit -m "$(cat <<'EOF'
transcriber: WhisperKitDriver protocol + test stub

Internal seam isolating WhisperKit from the state machine. Stub records
calls and lets tests drive deterministic load + transcribe outcomes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D2: `WhisperKitTranscriber` — `loadModel` happy path

**Files:**
- Create: `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift`
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `TranscriberTests.swift` inside `final class TranscriberTests`:

```swift
@MainActor
func test_loadModel_happyPath_transitionsToReady() async throws {
    let driver = StubWhisperKitDriver()
    let modelStorage = Self.tempModelStorage()
    let transcriber = WhisperKitTranscriber(
        driver: driver,
        modelName: "openai_whisper-base",
        modelStorage: modelStorage
    )
    XCTAssertEqual(transcriber.state, .uninitialized)

    try await transcriber.loadModel()

    XCTAssertEqual(transcriber.state, .ready)
    XCTAssertEqual(driver.loadModelCalls.count, 1)
    XCTAssertEqual(driver.loadModelCalls.first?.name, "openai_whisper-base")
    XCTAssertEqual(driver.loadModelCalls.first?.modelStorage, modelStorage)
}
```

Append a static helper at the bottom of `TranscriberTests`:

```swift
static func tempModelStorage() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "diktador-test-models-\(UUID().uuidString)"
    )
    return url
}
```

- [ ] **Step 2: Run the test — it must fail because `WhisperKitTranscriber` doesn't exist**

Run: `cd modules/diktador-transcriber && swift test --filter test_loadModel_happyPath_transitionsToReady 2>&1 | tail -10`
Expected: compile error — `cannot find 'WhisperKitTranscriber' in scope`.

- [ ] **Step 3: Implement `WhisperKitTranscriber`**

`Sources/DiktadorTranscriber/WhisperKitTranscriber.swift`:
```swift
import Foundation

/// Transcribes audio files via WhisperKit. Holds the loaded model in
/// memory across calls; main-actor-isolated state.
@MainActor
public final class WhisperKitTranscriber: Transcriber {
    public static let defaultModelName = "openai_whisper-base"

    public static func defaultModelStorage() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Diktador", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    private let driver: WhisperKitDriver
    private let modelName: String
    private let modelStorage: URL

    public private(set) var state: TranscriberState = .uninitialized

    /// Production initializer.
    public convenience init(modelName: String = defaultModelName) {
        self.init(
            driver: LiveWhisperKitDriver(),
            modelName: modelName,
            modelStorage: Self.defaultModelStorage()
        )
    }

    /// Test seam.
    internal init(
        driver: WhisperKitDriver,
        modelName: String = defaultModelName,
        modelStorage: URL = WhisperKitTranscriber.defaultModelStorage()
    ) {
        self.driver = driver
        self.modelName = modelName
        self.modelStorage = modelStorage
    }

    public func loadModel() async throws {
        state = .loading
        do {
            try await driver.loadModel(name: modelName, modelStorage: modelStorage)
            state = .ready
        } catch {
            let mapped = TranscriberError.modelLoadFailed(message: String(describing: error))
            state = .failed(mapped)
            throw mapped
        }
    }

    public func transcribe(audioFileURL: URL) async throws -> String {
        // Stub for D3+. Initial body just to make the type compile.
        throw TranscriberError.transcriptionFailed(message: "not yet implemented")
    }
}
```

`LiveWhisperKitDriver` doesn't exist yet, so add a temporary stub at the bottom of `WhisperKitDriver.swift`:

```swift
/// Temporary placeholder so the production initializer compiles.
/// Replaced with the real WhisperKit-backed implementation in Phase E.
internal final class LiveWhisperKitDriver: WhisperKitDriver, @unchecked Sendable {
    func loadModel(name: String, modelStorage: URL) async throws {
        throw TranscriberError.modelLoadFailed(message: "LiveWhisperKitDriver not yet implemented")
    }
    func transcribe(audioFileURL: URL) async throws -> String {
        throw TranscriberError.transcriptionFailed(message: "LiveWhisperKitDriver not yet implemented")
    }
}
```

- [ ] **Step 4: Run the test — must pass**

Run: `cd modules/diktador-transcriber && swift test --filter test_loadModel_happyPath_transitionsToReady 2>&1 | tail -10`
Expected: 1/1 pass. Run the full suite: `swift test 2>&1 | tail -10` — 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift \
        modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitDriver.swift \
        modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: WhisperKitTranscriber.loadModel happy path

@MainActor class with state machine. State transitions
.uninitialized -> .loading -> .ready on successful load via the driver.
LiveWhisperKitDriver is a temporary throwing stub until Phase E.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D3: `loadModel` failure path → `.failed(.modelLoadFailed)`

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

Append:

```swift
@MainActor
func test_loadModel_failure_transitionsToFailed_andRethrows() async throws {
    struct DriverFailure: Error { let detail: String }
    let driver = StubWhisperKitDriver()
    driver.loadModelError = DriverFailure(detail: "no network")
    let transcriber = WhisperKitTranscriber(driver: driver)

    do {
        try await transcriber.loadModel()
        XCTFail("expected loadModel to throw")
    } catch let error as TranscriberError {
        if case .modelLoadFailed(let message) = error {
            XCTAssertTrue(message.contains("no network"), "got: \(message)")
        } else {
            XCTFail("unexpected error: \(error)")
        }
    }

    if case .failed(let inner) = transcriber.state {
        if case .modelLoadFailed = inner { /* ok */ } else { XCTFail() }
    } else {
        XCTFail("expected .failed state, got \(transcriber.state)")
    }
}
```

- [ ] **Step 2: Run — must pass already** (the impl from D2 already handles the failure branch)

Run: `cd modules/diktador-transcriber && swift test --filter test_loadModel_failure_transitionsToFailed_andRethrows 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: test loadModel failure transitions to .failed

Codifies the existing failure-branch behaviour from D2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D4: `loadModel` is idempotent

**Files:**
- Modify: `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift`
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_loadModel_idempotent_secondCallIsNoOp() async throws {
    let driver = StubWhisperKitDriver()
    let transcriber = WhisperKitTranscriber(driver: driver)
    try await transcriber.loadModel()
    try await transcriber.loadModel()
    XCTAssertEqual(driver.loadModelCalls.count, 1, "loadModel must not re-invoke driver once .ready")
    XCTAssertEqual(transcriber.state, .ready)
}
```

- [ ] **Step 2: Run — must fail** (D2's impl unconditionally calls the driver)

Run: `cd modules/diktador-transcriber && swift test --filter test_loadModel_idempotent_secondCallIsNoOp 2>&1 | tail -10`
Expected: fail with `loadModelCalls.count == 2`, expected 1.

- [ ] **Step 3: Update `loadModel` to short-circuit when already `.ready`**

Replace the body of `loadModel` in `WhisperKitTranscriber.swift`:

```swift
public func loadModel() async throws {
    if case .ready = state { return }
    if let task = inFlightLoad {
        try await task.value
        return
    }
    state = .loading
    let task = Task<Void, Error> { [self, modelName, modelStorage] in
        try await driver.loadModel(name: modelName, modelStorage: modelStorage)
    }
    inFlightLoad = task
    defer { inFlightLoad = nil }
    do {
        try await task.value
        state = .ready
    } catch {
        let mapped = TranscriberError.modelLoadFailed(message: String(describing: error))
        state = .failed(mapped)
        throw mapped
    }
}
```

Add the property near the top of the class:

```swift
private var inFlightLoad: Task<Void, Error>?
```

- [ ] **Step 4: Run — must pass; full suite still green**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 5/5 pass (the existing happy-path + failure tests still hold).

- [ ] **Step 5: Commit**

```bash
git add modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift \
        modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: loadModel idempotent + concurrent-call coalesce seam

Once .ready, second loadModel returns immediately. While .loading,
concurrent callers await the same Task. Sets up D5's concurrency test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D5: Concurrent `loadModel` calls coalesce

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_loadModel_concurrent_callsCoalesceToSingleDriverCall() async throws {
    let driver = StubWhisperKitDriver()
    driver.loadModelDelay = 50_000_000  // 50 ms — long enough that both Tasks join the in-flight one
    let transcriber = WhisperKitTranscriber(driver: driver)

    async let a: Void = transcriber.loadModel()
    async let b: Void = transcriber.loadModel()
    _ = try await (a, b)

    XCTAssertEqual(driver.loadModelCalls.count, 1)
    XCTAssertEqual(transcriber.state, .ready)
}
```

- [ ] **Step 2: Run — must pass given D4's `inFlightLoad` machinery**

Run: `cd modules/diktador-transcriber && swift test --filter test_loadModel_concurrent_callsCoalesceToSingleDriverCall 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: test concurrent loadModel coalesces to one driver call

Two simultaneous loadModel() awaits resolve from a single in-flight Task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D6: `transcribe` happy path

**Files:**
- Modify: `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift`
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_transcribe_happyPath_returnsDriverResult_andStateReturnsToReady() async throws {
    let driver = StubWhisperKitDriver()
    driver.transcribeResult = "hello world"
    let transcriber = WhisperKitTranscriber(driver: driver)
    try await transcriber.loadModel()

    let url = Self.tempAudioFile()
    let text = try await transcriber.transcribe(audioFileURL: url)

    XCTAssertEqual(text, "hello world")
    XCTAssertEqual(driver.transcribeCalls, [url])
    XCTAssertEqual(transcriber.state, .ready)
}
```

Add a static helper to `TranscriberTests`:

```swift
static func tempAudioFile() -> URL {
    // Real bytes aren't required — the stub driver doesn't read the file.
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "diktador-test-\(UUID().uuidString).wav"
    )
    let header = Data(repeating: 0, count: 44)  // minimal nonzero file
    try? header.write(to: url)
    return url
}
```

- [ ] **Step 2: Run — must fail** (current `transcribe` always throws `.transcriptionFailed("not yet implemented")`)

Run: `cd modules/diktador-transcriber && swift test --filter test_transcribe_happyPath_returnsDriverResult_andStateReturnsToReady 2>&1 | tail -10`
Expected: fail.

- [ ] **Step 3: Replace `transcribe` body in `WhisperKitTranscriber.swift`**

```swift
public func transcribe(audioFileURL: URL) async throws -> String {
    // Validate file exists before paying for state transitions.
    guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
        throw TranscriberError.audioFileUnreadable(audioFileURL)
    }

    // Drive load if needed; surface the same .modelLoadFailed error.
    try await loadModel()

    // Sticky-failure check after loadModel returns.
    if case .failed(let error) = state { throw error }

    state = .transcribing
    do {
        let raw = try await driver.transcribe(audioFileURL: audioFileURL)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .ready
        if trimmed.isEmpty { throw TranscriberError.emptyTranscript }
        return trimmed
    } catch let error as TranscriberError {
        if case .emptyTranscript = error {
            // .ready state was already restored before throwing emptyTranscript.
            throw error
        }
        state = .ready
        throw error
    } catch {
        state = .ready
        throw TranscriberError.transcriptionFailed(message: String(describing: error))
    }
}
```

- [ ] **Step 4: Run — happy-path test must pass; full suite still green**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
git add modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift \
        modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: transcribe happy path returns driver result

Trims whitespace, drives loadModel if needed, sets .transcribing during
the call and returns to .ready. Empty results handled in D7.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D7: Empty / whitespace-only transcripts surface `.emptyTranscript`

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing tests**

```swift
@MainActor
func test_transcribe_emptyResult_throwsEmptyTranscript_andStaysReady() async throws {
    let driver = StubWhisperKitDriver()
    driver.transcribeResult = ""
    let transcriber = WhisperKitTranscriber(driver: driver)
    try await transcriber.loadModel()

    do {
        _ = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
        XCTFail("expected emptyTranscript")
    } catch TranscriberError.emptyTranscript {
        // expected
    }
    XCTAssertEqual(transcriber.state, .ready)
}

@MainActor
func test_transcribe_whitespaceOnlyResult_throwsEmptyTranscript() async throws {
    let driver = StubWhisperKitDriver()
    driver.transcribeResult = "   \n\t  "
    let transcriber = WhisperKitTranscriber(driver: driver)
    try await transcriber.loadModel()

    do {
        _ = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
        XCTFail("expected emptyTranscript")
    } catch TranscriberError.emptyTranscript { /* expected */ }
    XCTAssertEqual(transcriber.state, .ready)
}
```

- [ ] **Step 2: Run — both pass given D6's logic**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 8/8 pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: empty/whitespace transcripts surface emptyTranscript

State stays .ready; AppDelegate will treat this as 'no speech detected'
without poisoning the clipboard.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D8: Driver throw → `.transcriptionFailed`, state recovers to `.ready`

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_transcribe_driverFailure_throwsTranscriptionFailed_andRecovers() async throws {
    struct InferenceFailure: Error {}
    let driver = StubWhisperKitDriver()
    driver.transcribeError = InferenceFailure()
    let transcriber = WhisperKitTranscriber(driver: driver)
    try await transcriber.loadModel()

    do {
        _ = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
        XCTFail("expected transcriptionFailed")
    } catch TranscriberError.transcriptionFailed { /* expected */ }

    XCTAssertEqual(transcriber.state, .ready, "transient transcription failure must not poison state")

    // Subsequent transcribe still works (driver unset on next call):
    driver.transcribeError = nil
    driver.transcribeResult = "second try"
    let text = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
    XCTAssertEqual(text, "second try")
}
```

- [ ] **Step 2: Run — must pass given D6's catch-all branch**

Run: `cd modules/diktador-transcriber && swift test --filter test_transcribe_driverFailure_throwsTranscriptionFailed_andRecovers 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: driver failure surfaces transcriptionFailed; state recovers

Transient inference errors don't poison the model — next transcribe works.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D9: `transcribe` from `.uninitialized` triggers an implicit `loadModel`

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_transcribe_fromUninitialized_triggersImplicitLoadModel() async throws {
    let driver = StubWhisperKitDriver()
    let transcriber = WhisperKitTranscriber(driver: driver)
    XCTAssertEqual(transcriber.state, .uninitialized)

    let text = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())

    XCTAssertEqual(text, "stub transcript")
    XCTAssertEqual(driver.loadModelCalls.count, 1, "transcribe must drive loadModel implicitly")
    XCTAssertEqual(driver.transcribeCalls.count, 1)
    XCTAssertEqual(transcriber.state, .ready)
}
```

- [ ] **Step 2: Run — must pass given D6's `try await loadModel()` line**

Run: `cd modules/diktador-transcriber && swift test --filter test_transcribe_fromUninitialized_triggersImplicitLoadModel 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: transcribe from .uninitialized drives loadModel implicitly

The 'recording before model is ready' lifecycle resolves through Swift
structured concurrency — no explicit queue needed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D10: `transcribe` while `loadModel` is in flight awaits it

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_transcribe_whileLoading_awaitsTheInFlightLoad() async throws {
    let driver = StubWhisperKitDriver()
    driver.loadModelDelay = 50_000_000
    let transcriber = WhisperKitTranscriber(driver: driver)

    // Kick off loadModel without awaiting; transcribe right away should
    // join the in-flight task rather than starting a second load.
    async let load: Void = transcriber.loadModel()
    let text = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
    try await load

    XCTAssertEqual(text, "stub transcript")
    XCTAssertEqual(driver.loadModelCalls.count, 1)
    XCTAssertEqual(transcriber.state, .ready)
}
```

- [ ] **Step 2: Run — must pass given D4's `inFlightLoad` coalescing**

Run: `cd modules/diktador-transcriber && swift test --filter test_transcribe_whileLoading_awaitsTheInFlightLoad 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: transcribe joins in-flight loadModel via Task coalescing

Confirms the 'press Fn before model loaded' lifecycle works end-to-end.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D11: `transcribe` after a `.failed` model state throws immediately

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_transcribe_afterFailedModelLoad_throwsModelLoadFailed_withoutCallingDriver() async throws {
    struct LoadFailure: Error {}
    let driver = StubWhisperKitDriver()
    driver.loadModelError = LoadFailure()
    let transcriber = WhisperKitTranscriber(driver: driver)
    do {
        try await transcriber.loadModel()
        XCTFail("expected loadModel to throw")
    } catch { /* expected */ }
    XCTAssertEqual(driver.transcribeCalls.count, 0)

    do {
        _ = try await transcriber.transcribe(audioFileURL: Self.tempAudioFile())
        XCTFail("expected transcribe to throw")
    } catch TranscriberError.modelLoadFailed { /* expected */ }
    XCTAssertEqual(driver.transcribeCalls.count, 0, "driver.transcribe must not be called while .failed")
}
```

- [ ] **Step 2: Run — currently the impl re-enters `loadModel()` from `transcribe`. Need to short-circuit when `.failed`.**

Run: `cd modules/diktador-transcriber && swift test --filter test_transcribe_afterFailedModelLoad_throwsModelLoadFailed_withoutCallingDriver 2>&1 | tail -10`
Expected: fail. The second call to `loadModel()` re-runs the driver because the current impl only short-circuits on `.ready`, not `.failed`. Either:
- driver.loadModelCalls.count rises to 2 (driver re-invoked), OR
- transcribeCalls > 0 (if the second load happened to succeed in some configurations)

Either way, the test catches the wrong shape.

- [ ] **Step 3: Update `loadModel` to also short-circuit on `.failed`**

In `WhisperKitTranscriber.swift`, replace the first guard line of `loadModel`:

```swift
public func loadModel() async throws {
    if case .ready = state { return }
    if case .failed(let error) = state { throw error }
    if let task = inFlightLoad {
        try await task.value
        return
    }
    state = .loading
    // ...rest unchanged
```

- [ ] **Step 4: Run — must pass; full suite still green**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 12/12 pass.

- [ ] **Step 5: Commit**

```bash
git add modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift \
        modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: failed model state is sticky; transcribe rejects without driver hit

Once loadModel fails, the only path forward is restarting Diktador. v1
has no in-app retry button — the .failed state must surface, not
silently re-attempt.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D12: `transcribe` with a missing audio file throws `.audioFileUnreadable`

**Files:**
- Modify: `modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift`

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_transcribe_missingFile_throwsAudioFileUnreadable_withoutCallingDriver() async throws {
    let driver = StubWhisperKitDriver()
    let transcriber = WhisperKitTranscriber(driver: driver)
    try await transcriber.loadModel()

    let bogus = URL(fileURLWithPath: "/tmp/diktador-does-not-exist-\(UUID().uuidString).wav")
    do {
        _ = try await transcriber.transcribe(audioFileURL: bogus)
        XCTFail("expected audioFileUnreadable")
    } catch TranscriberError.audioFileUnreadable(let url) {
        XCTAssertEqual(url, bogus)
    }
    XCTAssertEqual(driver.transcribeCalls.count, 0, "driver must not be invoked for a missing file")
    XCTAssertEqual(transcriber.state, .ready)
}
```

- [ ] **Step 2: Run — must pass given D6's existence check**

Run: `cd modules/diktador-transcriber && swift test --filter test_transcribe_missingFile_throwsAudioFileUnreadable_withoutCallingDriver 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 3: Run the full suite once for the record**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -15`
Expected: 13/13 pass.

- [ ] **Step 4: Commit**

```bash
git add modules/diktador-transcriber/Tests/DiktadorTranscriberTests/TranscriberTests.swift
git commit -m "$(cat <<'EOF'
transcriber: missing audio file rejected before driver call

Cheap precondition check ahead of the (potentially expensive) load.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E — Live WhisperKit driver

Now that the state machine is fully tested behind the stub, we replace the placeholder `LiveWhisperKitDriver` with a real one and wire WhisperKit into the app target.

### Task E1: Implement `LiveWhisperKitDriver` against WhisperKit

**Files:**
- Modify: `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitDriver.swift`

- [ ] **Step 1: Replace the placeholder `LiveWhisperKitDriver`**

Replace the temporary placeholder at the bottom of `WhisperKitDriver.swift`:

```swift
import WhisperKit

/// Real WhisperKit-backed driver. Loads `openai_whisper-base` (or whatever
/// `WhisperKitTranscriber` was configured with) into a held `WhisperKit`
/// pipeline and routes `transcribe(audioFileURL:)` to it.
internal final class LiveWhisperKitDriver: WhisperKitDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var pipeline: WhisperKit?

    func loadModel(name: String, modelStorage: URL) async throws {
        try FileManager.default.createDirectory(
            at: modelStorage,
            withIntermediateDirectories: true
        )
        let config = WhisperKitConfig(
            model: name,
            modelRepo: "argmaxinc/whisperkit-coreml",
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        )
        let pipeline = try await WhisperKit(config)
        lock.lock(); self.pipeline = pipeline; lock.unlock()
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        lock.lock()
        let pipeline = self.pipeline
        lock.unlock()
        guard let pipeline else {
            throw TranscriberError.transcriptionFailed(message: "pipeline not loaded")
        }
        let results = try await pipeline.transcribe(audioPath: audioFileURL.path)
        // WhisperKit returns [TranscriptionResult]; concatenate text across results.
        let combined = results
            .map { $0.text }
            .joined(separator: " ")
        return combined
    }
}
```

(Drop the temporary placeholder body — replace the whole `LiveWhisperKitDriver` class with the version above.)

- [ ] **Step 2: Build the module to ensure WhisperKit links**

Run: `cd modules/diktador-transcriber && swift build 2>&1 | tail -15`
Expected: `Build complete!`. WhisperKit's transitive deps fetch on first build (~couple of minutes the first time).

- [ ] **Step 3: Tests still pass (WhisperKit isn't exercised by tests; stub driver covers state machine)**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 13/13 pass.

- [ ] **Step 4: Commit**

```bash
git add modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitDriver.swift
git commit -m "$(cat <<'EOF'
transcriber: LiveWhisperKitDriver wires the real WhisperKit pipeline

WhisperKitConfig with prewarm + load + download; held pipeline is shared
across transcribe calls. Stub driver still covers all state-machine
tests; this driver is exercised end-to-end during /go computer-use.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task E2: Add the transcriber package to `project.yml` + regenerate

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Read current `project.yml`**

Run: `cat project.yml`

- [ ] **Step 2: Add `DiktadorTranscriber` package + dependency**

Edit `project.yml`. Under `packages:` add the entry; under the `Diktador` target's `dependencies:` add the product. The result should look like:

```yaml
packages:
  DiktadorHotkey:
    path: modules/diktador-hotkey
  DiktadorRecorder:
    path: modules/diktador-recorder
  DiktadorTranscriber:
    path: modules/diktador-transcriber
targets:
  Diktador:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: Diktador
    dependencies:
      - package: DiktadorHotkey
        product: DiktadorHotkey
      - package: DiktadorRecorder
        product: DiktadorRecorder
      - package: DiktadorTranscriber
        product: DiktadorTranscriber
    settings:
      # ...unchanged...
```

(Keep the rest of the file exactly as-is. Only the two additions above.)

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate 2>&1 | tail -5`
Expected: `Generated project successfully`.

- [ ] **Step 4: Build the app target**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`. WhisperKit's transitive deps may fetch the first time.

If WhisperKit's Core ML models or supporting binaries aren't found at link time, check that `argmax-oss-swift` resolved fully via `cat Diktador.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and rerun `swift package resolve` in `modules/diktador-transcriber/`.

- [ ] **Step 5: Commit**

```bash
git add project.yml Diktador.xcodeproj
git commit -m "$(cat <<'EOF'
project: wire DiktadorTranscriber package into Diktador app target

xcodegen pulls the new module + WhisperKit transitively. Debug build
green; transcriber is now reachable from AppDelegate.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F — AppDelegate integration

### Task F1: Wire the transcriber + load on launch

**Files:**
- Modify: `Diktador/AppDelegate.swift`

- [ ] **Step 1: Add the import + property**

Near the existing imports, add:

```swift
import DiktadorTranscriber
```

In the `AppDelegate` body, alongside `private let recorder = Recorder()`, add:

```swift
private let transcriber = WhisperKitTranscriber()
```

And alongside the existing menu-item fields, add three new properties:

```swift
private var transcriberStatusItem: NSMenuItem?
private var lastTranscriptItem: NSMenuItem?
private var lastTranscript: String?
```

Plus three new title constants alongside `idleTitle` etc.:

```swift
private static let transcriberLoadingTitle = "Transcription: loading model…"
private static let transcriberReadyTitle = "Transcription: ready"
private static let transcriberTranscribingTitle = "Transcription: transcribing…"
private static let transcriberFailedTitle = "Transcription: model unavailable — see Console"
private static let transcriberInferenceFailedTitle = "Transcription failed — see Console"
private static let transcriberNoSpeechTitle = "Transcription: no speech detected"
```

- [ ] **Step 2: Insert the status-line menu item during `configureStatusItem`**

In `configureStatusItem` (current body lines 38–55 inclusive of the `statusRow` insertion), after `menu.addItem(statusRow)` and before the separator, insert:

```swift
menu.addItem(.separator())
let transcriberStatus = NSMenuItem(title: Self.transcriberLoadingTitle, action: nil, keyEquivalent: "")
menu.addItem(transcriberStatus)
self.transcriberStatusItem = transcriberStatus
```

(So the menu order becomes: status row, separator, transcriber status, separator (existing), Quit.)

- [ ] **Step 3: Kick off `loadModel()` from `applicationDidFinishLaunching`**

Replace the body of `applicationDidFinishLaunching` to:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    configureStatusItem()
    bootstrapPushToTalk()
    Task { @MainActor [weak self] in
        await self?.loadTranscriptionModel()
    }
}
```

Add a new private method to `AppDelegate`:

```swift
@MainActor
private func loadTranscriptionModel() async {
    transcriberStatusItem?.title = Self.transcriberLoadingTitle
    do {
        try await transcriber.loadModel()
        transcriberStatusItem?.title = Self.transcriberReadyTitle
    } catch {
        transcriberStatusItem?.title = Self.transcriberFailedTitle
        NSLog("[app] transcriber.loadModel failed: \(error)")
    }
}
```

- [ ] **Step 4: Build and confirm the app still launches**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

(Computer-use is in Phase H — at this checkpoint the WhisperKit init runs but no transcription happens yet on Fn release.)

- [ ] **Step 5: Commit**

```bash
git add Diktador/AppDelegate.swift
git commit -m "$(cat <<'EOF'
app: own a WhisperKitTranscriber and load model on launch

Background Task drives loadModel after bootstrap; menu status item
reflects loading/ready/failed. Recorder still operates independently.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task F2: Run transcription on each successful recording

**Files:**
- Modify: `Diktador/AppDelegate.swift`

- [ ] **Step 1: Branch transcription off `handleRecordingResult`**

In `handleRecordingResult`, modify the `.success(let recording)` branch. The existing body builds and inserts the "Last recording: …" menu item; after that block (still within `case .success`), append:

```swift
let url = recording.fileURL
Task { @MainActor [weak self] in
    await self?.runTranscription(for: url)
}
```

- [ ] **Step 2: Add `runTranscription`**

Add as a new private method:

```swift
@MainActor
private func runTranscription(for audioFileURL: URL) async {
    transcriberStatusItem?.title = Self.transcriberTranscribingTitle
    do {
        let transcript = try await transcriber.transcribe(audioFileURL: audioFileURL)
        copyTranscriptToPasteboard(transcript)
        updateLastTranscriptItem(transcript)
        lastTranscript = transcript
        transcriberStatusItem?.title = Self.transcriberReadyTitle
    } catch TranscriberError.emptyTranscript {
        transcriberStatusItem?.title = Self.transcriberNoSpeechTitle
        NSLog("[app] transcription returned no speech for \(audioFileURL.lastPathComponent)")
    } catch TranscriberError.modelLoadFailed(let message) {
        transcriberStatusItem?.title = Self.transcriberFailedTitle
        NSLog("[app] transcription unavailable: \(message)")
    } catch {
        transcriberStatusItem?.title = Self.transcriberInferenceFailedTitle
        NSLog("[app] transcription failed: \(error)")
    }
}

@MainActor
private func copyTranscriptToPasteboard(_ transcript: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(transcript, forType: .string)
}

@MainActor
private func updateLastTranscriptItem(_ transcript: String) {
    let title = Self.lastTranscriptMenuTitle(for: transcript)
    if let item = lastTranscriptItem {
        item.title = title
        item.representedObject = transcript
        return
    }
    let item = NSMenuItem(
        title: title,
        action: #selector(copyLastTranscript(_:)),
        keyEquivalent: ""
    )
    item.target = self
    item.representedObject = transcript
    // Insert above "Last recording" if present, else above the Quit-area separator.
    let menu = statusItem?.menu
    if let recordingItem = lastRecordingItem,
       let menu, let idx = menu.items.firstIndex(of: recordingItem) {
        menu.insertItem(item, at: idx)
    } else if let menu {
        // Insert just before the final separator+Quit pair.
        let insertAt = max(menu.items.count - 2, 0)
        menu.insertItem(item, at: insertAt)
    }
    lastTranscriptItem = item
}

@objc private func copyLastTranscript(_ sender: NSMenuItem) {
    guard let transcript = sender.representedObject as? String else { return }
    copyTranscriptToPasteboard(transcript)
}

private static func lastTranscriptMenuTitle(for transcript: String) -> String {
    let single = transcript.replacingOccurrences(of: "\n", with: " ")
    let trimmed = single.count > 60
        ? String(single.prefix(60)) + "…"
        : single
    return "Last transcript: \"\(trimmed)\" — Copied"
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Diktador/AppDelegate.swift
git commit -m "$(cat <<'EOF'
app: run transcription on each recorder.stop success

Each successful WAV triggers transcribe -> NSPasteboard.general write +
'Last transcript' menu item. Empty transcripts surface 'no speech
detected' without touching the clipboard. Failures log + flash the
status line.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task F3: Manual smoke build (Release)

**Files:** none touched.

- [ ] **Step 1: Build Release**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

(Real verification against a microphone happens in Phase H.)

(No commit.)

---

## Phase G — Documentation

### Task G1: Module README

**Files:**
- Create: `modules/diktador-transcriber/README.md`

- [ ] **Step 1: Write the README**

```markdown
# diktador-transcriber

## Purpose

Transcribes audio files produced by `diktador-recorder` into `String` text using WhisperKit's on-device Whisper inference. v1 ships a single backend (`WhisperKitTranscriber`) with model `openai_whisper-base`; the `Transcriber` protocol exists so a Groq sibling impl can drop in later without touching consumers.

## Public API

Import: `import DiktadorTranscriber`. SwiftPM library and target both named `DiktadorTranscriber`; package directory is `modules/diktador-transcriber/`.

- `Transcriber` — protocol. `state: TranscriberState` (main-actor isolated), `loadModel()`, `transcribe(audioFileURL:)`. All methods `async`.
- `WhisperKitTranscriber` — `@MainActor public final class` implementing `Transcriber`. `init(modelName: String = defaultModelName)` for production; `internal init(driver:modelName:modelStorage:)` is the test seam.
- `WhisperKitTranscriber.defaultModelName` — `"openai_whisper-base"`.
- `WhisperKitTranscriber.defaultModelStorage()` — `~/Library/Application Support/Diktador/models/`.
- `TranscriberState` — `Sendable, Equatable` enum: `.uninitialized` / `.loading` / `.ready` / `.transcribing` / `.failed(TranscriberError)`.
- `TranscriberError` — `Sendable, Equatable` error enum: `.modelLoadFailed(message:)`, `.transcriptionFailed(message:)`, `.audioFileUnreadable(URL)`, `.emptyTranscript`.

State transitions:
- `.uninitialized → .loading → .ready` on successful `loadModel()`.
- `.loading → .failed(.modelLoadFailed(...))` on failure (sticky; restart the app to retry).
- `.ready → .transcribing → .ready` on each `transcribe(...)`. Driver errors return state to `.ready` (transient).

Tests run with `swift test` from `modules/diktador-transcriber/`.

## Dependencies

- WhisperKit (via `argmaxinc/argmax-oss-swift`, from `0.9.0`).
- Foundation (system).
- Deployment target: macOS 14+.
- Network access for the first-run model download (~140 MB for `openai_whisper-base`). Cached under `~/Library/Application Support/Diktador/models/` on subsequent launches.
- No environment variables, no Diktador-internal modules. Consumes WAV files at any `URL` the caller provides — the recorder's output URL is the canonical input but not coupled at compile time.

## Known failure modes

- **Network unavailable on first run.** `loadModel()` throws; state becomes `.failed(.modelLoadFailed(...))`. The recorder still works; transcripts are unavailable until the next launch with network. v1 has no in-app retry button.
- **Model storage directory not writable.** `LiveWhisperKitDriver.loadModel` creates the directory with intermediates; if Application Support is read-only (rare; only happens if disk is full or sandbox blocks it), `WhisperKitConfig` with `download: true` fails and the same `.modelLoadFailed` flow applies.
- **Bogus audio path.** `transcribe(audioFileURL:)` does a `FileManager.fileExists` check before calling the driver; missing files throw `.audioFileUnreadable(URL)` without paying for a model load.
- **Silent recording.** WhisperKit returns no segments (or whitespace only); `WhisperKitTranscriber` throws `.emptyTranscript` and leaves state at `.ready`. AppDelegate surfaces "no speech detected" without modifying the clipboard.
- **WhisperKit inference error.** Driver throws → mapped to `.transcriptionFailed(message:)` and state recovers to `.ready` (transient — next call works).
- **Failed model load is sticky.** Once `state == .failed(...)`, `transcribe` rejects without calling the driver. Restart Diktador to retry. (The settings module will add an in-app retry path later.)
- **Two recordings released in quick succession.** Transcribe tasks queue via Swift structured concurrency; results process in order. Only the *latest* "Last transcript" item is shown — earlier ones are not preserved.
- **Model storage path moves after first download.** v1 uses `~/Library/Application Support/Diktador/models/` and never relocates. If the user nukes that directory, the next launch re-downloads.
- **WhisperKit version mismatch with system OS.** Argmax pins min macOS at the SDK level; on macOS 14+ the `openai_whisper-base` Core ML variant runs on the Neural Engine. Older macOS would fail at link time but is excluded by the deployment target.
```

- [ ] **Step 2: Commit**

```bash
git add modules/diktador-transcriber/README.md
git commit -m "$(cat <<'EOF'
transcriber: module README (purpose, API, deps, failure modes)

Mirrors the recorder/hotkey README structure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G2: ADR — `wiki/decisions/transcriber-pipeline.md`

**Files:**
- Create: `wiki/decisions/transcriber-pipeline.md`

- [ ] **Step 1: Write the ADR**

```markdown
---
type: decision
created: 2026-04-27
updated: 2026-04-27
tags: [transcriber, whisperkit, architecture, macos]
status: stable
sources: []
---

# Transcriber: WhisperKit-only v1, base model, eager-load on launch, clipboard-copy debug surface

## Context

The framework ADR ([[decisions/framework-choice]]) locks WhisperKit (default) + Groq (selectable) as the dual-backend pipeline. The recorder ADR ([[decisions/recorder-capture-pipeline]]) produces 16 kHz mono WAV files that match WhisperKit's expected input and explicitly defers VAD to "the transcriber PR."

Three questions surfaced during this PR's brainstorming:

1. **Does v1 ship both backends, or just WhisperKit?** Groq has no v1 consumer (no settings module to expose the toggle), and the dispatcher's primary/fallback logic only matters when both backends ship. Shipping both adds Keychain + HTTPS + the dispatcher with no user-visible difference vs WhisperKit-only.
2. **Where does the transcript land in v1?** The output module (text injection at the cursor) is deferred. Without it, the transcript needs a temporary destination so push-to-talk → text is verifiable end-to-end via `/go` computer-use.
3. **When does the model download fire?** WhisperKit's `openai_whisper-base` is ~140 MB. Lazy on first transcription means the user's first press feels broken. Eager on launch surfaces the wait honestly via the menu bar.

## Decision

**v1 ships WhisperKit only, behind the `Transcriber` protocol.** A single concrete impl `WhisperKitTranscriber` lives in `modules/diktador-transcriber/`. The protocol seam means Groq drops in later as a sibling impl without touching consumers; v1 has no dispatcher (single impl).

**Hard-coded model: `openai_whisper-base`** (~140 MB). Matches typr's chosen default. Settings module will expose `tiny` / `base` / `small` and the picker UI in a follow-up.

**Eager load on app launch** via a detached `Task` in `applicationDidFinishLaunching` after `bootstrapPushToTalk` runs. State transitions `.uninitialized → .loading → .ready` over network. If the user holds Fn before the model is ready, the recording still works (recorder is independent); transcription awaits the in-flight load via Swift structured concurrency.

**Clipboard-copy as the v1 output destination.** On successful transcription, AppDelegate copies the transcript to `NSPasteboard.general` and surfaces a "Last transcript: '...' — Copied" menu item. Click re-copies the full transcript. Verifiable via `Cmd+V` in any app. The output module replaces this when it lands.

**Internal `WhisperKitDriver` test seam** mirrors the recorder's `AudioEngineDriver` pattern: only `LiveWhisperKitDriver` imports `WhisperKit`; tests inject a stub. Lets the state machine be exercised without the model.

**Model storage at `~/Library/Application Support/Diktador/models/`**, alongside the recorder's `recordings/` directory. Survives reinstalls; doesn't pollute `~/Documents`.

**VAD stays deferred.** Push-to-talk + WhisperKit's batch `transcribe(audioPath:)` consume the complete WAV file. WhisperKit's built-in VAD will land alongside continuous-listening mode in a later PR.

## Consequences

- **No user-visible Groq toggle in v1.** The settings module's first job will be exposing the backend picker plus the API-key entry field; until then, Diktador is local-only.
- **First launch downloads ~140 MB.** Menu status line ("Loading transcription model…") makes the wait visible. On metered networks the user gets a deterministic message rather than silence.
- **Clipboard-copy is a load-bearing temporary.** It will be replaced when the output module lands. Today it provides the verification path for `/go` computer-use and the friends-distribution feedback loop.
- **`.failed` model state is sticky.** Once `loadModel` fails, transcription is unavailable until the user restarts Diktador. v1 has no in-app retry button — settings module concern.
- **The "Last transcript" menu item only ever shows one transcript.** Rapid press-release-press cycles overwrite the previous label. Persisted transcript history is a settings-module feature.
- **WhisperKit's transitive deps land in the app bundle.** Argmax's Core ML wrappers + tokenizer assets add to the binary. Acceptable: WhisperKit is the framework ADR's chosen default.
- **No network reachability probe.** WhisperKit attempts the download; failure surfaces via `.modelLoadFailed`. Adding a proactive probe would buy a marginally better error message and a `Network.framework` dependency.
- **Test seam covers everything but the WhisperKit call itself.** State machine, queue-while-loading, error mapping, sticky failure, empty-transcript handling all unit-tested. Real WhisperKit transcription is verified during `/go` computer-use, the same shape as the recorder's "real audio" verification.

## Alternatives considered

1. **WhisperKit + Groq dispatched in v1.** Rejected: no settings UI to expose the toggle. Pure code without a v1 consumer.
2. **Lazy model download on first transcription.** Rejected: the first press would feel broken. Eager-on-launch surfaces the wait via the menu bar.
3. **Bundle the model with the app.** Rejected: ~140 MB app bundle for a feature that's downloadable. WhisperKit is designed for HuggingFace Hub fetching.
4. **Manual "Download model" menu item.** Rejected: friction without payoff. Eager-on-launch is the same UX with less work.
5. **Auto-fire transcription with menu-bar display only (no clipboard).** Rejected: clipboard-copy gives `/go` computer-use a real target (paste into TextEdit). Without it, the only verification is reading the menu, which can't be automated.
6. **Manual-fire from a "Transcribe last recording" menu item.** Rejected: doubles the click count for every test, and the "speak → see typed text" UX is what users expect.
7. **`tiny` model default.** Rejected: accuracy is shaky enough that the first-impression test ("dictation got it wrong → user gives up") hits hard. `base` matches typr's chosen default.
8. **`small` model default.** Rejected: ~470 MB first-run download is too much friction for v1. Settings-module picker can upgrade later.
9. **WhisperKit standalone repo (`argmaxinc/WhisperKit`).** Argmax migrated WhisperKit into the `argmax-oss-swift` umbrella alongside TTSKit + SpeakerKit. The umbrella is the current canonical form; we depend on it directly so future kits land transitively.
10. **Stream transcription as audio arrives.** Rejected: push-to-talk produces a single buffer at stop. Streaming buys nothing without continuous-listening mode.

## Sources

- [`modules/diktador-transcriber/README.md`](../../modules/diktador-transcriber/README.md) — public API, dependencies, failure modes.
- [`memory/domains/transcriber.md`](../../memory/domains/transcriber.md) — operational notes + open questions.
- [`docs/superpowers/specs/2026-04-27-transcriber-module-design.md`](../../docs/superpowers/specs/2026-04-27-transcriber-module-design.md) — design doc this ADR ratifies.
- [[decisions/framework-choice]] — parent ADR (locks Swift / WhisperKit / Groq dual-backend).
- [[decisions/recorder-capture-pipeline]] — sibling ADR; locks the WAV format the transcriber consumes; defers VAD to here.
- [[decisions/hotkey-modifier-only-trigger]] — sibling ADR; establishes the dual-init test-seam pattern this module follows.
- WhisperKit (Argmax OSS Swift): https://github.com/argmaxinc/argmax-oss-swift
```

- [ ] **Step 2: Commit**

```bash
git add wiki/decisions/transcriber-pipeline.md
git commit -m "$(cat <<'EOF'
adr: transcriber pipeline — WhisperKit-only v1, base, eager-load, clipboard

Ratifies the design doc for PR #6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G3: Module wiki page

**Files:**
- Create: `wiki/modules/transcriber.md`

- [ ] **Step 1: Write the page**

```markdown
---
type: module
created: 2026-04-27
updated: 2026-04-27
tags: [module, transcriber, whisperkit]
status: stable
---

# Transcriber

> Audio-file → text via WhisperKit. v1 ships local-only on `openai_whisper-base`; Groq sibling backend deferred.

## Purpose

Consumes 16 kHz mono PCM WAV files produced by [[modules/recorder]] and returns plain `String` transcripts. The module owns the WhisperKit lifecycle (model load, in-memory pipeline, transcription calls) and exposes a small `Transcriber` protocol so a future Groq backend can slot in as a sibling impl.

## Public API

`Transcriber` protocol — `state: TranscriberState`, `loadModel() async throws`, `transcribe(audioFileURL:) async throws -> String`. `WhisperKitTranscriber` is the v1 concrete impl. See [`modules/diktador-transcriber/README.md`](../../modules/diktador-transcriber/README.md) for the full surface.

## Design decisions

The decision to ship WhisperKit-only in v1, hard-code `openai_whisper-base`, eager-load on app launch, and copy transcripts to the clipboard as a stand-in for the output module is captured in [[decisions/transcriber-pipeline]]. The dual-backend framework lock that this module satisfies is in [[decisions/framework-choice]].

The `WhisperKitDriver` internal protocol mirrors the recorder's `AudioEngineDriver` test seam — only the `LiveWhisperKitDriver` source file imports WhisperKit, so unit tests run without touching the model or the network.

State machine:

```
.uninitialized → .loading → .ready ↔ .transcribing
                     │
                     └─→ .failed(...)   (sticky; restart to retry)
```

`loadModel` is idempotent and concurrent-safe via an in-flight `Task` reference; `transcribe` from `.uninitialized` drives `loadModel` implicitly.

## Dependencies

- `WhisperKit` from [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift), `from: 0.9.0`.
- Foundation.
- Network access for first-run model download (~140 MB for `openai_whisper-base`).
- No coupling to other Diktador modules at compile time. Consumes WAV files at any `URL` the caller provides.

## Open questions

- Model picker UX (settings module concern).
- Groq backend + dispatcher (follow-up PR).
- VAD / continuous-listening mode (deferred again, per the recorder ADR's deferral and the framework ADR).
- Cancellation of an in-flight transcription.
- Transcript history beyond the most-recent.
- Network reachability probe before download.
- WhisperKit version pinning policy (currently `from: 0.9.0` — no aggressive lock).

## Related

- [[modules/recorder]] — produces the WAV files this module consumes.
- [[decisions/transcriber-pipeline]] — design rationale.
- [[decisions/framework-choice]] — parent ADR.
- [[decisions/recorder-capture-pipeline]] — sibling ADR; locks the WAV format.
```

- [ ] **Step 2: Commit**

```bash
git add wiki/modules/transcriber.md
git commit -m "$(cat <<'EOF'
wiki: transcriber module page

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G4: Memory domain note

**Files:**
- Create: `memory/domains/transcriber.md`

- [ ] **Step 1: Write the file**

```markdown
---
type: memory-domain
domain: transcriber
created: 2026-04-27
updated: 2026-04-27
---

# Transcriber — operational notes

Public surface and failure modes live in [`modules/diktador-transcriber/README.md`](../../modules/diktador-transcriber/README.md). This file is for working-memory shorthand only — do not duplicate the README.

## v1 configuration

- Backend: WhisperKit only. Groq deferred.
- Model: hard-coded `openai_whisper-base` (~140 MB).
- Storage: `~/Library/Application Support/Diktador/models/`. WhisperKit caches there; subsequent launches load from disk in ~1–2 s.
- Lifecycle: eager `loadModel()` from `applicationDidFinishLaunching` after `bootstrapPushToTalk`. Fn press still recordable while loading; transcription awaits.
- Output: `NSPasteboard.general.setString(transcript, forType: .string)` on every successful transcription. "Last transcript: '<60 chars>…' — Copied" menu item; click re-copies.
- Empty transcripts: `.emptyTranscript` thrown; AppDelegate surfaces "no speech detected" and does **not** modify the clipboard.
- Threading: `WhisperKitTranscriber` is `@MainActor`; `LiveWhisperKitDriver` calls into WhisperKit (its own actor isolation) via `await`.

## /go computer-use verification recipe

1. Build Release. Launch Diktador.
2. Wait for menu status: "Transcription: ready". On a fresh install watch for "loading model…" first; ~30–60 s on a typical connection.
3. Hold Fn, speak a known phrase ("Hello, this is a test of Diktador transcription."), release.
4. Menu flashes "transcribing…" → "ready". "Last transcript: …" item appears.
5. `Cmd+V` in TextEdit — transcript pastes.
6. Quit + relaunch — model loads from cache in ~1–2 s.

## Open questions (deferred to follow-up PRs)

- **Groq sibling backend.** Adds Keychain + HTTPS + dispatcher. Lands when settings module exposes the picker.
- **Model picker.** v1 hard-codes `openai_whisper-base`. Settings will expose `tiny` / `base` / `small`.
- **VAD.** Deferred again; depends on continuous-listening mode existing.
- **Cancellation.** No "cancel transcribe" menu in v1. A Fn press during `.transcribing` records normally; the transcribe tasks queue and resolve in order.
- **Transcript history.** Only most-recent surfaced today.
- **Network reachability probe.** Could improve the error message; adds Network.framework dep.
- **Recordings cleanup tied to successful transcription.** Today the WAV is kept (matches recorder ADR's debug intent).

## Debug recipes

- Menu shows "model unavailable — see Console": `loadModel` failed. Check Console for `[app] transcriber.loadModel failed: <error>`. Most common cause on a clean install is no network during the HuggingFace Hub fetch. Restart Diktador after restoring connectivity.
- `transcribe` returns "no speech detected" for audible recordings: WhisperKit's segments came back empty. Possible causes: extremely short hold (<200 ms), microphone gain pinned to zero, accent/language drift (WhisperKit auto-detects but English is the most reliable). Replay the WAV from "Last recording: … Reveal in Finder" to check what was captured.
- Transcribe is slow (>10 s for a 3 s hold): first transcribe after launch loads weights into the Neural Engine. Subsequent transcriptions are faster.
- Models redownload on every launch: `~/Library/Application Support/Diktador/models/` was deleted or moved. Restore the directory or accept the re-download.
- Clipboard contains the previous transcript after an empty hold: by design — empty transcripts don't overwrite the clipboard, so a `Cmd+V` after a misfire still pastes the last good result.
- `state == .failed` is stuck even after restart: WhisperKitConfig threw before the network call. Check Console for the underlying error; common cause is a corrupted partial download under `models/` — `rm -rf ~/Library/Application\ Support/Diktador/models/` and relaunch.

## See also

- [`modules/diktador-transcriber/README.md`](../../modules/diktador-transcriber/README.md) — public API, dependencies, full failure-mode list.
- [`wiki/decisions/transcriber-pipeline.md`](../../wiki/decisions/transcriber-pipeline.md) — VAD-redeferral, model-default, eager-load decisions.
- [`memory/domains/recorder.md`](recorder.md) — produces the WAV files this module consumes.
```

- [ ] **Step 2: Commit**

```bash
git add memory/domains/transcriber.md
git commit -m "$(cat <<'EOF'
memory: transcriber domain notes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G5: Update `wiki/index.md`

**Files:**
- Modify: `wiki/index.md`

- [ ] **Step 1: Read current index**

Run: `cat wiki/index.md`

- [ ] **Step 2: Update Decisions and Modules counts and entries**

Edit `wiki/index.md`:

- Change `## Decisions (3)` to `## Decisions (4)`.
- Append a new entry to the Decisions list (preserving sort by date — this is the newest):

```markdown
- [[decisions/transcriber-pipeline]] — WhisperKit-only v1; `openai_whisper-base`; eager-load on launch; clipboard-copy debug surface; Groq + VAD deferred. | 2026-04-27
```

- Change `## Modules (1)` to `## Modules (2)`.
- Append:

```markdown
- [[modules/transcriber]] — WhisperKit transcription of recorder WAVs; clipboard-copy stand-in until output module lands. | 2026-04-27
```

- Remove the corresponding "_Proposed_: entity page on **WhisperKit**" line from the Stubs / TODO section if it now references this module's existence (the stub-page rule is "create when a second page references it" — `framework-choice` was the first reference; `transcriber-pipeline` and `modules/transcriber` are second/third, so an `entities/whisperkit` stub is now warranted; leave as-is for a future entity-creation pass and don't block this PR on it).

- [ ] **Step 3: Commit**

```bash
git add wiki/index.md
git commit -m "$(cat <<'EOF'
wiki/index: register transcriber ADR + module page

Decisions 3->4, Modules 1->2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G6: Append `log.md`

**Files:**
- Modify: `log.md`

- [ ] **Step 1: Append `document` entry for the ADR + module page**

Append to `log.md`:

```markdown
## [2026-04-27] document | Transcriber module — WhisperKit + clipboard-copy debug surface

Files created:
- docs/superpowers/specs/2026-04-27-transcriber-module-design.md
- docs/superpowers/plans/2026-04-27-transcriber-module.md
- modules/diktador-transcriber/ (Package.swift, sources, tests, README)
- wiki/decisions/transcriber-pipeline.md
- wiki/modules/transcriber.md
- memory/domains/transcriber.md

Files updated:
- project.yml — DiktadorTranscriber package + product dep on Diktador target
- Diktador/AppDelegate.swift — transcriber owned, loadModel on launch, runTranscription on recorder.stop, clipboard-copy + menu surfaces
- wiki/index.md — Decisions 3->4, Modules 1->2

Notes:
- WhisperKit pulled via argmaxinc/argmax-oss-swift from 0.9.0 (umbrella package; product `WhisperKit`).
- Hard-coded model `openai_whisper-base` (~140 MB). Settings-module picker deferred.
- Eager load on launch; menu status line + "Last transcript" item.
- Groq backend + VAD deferred to follow-up PRs (framework ADR + recorder ADR open questions persist).
```

- [ ] **Step 2: Commit**

```bash
git add log.md
git commit -m "$(cat <<'EOF'
log: document transcriber module shipping

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase H — Ship cycle (`/go`)

Workspace `/go` is three phases: end-to-end test (computer-use), `/simplify`, PR. We follow the same shape but spell out each step.

### Task H1: End-to-end computer-use verification

**Files:** none touched (verification only).

- [ ] **Step 1: Build Release**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: Locate the built app**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release -showBuildSettings 2>/dev/null | awk '/ TARGET_BUILD_DIR /{print $3}'`
Note the path; the Diktador.app will be at `<TARGET_BUILD_DIR>/Diktador.app`.

- [ ] **Step 3: Launch Diktador**

Run: `open "<TARGET_BUILD_DIR>/Diktador.app"`

Expected sequence in the menu bar (click the icon to view the menu):
- Status row: `Diktador (idle)` — once Input Monitoring + Microphone are granted (one-time on a fresh install / after a `tccutil reset`).
- Transcription status: `Transcription: loading model…` for ~30–60 s on first run (HuggingFace Hub download), ~1–2 s on subsequent launches (cached at `~/Library/Application Support/Diktador/models/`).
- Transcription status changes to `Transcription: ready`.

If the model load fails (no network, etc.) the status will show `Transcription: model unavailable — see Console`. Check Console.app for `[app] transcriber.loadModel failed: …`.

- [ ] **Step 4: Test push-to-talk → transcript**

Hold Fn, speak the test phrase: **"Hello, this is a test of Diktador transcription."** Release Fn.

Expected:
- Status row flashes `Diktador (listening…)` while Fn is held, then back to `(idle)` on release.
- Transcription status flashes `Transcription: transcribing…` (typically <2 s for a 3-second hold on Apple Silicon) then back to `Transcription: ready`.
- New menu items appear:
  - `Last transcript: "Hello, this is a test of Diktador transcription." — Copied`
  - `Last recording: 3.2s — Reveal in Finder`

- [ ] **Step 5: Verify clipboard**

Open TextEdit (or any text-input app) and press `Cmd+V`. The transcript pastes verbatim.

- [ ] **Step 6: Verify "no speech detected" path**

Hold Fn briefly (<300 ms) without speaking; release. Expected: `Transcription: no speech detected` in the menu bar status; `Cmd+V` still pastes the *previous* transcript (clipboard untouched on empty results).

- [ ] **Step 7: Verify the cached-model path**

Quit Diktador (`Cmd+Q` from the menu). Relaunch. Expected: status moves through `loading model…` → `ready` in ~1–2 s without a network round-trip.

- [ ] **Step 8: Click `Last transcript`**

Click the menu item. Expected: re-copies the full transcript to the clipboard (verify with another `Cmd+V`).

If any step fails, do **not** mark this task complete — debug, fix on a new task, return here.

(No commit — verification only.)

### Task H2: `/simplify` pass on the new module

**Files:** potentially modified by `/simplify` agents (within the new module + AppDelegate).

- [ ] **Step 1: Run `/simplify`**

In the Claude Code session (this is the `simplify` skill — invoked by typing `/simplify`):

```
/simplify modules/diktador-transcriber/ Diktador/AppDelegate.swift
```

Three agents (reuse, quality, efficiency) review the new code. Apply fixes when ≥2 agents flag the same issue (the workspace's "convergence pattern" — single-agent flags are usually defensible-as-is per `memory/resume.md`).

- [ ] **Step 2: Re-run tests after any changes**

Run: `cd modules/diktador-transcriber && swift test 2>&1 | tail -10`
Expected: 13/13 (or more, if `/simplify` added tests) green.

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit any `/simplify` fixes (one commit per logical change, not one big sweep)**

```bash
git add <paths>
git commit -m "<topic>: <one-line>

<why>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

If `/simplify` had nothing to flag (or all flags were single-agent and defensible), skip — no empty commit.

### Task H3: Final code review on the whole branch

**Files:** none touched.

- [ ] **Step 1: Dispatch `superpowers:code-reviewer`**

Use the Agent tool with `subagent_type: superpowers:code-reviewer`. Prompt:

> Review the entirety of branch `feat/transcriber-module` against:
> - the spec at `docs/superpowers/specs/2026-04-27-transcriber-module-design.md`
> - this plan at `docs/superpowers/plans/2026-04-27-transcriber-module.md`
> - the workspace's `AGENTS.md` schema (modular construction, error ownership, public-vs-private surface, no-shared-mutable-state).
>
> Flag any deviations, missing tests, missing failure modes in the README, or contradictions between the spec and what shipped. Limit to material issues — style nits the `/simplify` pass would have caught are out of scope.

- [ ] **Step 2: Address material issues with new commits**

For each material issue: fix on a new commit. Trivial issues bundled into a single "review fixes" commit are OK; substantive ones get their own commit + tests.

### Task H4: Update `memory/resume.md` for post-ship state

**Files:**
- Modify: `memory/resume.md`

- [ ] **Step 1: Rewrite `memory/resume.md`**

Replace the body with the post-PR-#6 handoff: clean main, transcriber shipped, recommend the next pick (output module — text injection at cursor — to complete the dictation loop). Lift the active-state details from `git log`, `gh pr view`, and the verification recipe above.

Section structure (mirror the current resume.md):
- Active state at end of session (branch, PR merged commit, build status, test counts).
- Pending action from you (likely none).
- What the app does today (now: Fn → record → transcribe → clipboard → paste).
- What to do next session — the natural pick is **Output module** (text injection at cursor; clipboard-paste primary + CGEvent fallback). Brief alternatives: Settings module (model picker, Groq key), Groq backend.
- Key files to load on resume.
- Sharp edges to remember (lift the new transcriber-relevant ones from the ADR + memory domain note).

- [ ] **Step 2: Commit**

```bash
git add memory/resume.md
git commit -m "$(cat <<'EOF'
memory/resume: post-PR-#6 handoff

Transcriber shipped; output module is the natural next pick.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task H5: Push branch + open PR

**Files:** none touched.

- [ ] **Step 1: Push the branch**

Run: `git push -u origin feat/transcriber-module`
Expected: branch pushed, tracking set up.

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "Transcriber module — WhisperKit transcription with clipboard-copy debug surface (#6)" --body "$(cat <<'EOF'
## Summary
- New `diktador-transcriber` module wraps WhisperKit (`openai_whisper-base`) behind a `Transcriber` protocol; future Groq backend slots in as a sibling impl.
- AppDelegate eager-loads the model on launch (menu status line) and auto-transcribes each recorder.stop success, copying the transcript to `NSPasteboard.general` with a "Last transcript" menu item.
- Spec at `docs/superpowers/specs/2026-04-27-transcriber-module-design.md`; ADR at `wiki/decisions/transcriber-pipeline.md`.

## Test plan
- [x] `swift test` green in `modules/diktador-transcriber/` (13/13 — state machine, error mapping, queue-while-loading, sticky failure, empty-transcript handling).
- [x] `swift test` still green in `modules/diktador-recorder/` (9/9) and `modules/diktador-hotkey/` (8/8) — no regressions.
- [x] `xcodebuild` Debug + Release build green.
- [x] Computer-use verified: launch → "loading model…" → "ready"; hold Fn + speak + release → transcript on clipboard, menu items updated; quit + relaunch → cached model loads in ~1–2 s; empty hold → "no speech detected" without clobbering clipboard.

## Out of scope (deferred)
- Groq sibling backend + dispatcher (needs settings module).
- VAD / continuous-listening mode (deferred again; next time it surfaces is the continuous-listening PR).
- Settings module (model picker, API key entry, primary/fallback selection).
- Output module (text injection at cursor) — clipboard-copy is a v1 stand-in.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Print the PR URL**

The `gh pr create` command outputs the URL on success. Note it for the user.

(No further commit; the PR ride from here is up to merge cadence — `gh pr merge` once green.)

### Task H6: Post-merge cleanup

**Files:** post-merge state only.

- [ ] **Step 1: Wait for merge** (driven by user / CI). Skip ahead until the PR is merged.

- [ ] **Step 2: Sync local main**

```bash
git checkout main && git pull origin main && git branch -d feat/transcriber-module
```

- [ ] **Step 3: Verify clean state**

Run: `git status && git log -3 --oneline`
Expected: branch `main`, clean tree, the merge commit at the top.

(No further commits unless `memory/resume.md` requires another touch — the post-ship resume.md commit went out as part of the PR, not as a follow-up.)

---

## Self-review

Spec coverage walk-through (each spec section → which task implements it):

| Spec section | Implementing tasks |
|---|---|
| Module shape — package + library naming | B1 |
| Public `Transcriber` protocol | C1 |
| `TranscriberState` + `TranscriberError` enums | C1 |
| `WhisperKitTranscriber` happy-path `loadModel` | D2 |
| `loadModel` idempotent + concurrent-safe | D4, D5 |
| `loadModel` failure → `.failed(.modelLoadFailed)` | D2 (impl), D3 (test) |
| `WhisperKitDriver` test seam | D1 |
| `LiveWhisperKitDriver` real WhisperKit wiring | E1 |
| `transcribe` happy path | D6 |
| `transcribe` from `.uninitialized` triggers `loadModel` | D9 |
| `transcribe` while `.loading` awaits in-flight load | D10 |
| `transcribe` after `.failed` rejects without driver | D11 |
| Empty / whitespace-only transcripts → `.emptyTranscript` | D7 |
| Driver throw → `.transcriptionFailed`, state recovers | D8 |
| Missing audio file → `.audioFileUnreadable` | D12 |
| Model storage at `~/Library/Application Support/Diktador/models/` | D2 (`defaultModelStorage`), E1 (createDirectory) |
| `project.yml` package wiring | E2 |
| AppDelegate `loadModel` on launch + status line | F1 |
| AppDelegate auto-transcribe on `recorder.stop` | F2 |
| Clipboard write + "Last transcript" menu item | F2 |
| "No speech detected" path keeps clipboard intact | F2 |
| Module README | G1 |
| ADR `wiki/decisions/transcriber-pipeline.md` | G2 |
| Module wiki page | G3 |
| `memory/domains/transcriber.md` | G4 |
| `wiki/index.md` updates | G5 |
| `log.md` entry | G6 |
| Computer-use verification recipe | H1 |
| `/simplify` pass | H2 |
| Final whole-branch code review | H3 |
| `memory/resume.md` post-ship update | H4 |
| PR creation | H5 |

No spec sections without a task. No tasks without a spec hook (the `/simplify` and review tasks belong to the workspace's standard `/go` cadence rather than the spec, but they ship every PR — see `memory/resume.md` "subagent-driven cadence").

Placeholder scan: the plan contains no "TBD", "TODO", "implement later", or vague "add appropriate error handling". Every code-bearing step has a code block; every command has the expected output named.

Type consistency:
- `Transcriber` protocol surface (`loadModel`, `transcribe(audioFileURL:)`, `state: TranscriberState`) is consistent across C1, D2, D6, F1, F2, README, and ADR.
- `TranscriberError` cases (`modelLoadFailed(message:)`, `transcriptionFailed(message:)`, `audioFileUnreadable(URL)`, `emptyTranscript`) are stable across the type definition (C1), all tests (D3, D7, D8, D11, D12), the impl (D2 onwards), and the README/ADR.
- `WhisperKitTranscriber.defaultModelName == "openai_whisper-base"` is the same string everywhere it appears.
- AppDelegate constants (`transcriberLoadingTitle`, etc.) are introduced in F1 and referenced in F2; both tasks use the same names.
- `WhisperKitDriver.loadModel(name:modelStorage:)` and `transcribe(audioFileURL:)` signatures match between the protocol (D1), the stub (D1), and the live impl (E1).
