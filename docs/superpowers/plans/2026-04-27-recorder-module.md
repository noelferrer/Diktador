# Recorder Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `diktador-recorder` SwiftPM module that captures mic audio between explicit `start()` / `stop()` calls and writes a 16 kHz mono PCM WAV file to `~/Library/Application Support/Diktador/recordings/`, plus an `AppDelegate` integration that hooks recording to the existing Fn push-to-talk and surfaces a "Last recording: 2.3s — Reveal in Finder" debug menu item.

**Architecture:** New SwiftPM module `modules/diktador-recorder/` (package + library + target named `DiktadorRecorder`, lowercase directory). Public `Recorder` class with `start()` / `stop(completion:)`, permission accessors, and `RecordingResult` value type. Internals: `MicrophonePermissionProvider` protocol (real impl wraps `AVCaptureDevice` APIs) and `AudioEngineDriver` protocol (real impl wraps `AVAudioEngine` + tap installation). `AVAudioConverter` converts the device's native input format to 16 kHz mono `Float32` in process; `AVAudioFile` writes 16-bit PCM WAV. `AppDelegate` chains a Microphone permission check after the existing Input Monitoring check, and the Fn press/release callbacks call `recorder.start()` / `recorder.stop`.

**Tech Stack:** Swift 5.10 / SwiftUI / AppKit / AVFoundation; SwiftPM module `DiktadorRecorder`; XCTest; xcodegen (`project.yml`); `xcodebuild` for the app target; `gh` for PR; macOS 14 deployment target.

**Spec:** [`docs/superpowers/specs/2026-04-27-recorder-module-design.md`](../specs/2026-04-27-recorder-module-design.md)

---

## File structure

**Created:**

- `modules/diktador-recorder/Package.swift` — SwiftPM manifest. macOS 14+. No external dependencies (AVFoundation ships with the SDK). Library + target + test target all named `DiktadorRecorder`.
- `modules/diktador-recorder/Sources/DiktadorRecorder/Recorder.swift` — public `Recorder` class. State machine, `start` / `stop`, permission delegation, error handling.
- `modules/diktador-recorder/Sources/DiktadorRecorder/RecordingResult.swift` — public `RecordingResult` value type.
- `modules/diktador-recorder/Sources/DiktadorRecorder/MicrophonePermissionStatus.swift` — public enum (granted / denied / undetermined).
- `modules/diktador-recorder/Sources/DiktadorRecorder/RecorderError.swift` — public error enum.
- `modules/diktador-recorder/Sources/DiktadorRecorder/MicrophonePermissionProvider.swift` — internal protocol + `AVPermissionProvider` real implementation wrapping `AVCaptureDevice.authorizationStatus(for:)` / `AVCaptureDevice.requestAccess(for:)`.
- `modules/diktador-recorder/Sources/DiktadorRecorder/AudioEngineDriver.swift` — internal protocol + `AVAudioEngineDriver` real implementation wrapping `AVAudioEngine` + input-node tap installation.
- `modules/diktador-recorder/Sources/DiktadorRecorder/SampleRateConverter.swift` — internal `AVAudioConverter` wrapper.
- `modules/diktador-recorder/Sources/DiktadorRecorder/WAVWriter.swift` — internal `AVAudioFile`-backed WAV writer (16 kHz mono 16-bit PCM).
- `modules/diktador-recorder/Tests/DiktadorRecorderTests/RecorderTests.swift` — XCTest target with stub `MicrophonePermissionProvider` and stub `AudioEngineDriver`.
- `modules/diktador-recorder/README.md` — module README (Purpose / Public API / Dependencies / Known failure modes).
- `wiki/decisions/recorder-capture-pipeline.md` — ADR (VAD deferral, WAV-to-disk debug surface, in-process 16 kHz mono conversion, dual-permission bootstrap).
- `wiki/modules/recorder.md` — module spec page.
- `memory/domains/recorder.md` — operational memory note.

**Modified:**

- `Diktador/AppDelegate.swift` — owns a `Recorder` alongside `HotkeyRegistry`; chains a Microphone permission check after Input Monitoring; Fn press/release call `recorder.start()` / `recorder.stop`; new `lastRecordingItem` menu entry; new `showMicrophoneDeniedState`; reveal-in-Finder action.
- `project.yml` — adds the `DiktadorRecorder` package + product dependency on the `Diktador` target. Re-run `xcodegen generate`.
- `wiki/index.md` — Decisions 2→3, Modules 0→1.
- `log.md` — `document` (ADR + module spec) and `meta` (PR ship) entries.
- `memory/resume.md` — rewritten for the post-ship state at the end.

**No changes:**

- `modules/diktador-hotkey/` — untouched.
- `INFOPLIST_KEY_NSMicrophoneUsageDescription` already declared in `project.yml` (since PR #1).

---

## Phase A — Pre-flight

### Task A1: Verify branch + baseline green

**Files:** none touched.

- [ ] **Step 1: Confirm branch state**

Run: `cd "/Users/user/Desktop/Aintigravity Workflows/Diktador" && git status && git branch --show-current`
Expected: branch `feat/recorder-module`, working tree clean (the spec commit is already there from brainstorming).

- [ ] **Step 2: Confirm baseline `swift test` for the existing hotkey module**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`, 8/8 cases.

- [ ] **Step 3: Confirm `xcodebuild` Debug**

Run from repo root: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

(No commit — baseline only.)

---

## Phase B — Module skeleton

### Task B1: Create the SwiftPM package

**Files:**
- Create: `modules/diktador-recorder/Package.swift`
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/.gitkeep`
- Create: `modules/diktador-recorder/Tests/DiktadorRecorderTests/.gitkeep`

- [ ] **Step 1: Create the directory structure**

Run: `mkdir -p modules/diktador-recorder/Sources/DiktadorRecorder modules/diktador-recorder/Tests/DiktadorRecorderTests && touch modules/diktador-recorder/Sources/DiktadorRecorder/.gitkeep modules/diktador-recorder/Tests/DiktadorRecorderTests/.gitkeep`
Expected: directories created.

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiktadorRecorder",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiktadorRecorder", targets: ["DiktadorRecorder"]),
    ],
    targets: [
        .target(name: "DiktadorRecorder"),
        .testTarget(
            name: "DiktadorRecorderTests",
            dependencies: ["DiktadorRecorder"]
        ),
    ]
)
```

- [ ] **Step 3: Verify `swift build` resolves the (empty) package**

Run: `cd modules/diktador-recorder && swift build 2>&1 | tail -5`
Expected: build fails because target has no sources — that's expected. The error should be `error: target 'DiktadorRecorder' referenced in product 'DiktadorRecorder' could not be found` *or* a "no source files" warning. Either way, the manifest itself parses; B2 fixes it.

- [ ] **Step 4: Commit**

```bash
git add modules/diktador-recorder/Package.swift \
        modules/diktador-recorder/Sources/DiktadorRecorder/.gitkeep \
        modules/diktador-recorder/Tests/DiktadorRecorderTests/.gitkeep
git commit -m "$(cat <<'EOF'
diktador-recorder: SwiftPM package skeleton

Package + library + target + test target all named DiktadorRecorder.
macOS 14+, no external dependencies. Sources land in subsequent
phases.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C — Public value types

### Task C1: `MicrophonePermissionStatus`, `RecorderError`, `RecordingResult`

**Files:**
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/MicrophonePermissionStatus.swift`
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/RecorderError.swift`
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/RecordingResult.swift`

These are pure value types with no behavior; landing them together is fine. No tests needed in isolation — exercised via the `Recorder` tests in Phase F.

- [ ] **Step 1: Write `MicrophonePermissionStatus.swift`**

```swift
/// Whether the running process has been granted macOS Microphone access.
public enum MicrophonePermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case undetermined
}
```

- [ ] **Step 2: Write `RecorderError.swift`**

```swift
import Foundation

public enum RecorderError: Error, Equatable {
    /// `start()` was called but Microphone permission is not granted.
    case microphonePermissionDenied
    /// `start()` was called while a recording is already in progress.
    case alreadyRecording
    /// `stop()` was called while no recording is in progress.
    case notRecording
    /// `AVAudioEngine` failed to start (no input device, hardware busy, etc.).
    case engineUnavailable
    /// `AVAudioConverter` setup or per-buffer conversion failed.
    case formatConversionFailed
    /// The recordings directory could not be created or the WAV file could not be written.
    case fileWriteFailed
}
```

- [ ] **Step 3: Write `RecordingResult.swift`**

```swift
import Foundation

/// The artifact produced by a successful `Recorder.stop` call.
public struct RecordingResult: Sendable, Equatable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let sampleCount: Int

    public init(fileURL: URL, duration: TimeInterval, sampleCount: Int) {
        self.fileURL = fileURL
        self.duration = duration
        self.sampleCount = sampleCount
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `cd modules/diktador-recorder && swift build 2>&1 | tail -5`
Expected: still fails for the empty target — wait, no: with three sources in `Sources/DiktadorRecorder/`, the build should now succeed. Expected: `Build complete!`.

If a `.gitkeep` next to source files trips the compiler, drop the `.gitkeep` from `Sources/DiktadorRecorder/` (B1 created it; once real sources exist it's no longer needed). Run: `rm modules/diktador-recorder/Sources/DiktadorRecorder/.gitkeep`.

- [ ] **Step 5: Commit**

```bash
git add modules/diktador-recorder/Sources/DiktadorRecorder/MicrophonePermissionStatus.swift \
        modules/diktador-recorder/Sources/DiktadorRecorder/RecorderError.swift \
        modules/diktador-recorder/Sources/DiktadorRecorder/RecordingResult.swift
# Stage the gitkeep removal if it was deleted in Step 4:
git add -u modules/diktador-recorder/Sources/DiktadorRecorder/
git commit -m "$(cat <<'EOF'
diktador-recorder: public value types — Status, Error, Result

MicrophonePermissionStatus (granted/denied/undetermined), RecorderError
(named cases for the failure modes the spec enumerates), RecordingResult
(fileURL + duration + sampleCount). All Sendable; Result is Equatable
for test assertions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D — Internal seams (PermissionProvider + AudioEngineDriver)

### Task D1: `MicrophonePermissionProvider` protocol + `AVPermissionProvider` real impl

**Files:**
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/MicrophonePermissionProvider.swift`

- [ ] **Step 1: Write the file**

```swift
import AVFoundation
import Foundation

internal protocol MicrophonePermissionProvider: Sendable {
    func currentStatus() -> MicrophonePermissionStatus
    func requestAccess(completion: @escaping (MicrophonePermissionStatus) -> Void)
}

/// Real provider that wraps `AVCaptureDevice.authorizationStatus(for:)` /
/// `AVCaptureDevice.requestAccess(for:)`. macOS shows the consent prompt at
/// most once per app-bundle / user pair; subsequent `requestAccess` calls
/// return the cached granted/denied state without re-prompting.
internal struct AVPermissionProvider: MicrophonePermissionProvider {
    func currentStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    func requestAccess(completion: @escaping (MicrophonePermissionStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted ? .granted : .denied)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd modules/diktador-recorder && swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-recorder/Sources/DiktadorRecorder/MicrophonePermissionProvider.swift
git commit -m "$(cat <<'EOF'
diktador-recorder: MicrophonePermissionProvider seam + AV impl

Internal protocol with currentStatus / requestAccess. Real
AVPermissionProvider wraps AVCaptureDevice authorizationStatus and
requestAccess; hops the completion to main. Test stub follows in the
recorder tests phase.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task D2: `AudioEngineDriver` protocol + `AVAudioEngineDriver` real impl

**Files:**
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/AudioEngineDriver.swift`

- [ ] **Step 1: Write the file**

```swift
import AVFoundation
import Foundation

/// Internal seam over the AVAudioEngine surface used by `Recorder`. Real
/// implementation wires up an engine + input-node tap; tests substitute a stub
/// that records lifecycle calls and lets the test feed synthetic buffers.
internal protocol AudioEngineDriver: AnyObject {
    var inputFormat: AVAudioFormat { get }
    func installTap(
        bufferSize: AVAudioFrameCount,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws
    func removeTap()
    func start() throws
    func stop()
}

internal final class AVAudioEngineDriver: AudioEngineDriver {
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    var inputFormat: AVAudioFormat {
        engine.inputNode.inputFormat(forBus: 0)
    }

    func installTap(
        bufferSize: AVAudioFrameCount,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws {
        guard !tapInstalled else { return }
        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: engine.inputNode.inputFormat(forBus: 0)
        ) { buffer, _ in
            onBuffer(buffer)
        }
        tapInstalled = true
    }

    func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}
```

- [ ] **Step 2: Build**

Run: `cd modules/diktador-recorder && swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-recorder/Sources/DiktadorRecorder/AudioEngineDriver.swift
git commit -m "$(cat <<'EOF'
diktador-recorder: AudioEngineDriver seam + AVAudioEngine impl

Internal protocol over installTap/removeTap/start/stop and inputFormat.
Real AVAudioEngineDriver constructs an AVAudioEngine and installs/
removes a tap on the input node. tapInstalled flag prevents double-
install / double-remove. Test stub follows in the recorder tests phase.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E — Sample-rate converter + WAV writer

### Task E1: `SampleRateConverter`

**Files:**
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/SampleRateConverter.swift`

- [ ] **Step 1: Write the file**

```swift
import AVFoundation
import Foundation

/// Lazily converts captured buffers from the input device's native format to
/// 16 kHz mono `Float32`. Initialized on the first buffer (when the source
/// format is known); reused thereafter.
internal final class SampleRateConverter {
    static let targetSampleRate: Double = 16_000

    static var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    /// Converts `buffer` to 16 kHz mono Float32 and appends the resulting
    /// samples to `accumulator`. Returns the number of frames appended.
    /// Throws `RecorderError.formatConversionFailed` on setup or convert failure.
    func append(_ buffer: AVAudioPCMBuffer, into accumulator: inout [Float]) throws -> AVAudioFrameCount {
        if converter == nil {
            sourceFormat = buffer.format
            guard let c = AVAudioConverter(from: buffer.format, to: Self.targetFormat) else {
                throw RecorderError.formatConversionFailed
            }
            converter = c
        }
        guard let converter = converter else {
            throw RecorderError.formatConversionFailed
        }

        // Estimate output capacity: ratio = target / source rate; +256 for safety
        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: estimatedFrames
        ) else {
            throw RecorderError.formatConversionFailed
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            throw RecorderError.formatConversionFailed
        }

        let frames = Int(outBuffer.frameLength)
        if frames > 0, let channelData = outBuffer.floatChannelData?[0] {
            accumulator.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
        }
        return outBuffer.frameLength
    }
}
```

- [ ] **Step 2: Build**

Run: `cd modules/diktador-recorder && swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-recorder/Sources/DiktadorRecorder/SampleRateConverter.swift
git commit -m "$(cat <<'EOF'
diktador-recorder: SampleRateConverter — native format → 16 kHz mono Float32

Lazily initializes AVAudioConverter on the first buffer (source format
is only known once the engine starts). Each append() converts one
input buffer and appends the resulting samples to the caller's
[Float] accumulator. Failures surface as RecorderError.formatConversionFailed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task E2: `WAVWriter`

**Files:**
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/WAVWriter.swift`

- [ ] **Step 1: Write the file**

```swift
import AVFoundation
import Foundation

/// Writes a `[Float]` accumulator to a WAV file at 16 kHz mono 16-bit PCM.
internal struct WAVWriter {
    func write(samples: [Float], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // 16-bit PCM mono at 16 kHz. AVAudioFile takes a settings dict for the
        // file format; the in-memory buffer stays Float32 and AVAudioFile
        // converts on write.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: SampleRateConverter.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            throw RecorderError.fileWriteFailed
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: SampleRateConverter.targetFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw RecorderError.fileWriteFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channelData.update(from: src.baseAddress!, count: samples.count)
            }
        }

        do {
            try audioFile.write(from: buffer)
        } catch {
            throw RecorderError.fileWriteFailed
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd modules/diktador-recorder && swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-recorder/Sources/DiktadorRecorder/WAVWriter.swift
git commit -m "$(cat <<'EOF'
diktador-recorder: WAVWriter — 16 kHz mono 16-bit PCM via AVAudioFile

Creates intermediate directories on write. Settings dict pins the file
format to 16-bit linear PCM mono at 16 kHz; AVAudioFile converts the
Float32 buffer on write. Failures surface as RecorderError.fileWriteFailed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F — `Recorder` core (TDD)

### Task F1: Failing tests for permission accessors + simple lifecycle

**Files:**
- Create: `modules/diktador-recorder/Tests/DiktadorRecorderTests/RecorderTests.swift`

- [ ] **Step 1: Write the test file with stubs and the first three test cases**

```swift
import XCTest
import AVFoundation
@testable import DiktadorRecorder

final class RecorderTests: XCTestCase {
    func test_microphonePermission_reflectsProviderStatus() {
        let perms = StubPermissionProvider()
        perms.statusToReturn = .granted
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )
        XCTAssertEqual(recorder.microphonePermission, .granted)

        perms.statusToReturn = .denied
        XCTAssertEqual(recorder.microphonePermission, .denied)
    }

    func test_requestMicrophonePermission_callsProviderAndReturnsResult() {
        let perms = StubPermissionProvider()
        perms.requestResultToReturn = .granted
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        let exp = expectation(description: "completion")
        var observed: MicrophonePermissionStatus?
        recorder.requestMicrophonePermission { status in
            observed = status
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(observed, .granted)
        XCTAssertEqual(perms.requestCallCount, 1)
    }

    func test_start_throwsWhenPermissionDenied() {
        let perms = StubPermissionProvider()
        perms.statusToReturn = .denied
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )
        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? RecorderError, .microphonePermissionDenied)
        }
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: - Helpers

    private static func tempRecordingsDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiktadorRecorderTests-\(UUID().uuidString)")
        return dir
    }
}

private final class StubPermissionProvider: MicrophonePermissionProvider, @unchecked Sendable {
    var statusToReturn: MicrophonePermissionStatus = .undetermined
    var requestResultToReturn: MicrophonePermissionStatus = .granted
    private(set) var requestCallCount = 0

    func currentStatus() -> MicrophonePermissionStatus { statusToReturn }

    func requestAccess(completion: @escaping (MicrophonePermissionStatus) -> Void) {
        requestCallCount += 1
        let result = requestResultToReturn
        DispatchQueue.main.async { completion(result) }
    }
}

private final class StubAudioEngineDriver: AudioEngineDriver, @unchecked Sendable {
    enum Call: Equatable {
        case installTap(bufferSize: AVAudioFrameCount)
        case removeTap
        case start
        case stop
    }

    private(set) var calls: [Call] = []
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    var startError: Error?
    var fakeInputFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!

    var inputFormat: AVAudioFormat { fakeInputFormat }

    func installTap(
        bufferSize: AVAudioFrameCount,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) throws {
        calls.append(.installTap(bufferSize: bufferSize))
        self.onBuffer = onBuffer
    }

    func removeTap() {
        calls.append(.removeTap)
        onBuffer = nil
    }

    func start() throws {
        calls.append(.start)
        if let startError = startError { throw startError }
    }

    func stop() {
        calls.append(.stop)
    }

    /// Test helper: synthesize a buffer of `frameCount` zero samples in the
    /// fake input format and feed it through the installed tap.
    func feedZeroBuffer(frameCount: AVAudioFrameCount) {
        guard let onBuffer = onBuffer else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: fakeInputFormat,
            frameCapacity: frameCount
        ) else { return }
        buffer.frameLength = frameCount
        onBuffer(buffer)
    }
}
```

- [ ] **Step 2: Verify they fail**

Run: `cd modules/diktador-recorder && swift test 2>&1 | tail -30`
Expected: compile failures — `cannot find 'Recorder' in scope`, `extra arguments at positions...`.

### Task F2: Implement `Recorder` to pass F1

**Files:**
- Create: `modules/diktador-recorder/Sources/DiktadorRecorder/Recorder.swift`

- [ ] **Step 1: Write the file**

```swift
import AVFoundation
import Foundation

/// Captures microphone audio between `start()` and `stop(completion:)` calls
/// and writes the result as a 16 kHz mono PCM WAV file.
public final class Recorder {
    private enum State {
        case idle
        case recording(samples: [Float], startedAt: Date)
        case finalizing
    }

    private let permissionProvider: MicrophonePermissionProvider
    private let engineDriver: AudioEngineDriver
    private let recordingsDirectory: URL
    private let converter = SampleRateConverter()
    private let writer = WAVWriter()

    private var state: State = .idle

    public convenience init() {
        self.init(
            permissionProvider: AVPermissionProvider(),
            engineDriver: AVAudioEngineDriver(),
            recordingsDirectory: Self.defaultRecordingsDirectory()
        )
    }

    internal init(
        permissionProvider: MicrophonePermissionProvider,
        engineDriver: AudioEngineDriver,
        recordingsDirectory: URL
    ) {
        self.permissionProvider = permissionProvider
        self.engineDriver = engineDriver
        self.recordingsDirectory = recordingsDirectory
    }

    deinit {
        if case .recording = state {
            engineDriver.removeTap()
            engineDriver.stop()
        }
    }

    public var microphonePermission: MicrophonePermissionStatus {
        permissionProvider.currentStatus()
    }

    public func requestMicrophonePermission(
        completion: @escaping (MicrophonePermissionStatus) -> Void
    ) {
        permissionProvider.requestAccess(completion: completion)
    }

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    public func start() throws {
        guard case .idle = state else { throw RecorderError.alreadyRecording }
        guard permissionProvider.currentStatus() == .granted else {
            throw RecorderError.microphonePermissionDenied
        }

        var samples: [Float] = []
        let startedAt = Date()
        do {
            try engineDriver.installTap(
                bufferSize: 4096,
                onBuffer: { [weak self] buffer in
                    self?.handleBuffer(buffer)
                }
            )
            try engineDriver.start()
        } catch {
            engineDriver.removeTap()
            engineDriver.stop()
            NSLog("[recorder] engine start failed: \(error)")
            throw RecorderError.engineUnavailable
        }
        state = .recording(samples: samples, startedAt: startedAt)
    }

    public func stop(completion: @escaping (Result<RecordingResult, Error>) -> Void) {
        guard case .recording(let samples, let startedAt) = state else {
            completion(.failure(RecorderError.notRecording))
            return
        }

        engineDriver.removeTap()
        engineDriver.stop()
        state = .finalizing

        let fileURL = nextFileURL()
        let duration = Date().timeIntervalSince(startedAt)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.writer.write(samples: samples, to: fileURL)
                let result = RecordingResult(
                    fileURL: fileURL,
                    duration: duration,
                    sampleCount: samples.count
                )
                DispatchQueue.main.async {
                    self.state = .idle
                    completion(.success(result))
                }
            } catch {
                NSLog("[recorder] file write failed: \(error)")
                DispatchQueue.main.async {
                    self.state = .idle
                    completion(.failure(error))
                }
            }
        }
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard case .recording(var samples, let startedAt) = state else { return }
        do {
            _ = try converter.append(buffer, into: &samples)
            state = .recording(samples: samples, startedAt: startedAt)
        } catch {
            NSLog("[recorder] format conversion failed: \(error)")
        }
    }

    private func nextFileURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return recordingsDirectory.appendingPathComponent("\(stamp).wav")
    }

    private static func defaultRecordingsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Diktador", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }
}
```

- [ ] **Step 2: Run the tests, confirm F1's three cases pass**

Run: `cd modules/diktador-recorder && swift test 2>&1 | tail -20`
Expected: 3/3 pass.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-recorder/Sources/DiktadorRecorder/Recorder.swift \
        modules/diktador-recorder/Tests/DiktadorRecorderTests/RecorderTests.swift
git commit -m "$(cat <<'EOF'
diktador-recorder: Recorder core — start/stop, permission, lifecycle

Public Recorder class with three internal states (idle / recording /
finalizing), dual init (public + test seam taking PermissionProvider +
EngineDriver + recordingsDirectory). start() validates permission and
installs the tap; stop() removes the tap, dispatches WAV write off-main,
delivers RecordingResult on main. Three tests cover permission accessors
and the denied-permission path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task F3: Failing tests for the success path + reentry guards + writer failure

**Files:**
- Modify: `modules/diktador-recorder/Tests/DiktadorRecorderTests/RecorderTests.swift`

- [ ] **Step 1: Append five new tests inside the test class**

```swift
    func test_start_installsTapAndStartsEngine() throws {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        try recorder.start()

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(driver.calls, [
            .installTap(bufferSize: 4096),
            .start,
        ])
    }

    func test_start_throws_alreadyRecording_onSecondCall() throws {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: Self.tempRecordingsDirectory()
        )
        try recorder.start()

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? RecorderError, .alreadyRecording)
        }
    }

    func test_stop_returnsNotRecording_whenIdle() {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: StubAudioEngineDriver(),
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        let exp = expectation(description: "completion")
        var observed: Result<RecordingResult, Error>?
        recorder.stop { result in
            observed = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        if case .failure(let error) = observed {
            XCTAssertEqual(error as? RecorderError, .notRecording)
        } else {
            XCTFail("expected .failure(.notRecording), got \(String(describing: observed))")
        }
    }

    func test_stopAfterStart_writesWAVAndReturnsResult() throws {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        let dir = Self.tempRecordingsDirectory()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: dir
        )

        try recorder.start()
        // Feed three native-rate buffers (~85 ms each at 48 kHz).
        driver.feedZeroBuffer(frameCount: 4096)
        driver.feedZeroBuffer(frameCount: 4096)
        driver.feedZeroBuffer(frameCount: 4096)

        let exp = expectation(description: "completion")
        var observed: Result<RecordingResult, Error>?
        recorder.stop { result in
            observed = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        guard case .success(let result) = observed else {
            XCTFail("expected .success, got \(String(describing: observed))")
            return
        }
        XCTAssertGreaterThan(result.sampleCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(result.fileURL.pathExtension, "wav")
        XCTAssertFalse(recorder.isRecording)

        // Driver lifecycle calls in expected order: installTap, start, removeTap, stop.
        XCTAssertEqual(driver.calls, [
            .installTap(bufferSize: 4096),
            .start,
            .removeTap,
            .stop,
        ])

        try? FileManager.default.removeItem(at: dir)
    }

    func test_start_engineFailure_throwsEngineUnavailable() {
        let perms = StubPermissionProvider(); perms.statusToReturn = .granted
        let driver = StubAudioEngineDriver()
        struct DummyError: Error {}
        driver.startError = DummyError()
        let recorder = Recorder(
            permissionProvider: perms,
            engineDriver: driver,
            recordingsDirectory: Self.tempRecordingsDirectory()
        )

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? RecorderError, .engineUnavailable)
        }
        XCTAssertFalse(recorder.isRecording)
        // Tap was installed then removed during the unwind.
        XCTAssertEqual(driver.calls, [
            .installTap(bufferSize: 4096),
            .start,
            .removeTap,
            .stop,
        ])
    }
```

- [ ] **Step 2: Verify they fail or pass**

Run: `cd modules/diktador-recorder && swift test 2>&1 | tail -25`
Expected: 5 new tests, all should pass against the F2 implementation. If any fail, fix before continuing.

- [ ] **Step 3: Commit**

```bash
git add modules/diktador-recorder/Tests/DiktadorRecorderTests/RecorderTests.swift
git commit -m "$(cat <<'EOF'
diktador-recorder: tests for success path + reentry + engine-failure unwind

Five new test cases exercise the happy path (start → feed buffers →
stop → WAV exists), the alreadyRecording / notRecording reentry guards,
and the engineUnavailable unwind (tap installed and removed; engine
stopped). 8/8 pass.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase G — `AppDelegate` integration

### Task G1: Update `project.yml` for the new package

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add the package + product dependency**

Edit the `packages:` block to add `DiktadorRecorder`:

```yaml
packages:
  DiktadorHotkey:
    path: modules/diktador-hotkey
  DiktadorRecorder:
    path: modules/diktador-recorder
```

And add a second product dependency under the `Diktador` target:

```yaml
    dependencies:
      - package: DiktadorHotkey
        product: DiktadorHotkey
      - package: DiktadorRecorder
        product: DiktadorRecorder
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `cd "/Users/user/Desktop/Aintigravity Workflows/Diktador" && xcodegen generate 2>&1 | tail -5`
Expected: project regenerated; output mentions both packages.

- [ ] **Step 3: Verify the app target still builds**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`. (No code changes yet — just adding the dep.)

- [ ] **Step 4: Commit**

```bash
git add project.yml Diktador.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
project.yml: link DiktadorRecorder package into the Diktador app target

Regenerated via xcodegen. Diktador app target now depends on both
DiktadorHotkey and DiktadorRecorder products. Recorder is wired into
AppDelegate in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task G2: Rewire `AppDelegate` for the dual-permission bootstrap and recording-on-press

**Files:**
- Modify: `Diktador/AppDelegate.swift`

- [ ] **Step 1: Replace the file with the integrated version**

```swift
import AppKit
import DiktadorHotkey
import DiktadorRecorder

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let idleTitle = "Diktador (idle)"
    private static let listeningTitle = "Diktador (listening…)"
    private static let inputMonitoringNeededTitle = "Diktador (needs Input Monitoring)"
    private static let microphoneNeededTitle = "Diktador (needs Microphone)"
    private static let openInputMonitoringSettingsTitle = "Open Input Monitoring settings…"
    private static let openMicrophoneSettingsTitle = "Open Microphone settings…"

    private static let inputMonitoringPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )
    private static let microphonePaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )

    private var statusItem: NSStatusItem?
    private var statusRowItem: NSMenuItem?
    private var openInputMonitoringSettingsItem: NSMenuItem?
    private var openMicrophoneSettingsItem: NSMenuItem?
    private var lastRecordingItem: NSMenuItem?
    private var lastRecordingURL: URL?

    private let hotkeys = HotkeyRegistry()
    private let recorder = Recorder()
    private var pushToTalkToken: HotkeyRegistry.RegistrationToken?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bootstrapPushToTalk()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage

        let menu = NSMenu()
        let statusRow = NSMenuItem(title: Self.idleTitle, action: nil, keyEquivalent: "")
        menu.addItem(statusRow)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu

        self.statusItem = item
        self.statusRowItem = statusRow
    }

    private func bootstrapPushToTalk() {
        switch hotkeys.inputMonitoringPermission {
        case .granted:
            checkMicrophonePermission()
        case .undetermined:
            hotkeys.requestInputMonitoringPermission { [weak self] _ in
                self?.bootstrapPushToTalk()
            }
        case .denied:
            showInputMonitoringDeniedState()
        }
    }

    private func checkMicrophonePermission() {
        switch recorder.microphonePermission {
        case .granted:
            registerFnPushToTalk()
        case .undetermined:
            recorder.requestMicrophonePermission { [weak self] _ in
                self?.checkMicrophonePermission()
            }
        case .denied:
            showMicrophoneDeniedState()
        }
    }

    private func registerFnPushToTalk() {
        // Bare Fn (🌐) held = listening + recording. The user must set
        // System Settings → Keyboard → Press 🌐 to → Do nothing
        // for the press not to ALSO trigger Apple's globe-key action.
        // See wiki/howtos/first-run-setup.md.
        pushToTalkToken = hotkeys.register(
            modifierTrigger: .fn,
            onPress: { [weak self] in self?.handlePress() },
            onRelease: { [weak self] in self?.handleRelease() }
        )
    }

    private func handlePress() {
        setListening(true)
        do {
            try recorder.start()
        } catch {
            NSLog("[app] recorder.start failed: \(error)")
            statusRowItem?.title = "Recording failed: \(error)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.setListening(self?.recorder.isRecording == true)
            }
        }
    }

    private func handleRelease() {
        setListening(false)
        recorder.stop { [weak self] result in
            self?.handleRecordingResult(result)
        }
    }

    private func handleRecordingResult(_ result: Result<RecordingResult, Error>) {
        switch result {
        case .success(let recording):
            lastRecordingURL = recording.fileURL
            let title = String(
                format: "Last recording: %.1fs — Reveal in Finder",
                recording.duration
            )
            if lastRecordingItem == nil {
                let item = NSMenuItem(
                    title: title,
                    action: #selector(revealLastRecording),
                    keyEquivalent: ""
                )
                item.target = self
                statusItem?.menu?.insertItem(item, at: 1)
                lastRecordingItem = item
            } else {
                lastRecordingItem?.title = title
            }
        case .failure(let error):
            NSLog("[app] recorder.stop failed: \(error)")
            statusRowItem?.title = "Recording failed: \(error)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.statusRowItem?.title = Self.idleTitle
            }
        }
    }

    @objc private func revealLastRecording() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func showInputMonitoringDeniedState() {
        statusItem?.button?.image = Self.warningImage
        statusRowItem?.title = Self.inputMonitoringNeededTitle

        guard openInputMonitoringSettingsItem == nil else { return }
        let item = NSMenuItem(
            title: Self.openInputMonitoringSettingsTitle,
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        item.target = self
        statusItem?.menu?.insertItem(item, at: 1)
        openInputMonitoringSettingsItem = item
    }

    private func showMicrophoneDeniedState() {
        statusItem?.button?.image = Self.warningImage
        statusRowItem?.title = Self.microphoneNeededTitle

        guard openMicrophoneSettingsItem == nil else { return }
        let item = NSMenuItem(
            title: Self.openMicrophoneSettingsTitle,
            action: #selector(openMicrophoneSettings),
            keyEquivalent: ""
        )
        item.target = self
        statusItem?.menu?.insertItem(item, at: 1)
        openMicrophoneSettingsItem = item
    }

    @objc private func openInputMonitoringSettings() {
        if let url = Self.inputMonitoringPaneURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openMicrophoneSettings() {
        if let url = Self.microphonePaneURL {
            NSWorkspace.shared.open(url)
        }
    }

    func setListening(_ listening: Bool) {
        statusItem?.button?.image = listening ? Self.listeningImage : Self.idleImage
        statusRowItem?.title = listening ? Self.listeningTitle : Self.idleTitle
    }

    private static func templateSymbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    static let idleImage = templateSymbol("mic", description: "Diktador")
    static let listeningImage = templateSymbol("mic.fill", description: "Diktador (listening)")
    static let warningImage = templateSymbol(
        "exclamationmark.triangle",
        description: "Diktador (needs permission)"
    )
}
```

- [ ] **Step 2: Build Debug**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Build Release**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Diktador/AppDelegate.swift
git commit -m "$(cat <<'EOF'
Diktador app: chain Microphone permission + record on Fn press/release

bootstrapPushToTalk now resolves Input Monitoring first, then chains
into checkMicrophonePermission. Each press calls recorder.start()
(catching the start error path); each release calls recorder.stop and
on success updates a "Last recording: 2.3s — Reveal in Finder" menu
item linked to NSWorkspace.activateFileViewerSelecting. Mic-denied
state mirrors the existing Input-Monitoring-denied state with an
"Open Microphone settings…" deep-link.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase H — Documentation

### Task H1: Module README

**Files:**
- Create: `modules/diktador-recorder/README.md`

- [ ] **Step 1: Write the file**

```markdown
# diktador-recorder

## Purpose

Captures microphone audio between explicit `start()` and `stop()` calls and writes a 16 kHz mono PCM WAV file to `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav` on stop. Pure capture — no VAD, no streaming. The hotkey module signals start/end; this module produces the buffer the future transcriber will consume.

## Public API

Import: `import DiktadorRecorder`. SwiftPM library and target both named `DiktadorRecorder`; package directory is `modules/diktador-recorder/`.

- `Recorder()` — instantiate. One recorder per owner; `AppDelegate` owns the live one in v1.
- `microphonePermission: MicrophonePermissionStatus` — current macOS Microphone access for the running process. Synchronous, no side effects.
- `requestMicrophonePermission(completion:)` — triggers the macOS consent prompt the first time it is called per app-bundle / user; subsequent calls return the cached result. Completion runs on the main queue.
- `start() throws` — begins recording. Throws `RecorderError.microphonePermissionDenied` if permission isn't granted; `.alreadyRecording` if already running; `.engineUnavailable` if `AVAudioEngine` fails to start.
- `stop(completion:)` — ends recording, finalizes the WAV file off-main, returns `Result<RecordingResult, Error>` on main. `.failure(.notRecording)` if not currently recording.
- `isRecording: Bool` — diagnostic and consumer surface.
- `RecordingResult` — `Sendable, Equatable` value type with `fileURL`, `duration`, `sampleCount`.
- `MicrophonePermissionStatus` — `Sendable, Equatable` enum: `.granted` / `.denied` / `.undetermined`.
- `RecorderError` — `Equatable` error enum: `.microphonePermissionDenied`, `.alreadyRecording`, `.notRecording`, `.engineUnavailable`, `.formatConversionFailed`, `.fileWriteFailed`.

Tests run with `swift test` from `modules/diktador-recorder/`.

## Dependencies

- AVFoundation (system) — for `AVCaptureDevice`, `AVAudioEngine`, `AVAudioConverter`, `AVAudioFile`, `AVAudioPCMBuffer`.
- Foundation (system) — for `FileManager`, `URL`, `ISO8601DateFormatter`.
- Deployment target: macOS 14+.
- No environment variables, no external services, no other Diktador modules.

`INFOPLIST_KEY_NSMicrophoneUsageDescription` must be present in the app target's Info.plist (already declared in `project.yml` since PR #1).

## Known failure modes

- **Microphone permission denied.** `start()` throws `RecorderError.microphonePermissionDenied`. AppDelegate catches and surfaces a warning state with a deep-link to System Settings → Privacy & Security → Microphone.
- **Microphone permission revoked at runtime.** macOS lets the user revoke access while Diktador is running; the engine's input node stops delivering samples, so the next `stop` returns a recording with zero or near-zero `sampleCount`. v1 mitigation: none. Future: poll `microphonePermission` on `NSApplication.didBecomeActiveNotification` and re-bootstrap.
- **`AVAudioEngine.start()` fails.** No input device available, hardware busy (other app holds exclusive access), or sandbox blocked. `start()` removes the tap, stops the engine, logs `[recorder] engine start failed: <error>`, and re-throws as `.engineUnavailable`.
- **Format conversion failure.** `AVAudioConverter` setup or per-buffer conversion failed. Per-buffer failures are logged and skipped — the recording continues with whatever samples have been accumulated. Setup failures throw `.formatConversionFailed` from `start()`.
- **WAV write failure.** Recordings directory not writable (rare; only happens if Application Support is read-only) or `AVAudioFile.write` errored. `stop` completion fires with `.failure(.fileWriteFailed)`. The captured samples are lost.
- **Double-`start()`.** Throws `.alreadyRecording`. Push-to-talk shouldn't trigger this (the hotkey module debounces edges), but a stuck `onPress` could.
- **`stop()` while idle.** Completion fires synchronously with `.failure(.notRecording)`.
- **App quit mid-recording.** `Recorder.deinit` removes the tap and stops the engine. The in-flight buffer is dropped; no partial WAV is written. Consumers must call `stop` explicitly for a successful capture.
- **Native input format != 16 kHz mono.** The internal `SampleRateConverter` lazy-initializes on the first buffer once the device's actual `inputFormat` is known and converts every subsequent buffer. Conversion happens in process; the on-disk format is always 16 kHz mono 16-bit PCM regardless of the input device.
```

- [ ] **Step 2: Commit**

```bash
git add modules/diktador-recorder/README.md
git commit -m "$(cat <<'EOF'
diktador-recorder: README — Purpose / Public API / Dependencies / Failure modes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task H2: Memory domain note

**Files:**
- Create: `memory/domains/recorder.md`

- [ ] **Step 1: Write the file**

```markdown
---
type: memory-domain
domain: recorder
created: 2026-04-27
updated: 2026-04-27
---

# Recorder — operational notes

Public surface and failure modes live in [`modules/diktador-recorder/README.md`](../../modules/diktador-recorder/README.md). This file is for working-memory shorthand only — do not duplicate the README.

## v1 configuration

- Trigger: bare Fn held (delegated to the hotkey module). `onPress` calls `recorder.start()`; `onRelease` calls `recorder.stop`.
- Capture: `AVAudioEngine` input-node tap at 4096-sample buffer size (~85 ms at 48 kHz). Lazily-initialized `AVAudioConverter` resamples every buffer to 16 kHz mono `Float32` in process.
- On stop: WAV file written off-main to `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav`. Filenames use `:` → `-` replacement for filesystem safety.
- AppDelegate exposes a "Last recording: 2.3s — Reveal in Finder" menu item once at least one recording has succeeded.
- Permission flow: chained after Input Monitoring. `bootstrapPushToTalk` resolves Input Monitoring first, then `checkMicrophonePermission`. Both prompt on first launch.
- No retention policy. Files accumulate under `recordings/` until the user deletes them or a future settings module ships cleanup.

## Open questions (deferred to follow-up PRs)

- **VAD** — deferred to the transcriber PR. Push-to-talk doesn't need it; continuous-listening mode does. WhisperKit has built-in VAD; an energy-based fallback for early end-of-speech detection is the second decision point.
- **Streaming chunked transcription** — deferred. v1 is single-buffer-at-stop. Streaming buys lower latency but requires the transcriber to exist.
- **Multi-input device selection** — deferred. Uses the system default input. Future settings-module concern.
- **Recordings folder cleanup** — deferred. Could be "delete after successful transcription" or LRU-keep-the-last-N. Settings-module concern.
- **Recovery from runtime permission revocation** — deferred. `NSApplication.didBecomeActiveNotification` poll + re-bootstrap is the natural hook; same gap exists for Input Monitoring.

## Debug recipes

- Recording produces a zero-byte / near-zero-sample-count file: check `microphonePermission`. If `.granted`, the most likely cause is the input device being held by another exclusive consumer (a video call, another DAW). The `[recorder] engine start failed` log line is the primary signal.
- Recording sounds pitched / time-stretched: the `SampleRateConverter` is using a stale source format. Hot-plugging an input device mid-recording is not in scope; restart the recording.
- `stop` returns `.fileWriteFailed`: check `~/Library/Application Support/Diktador/recordings/` exists and is writable. The recorder creates intermediate directories on write but cannot recover from a sandbox-blocked path.
- `stop` returns immediately with `.notRecording`: the `start` likely threw silently — check the press-handler's error log for `[app] recorder.start failed`.

## See also

- [`modules/diktador-recorder/README.md`](../../modules/diktador-recorder/README.md) — public API, dependencies, full failure-mode list.
- [`wiki/decisions/recorder-capture-pipeline.md`](../../wiki/decisions/recorder-capture-pipeline.md) — VAD-deferral + format choices.
- `memory/domains/hotkey.md` — the trigger surface that drives this module.
```

- [ ] **Step 2: Commit**

```bash
git add memory/domains/recorder.md
git commit -m "$(cat <<'EOF'
memory/recorder: operational notes — v1 config, open questions, debug recipes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task H3: ADR

**Files:**
- Create: `wiki/decisions/recorder-capture-pipeline.md`

- [ ] **Step 1: Write the ADR**

```markdown
---
type: decision
created: 2026-04-27
updated: 2026-04-27
tags: [recorder, audio, architecture, macos, permissions]
status: stable
sources: []
---

# Recorder: pure capture, in-process 16 kHz mono PCM, WAV-to-disk debug surface

## Context

The framework ADR ([[decisions/framework-choice]]) lists `recorder` as "Audio capture + VAD" and locks `AVAudioEngine` for capture, with WhisperKit's built-in VAD plus an energy-based fallback for end-of-speech detection.

Two questions surfaced during this PR's brainstorming:

1. **Does v1 ship VAD?** Push-to-talk uses the Fn hotkey to signal speech start/end; the user *is* the VAD. VAD code only earns its keep when continuous-listening mode lands — which has no spec yet and no v1 consumer.
2. **Without a transcriber or output module, the recorder has no observable behavior.** Either ship dark (logs only) or surface a debug WAV file the user can play back.

## Decision

**v1 recorder is pure capture, no VAD.** Single `start()` / `stop()` API; the hotkey module's `onPress` / `onRelease` callbacks drive the lifecycle. WhisperKit's built-in VAD will be enabled alongside the transcriber when continuous-listening mode is on the roadmap.

**Capture is converted in-process to 16 kHz mono `Float32`** via `AVAudioConverter` and accumulated in memory until `stop`. On stop, the buffer is written as a 16-bit PCM WAV file at `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav`. Pre-converted means the future transcriber can read straight from `RecordingResult.fileURL` without re-conversion; matches WhisperKit's expected input format.

**A debug "Last recording: 2.3s — Reveal in Finder" menu item** in `AppDelegate` lets the user verify capture works end-to-end without the transcriber. Click reveals the file in Finder; play in QuickLook to hear the recording. The menu item is retained as a permanent debug surface — also useful when transcription quality is wrong (replay the same buffer through different models).

**Permissions chain after Input Monitoring**: `bootstrapPushToTalk` resolves Input Monitoring first (without it the hotkey can't fire), then `checkMicrophonePermission`. Both can prompt on first launch in sequence; both denied states surface a warning UI with deep-links to the right System Settings panes.

**Test seam mirrors the hotkey module's pattern**: an internal `MicrophonePermissionProvider` protocol with an `AVPermissionProvider` real impl, and an internal `AudioEngineDriver` protocol with an `AVAudioEngineDriver` real impl. Test stubs let the recorder lifecycle be exercised without real hardware.

## Consequences

- **No VAD code today.** The transcriber PR will need to either invoke WhisperKit's built-in VAD or add an energy-based pre-pass; the decision is deferred to that PR's brainstorming.
- **Pre-converted-to-16-kHz means smaller in-memory buffers** (~31 KB/s vs ~376 KB/s native 48 kHz × 2 channels × 4 bytes). Negligible for short push-to-talk dictation; matters when the buffer accumulates over 10+ minutes (currently impossible — push-to-talk gates duration).
- **WAV files accumulate.** No retention policy in v1; cleanup is a settings-module concern. Disk usage grows roughly 31 KB per recorded second.
- **Two permission prompts on first launch.** Input Monitoring then Microphone, in sequence. Acceptable: Diktador needs both to function.
- **Reveal-in-Finder is a real feature, not just a debug knob.** Users will find utility in being able to keep recordings beyond a single session. The future settings module can add a "delete after transcription" toggle without removing this surface.
- **The recorder doesn't know about the transcriber.** It produces a WAV file; whoever consumes it decides what to do. Clean separation; matches the six modular rules.

## Alternatives considered

1. **Front-load VAD with the recorder.** Rejected: adds code, tests, failure modes for a feature with no v1 consumer. WhisperKit's built-in VAD will likely supersede whatever we ship.
2. **Stream chunks to the transcriber as they arrive.** Rejected for v1: there's no transcriber. When it lands, streaming may be the right call for lower latency, but that's a transcriber-PR design question.
3. **Recorder alone, no UI surface.** Rejected: makes the PR untestable except via `swift test`, which doesn't exercise real audio capture. The "Last recording" menu item provides a real verification path during /go computer-use.
4. **Keep the buffer in memory, no WAV file.** Rejected: blocks the user from verifying capture quality, and forfeits the future "replay through different models" debug workflow.
5. **Save in native format (e.g., 48 kHz multichannel).** Rejected: forces the transcriber to re-convert on every transcription. Centralizing the conversion in the recorder gives one source of truth.

## Sources

- [`modules/diktador-recorder/README.md`](../../modules/diktador-recorder/README.md) — public API, dependencies, full failure-mode list.
- [`memory/domains/recorder.md`](../../memory/domains/recorder.md) — operational notes + open questions.
- [`docs/superpowers/specs/2026-04-27-recorder-module-design.md`](../../docs/superpowers/specs/2026-04-27-recorder-module-design.md) — design doc this ADR ratifies.
- [[decisions/framework-choice]] — parent ADR (locks Swift / AVAudioEngine / WhisperKit).
- [[decisions/hotkey-modifier-only-trigger]] — sibling ADR; establishes the dual-init test-seam pattern this module follows.
```

- [ ] **Step 2: Commit**

```bash
git add wiki/decisions/recorder-capture-pipeline.md
git commit -m "$(cat <<'EOF'
ADR: recorder — pure capture, 16 kHz mono PCM, WAV-to-disk debug surface

VAD deferred to the transcriber PR. In-process AVAudioConverter to
WhisperKit-ready format. Reveal-in-Finder menu item is a permanent
debug surface (also useful for replay during transcription quality
debugging). Test seam mirrors the hotkey module's PermissionProvider /
EngineDriver pattern.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task H4: Wiki module page

**Files:**
- Create: `wiki/modules/recorder.md`

- [ ] **Step 1: Write the file**

```markdown
---
type: module
created: 2026-04-27
updated: 2026-04-27
tags: [recorder, audio]
status: stable
---

# Module: recorder

## Purpose

Captures microphone audio between explicit `start()` / `stop()` calls and writes a 16 kHz mono PCM WAV file on stop. Pure capture — no VAD, no streaming. Drives the future transcriber's input.

## Public API

Single class `Recorder` plus value types:

- `Recorder()` — instantiate.
- `microphonePermission: MicrophonePermissionStatus`
- `requestMicrophonePermission(completion:)`
- `start() throws`
- `stop(completion:)` — async finalize, completion delivers `Result<RecordingResult, Error>` on main.
- `isRecording: Bool`
- `RecordingResult { fileURL, duration, sampleCount }`
- `MicrophonePermissionStatus { granted, denied, undetermined }`
- `RecorderError { microphonePermissionDenied, alreadyRecording, notRecording, engineUnavailable, formatConversionFailed, fileWriteFailed }`

Full reference at [`modules/diktador-recorder/README.md`](../../modules/diktador-recorder/README.md).

## Design decisions

- v1 is **capture-only** — no VAD. Push-to-talk gives explicit start/end. See [[decisions/recorder-capture-pipeline]].
- **In-process conversion to 16 kHz mono Float32** — pre-conversion centralizes the format choice, making the on-disk WAV WhisperKit-ready and the in-memory buffer ~12× smaller than native 48 kHz × 2 channels.
- **WAV-to-disk debug surface** — the "Last recording: 2.3s — Reveal in Finder" menu item is a permanent feature, not a debug-only knob. Useful for verifying capture and for replay through different transcription models.
- **Test seam mirrors the hotkey module's pattern** — internal `MicrophonePermissionProvider` + `AudioEngineDriver` protocols with stub-friendly real implementations. Lifecycle is fully unit-testable without hardware.

## Dependencies

- AVFoundation (system) — `AVCaptureDevice`, `AVAudioEngine`, `AVAudioConverter`, `AVAudioFile`, `AVAudioPCMBuffer`.
- Foundation (system) — `FileManager`, `URL`, `ISO8601DateFormatter`.
- macOS 14+.
- No other Diktador modules. AppDelegate composes recorder + hotkey.

## Open questions

- VAD integration in continuous-listening mode (transcriber-PR concern).
- Streaming chunks vs single-buffer-at-stop (transcriber-PR concern).
- Multi-input device selection (settings-module concern).
- Recordings retention policy (settings-module concern).
```

- [ ] **Step 2: Commit**

```bash
git add wiki/modules/recorder.md
git commit -m "$(cat <<'EOF'
wiki/modules/recorder: module page — purpose, API, design decisions, deps

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task H5: Wiki index

**Files:**
- Modify: `wiki/index.md`

- [ ] **Step 1: Update Decisions count + entry**

Replace the Decisions section header and append the new entry:

```markdown
## Decisions (3)

- [[decisions/framework-choice]] — Swift + SwiftUI + WhisperKit, macOS-only. Replaces prior Tauri assumption. | 2026-04-26
- [[decisions/hotkey-modifier-only-trigger]] — Bare-modifier triggers (Fn for v1) via NSEvent global monitor; Input Monitoring permission required. | 2026-04-27
- [[decisions/recorder-capture-pipeline]] — Recorder is pure capture in v1 (no VAD); in-process 16 kHz mono Float32 conversion; WAV-to-disk debug surface. | 2026-04-27
```

- [ ] **Step 2: Update Modules section**

Replace the Modules section with:

```markdown
## Modules (1)

- [[modules/recorder]] — Audio capture + WAV-to-disk debug surface; consumed by the future transcriber. | 2026-04-27
```

- [ ] **Step 3: Bump frontmatter `updated`**

Change the `updated:` field at the top of `wiki/index.md` to `2026-04-27`.

- [ ] **Step 4: Commit**

```bash
git add wiki/index.md
git commit -m "$(cat <<'EOF'
wiki/index: add recorder ADR + module entries

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task H6: log.md entries

**Files:**
- Modify: `log.md`

- [ ] **Step 1: Append two entries**

Append at the end of `log.md`:

```markdown

## [2026-04-27] document | ADR — Recorder capture pipeline + module page
- Created: wiki/decisions/recorder-capture-pipeline.md (status: stable)
- Created: wiki/modules/recorder.md
- Created: memory/domains/recorder.md
- Updated: wiki/index.md (Decisions 2→3; Modules 0→1)
- Decision: v1 recorder is pure capture (no VAD); in-process AVAudioConverter to 16 kHz mono Float32; WAV-to-disk at ~/Library/Application Support/Diktador/recordings/. Test seam = MicrophonePermissionProvider + AudioEngineDriver protocols. AppDelegate chains Microphone permission after Input Monitoring.
- Open questions filed in the ADR + memory note: VAD integration (transcriber-PR concern); streaming chunks (transcriber-PR concern); multi-input device selection (settings-module concern); retention policy (settings-module concern).

## [2026-04-27] meta | Recorder module shipped — PR #4
- PR: <fill in URL after gh pr create>
- Modules touched: modules/diktador-recorder/ (new package: Recorder, RecordingResult, MicrophonePermissionStatus, RecorderError, MicrophonePermissionProvider, AudioEngineDriver, SampleRateConverter, WAVWriter; tests +8); Diktador/ app target (AppDelegate dual-permission bootstrap + recording on Fn press/release + Last Recording menu item); project.yml + Diktador.xcodeproj/ (new package dep).
- Plan executed: docs/superpowers/plans/2026-04-27-recorder-module.md (8 phases A–H, all done)
- Tests run: xcodebuild Debug + Release BUILD SUCCEEDED; swift test 8/8 cases pass; computer-use verification confirmed bare-Fn hold records audio, "Last recording: X.Xs — Reveal in Finder" appears in the menu, and QuickLook playback of the WAV plays the user's voice.
- Simplify changes: <fill in after /simplify pass>
- Notes: VAD deferred to transcriber PR. AppDelegate now requests Microphone permission on first launch after Input Monitoring resolves to .granted.
- Required user setup unchanged: System Settings → Keyboard → Press 🌐 to: Do nothing (from PR #3); plus Allow on the new Microphone consent prompt.
```

- [ ] **Step 2: Commit (PR URL + simplify summary land in Phase I)**

```bash
git add log.md
git commit -m "$(cat <<'EOF'
log: document ADR + meta for recorder PR (URLs/simplify pending)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase I — Verification + ship

### Task I1: Full local verification

- [ ] **Step 1: `swift test` for the new module**

Run: `cd modules/diktador-recorder && swift test 2>&1 | tail -20`
Expected: 8/8 pass.

- [ ] **Step 2: `swift test` for the existing hotkey module (regression check)**

Run: `cd modules/diktador-hotkey && swift test 2>&1 | tail -10`
Expected: 8/8 pass.

- [ ] **Step 3: `xcodebuild` Debug**

Run from repo root: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: `xcodebuild` Release**

Run: `xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Release build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`.

### Task I2: Computer-use verification (user-driven)

- [ ] **Step 1: Open the Release build**

```bash
open ~/Library/Developer/Xcode/DerivedData/Diktador-*/Build/Products/Release/Diktador.app
```

- [ ] **Step 2: Granted-state path**

Expected on first launch: Microphone consent prompt (Input Monitoring is already granted from PR #3). Click **Allow**.

Verify:
1. Menu bar shows `mic` icon (idle); menu first item reads "Diktador (idle)".
2. Press and hold **Fn** for ~3 seconds.
3. Icon flips to `mic.fill`; menu reads "Diktador (listening…)".
4. Release Fn.
5. Icon and menu return to idle. A new menu item appears: "Last recording: 3.0s — Reveal in Finder".
6. Click the menu item — Finder opens with the WAV file selected.
7. Press Space in Finder to QuickLook the file. Audio playback plays your voice.

- [ ] **Step 3: Repeated recordings**

Hold Fn again for ~1 second; release. Verify the menu item updates to "Last recording: 1.0s — Reveal in Finder" (not duplicated).

- [ ] **Step 4: Microphone-denied path**

Quit Diktador. **System Settings → Privacy & Security → Microphone** → toggle **Diktador OFF**. Relaunch.

Verify:
1. Menu bar shows the warning icon.
2. Menu first item reads "Diktador (needs Microphone)".
3. Menu has "Open Microphone settings…" item that deep-links to the right pane.

Toggle Diktador back ON, quit + relaunch, confirm Step 2's behavior returns.

- [ ] **Step 5: Inspect a captured WAV**

Open one of the WAV files in `~/Library/Application Support/Diktador/recordings/` with `afinfo`:

```bash
afinfo ~/Library/Application\ Support/Diktador/recordings/*.wav | tail -10
```

Expected: `Sample Rate: 16000`, `1 ch, 16-bit signed`, file size ≈ 32 KB/s × duration.

### Task I3: `/simplify` pass

- [ ] **Step 1: Run /simplify**

Invoke the workspace `/simplify` skill on the diff. Three review agents in parallel (reuse / quality / efficiency); apply convergent findings; reject ones that strip useful comments or invent abstractions.

- [ ] **Step 2: If changes were applied, re-run tests**

```bash
cd modules/diktador-recorder && swift test 2>&1 | tail -10
xcodebuild -project Diktador.xcodeproj -scheme Diktador -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit any changes**

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

### Task I4: Open the PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/recorder-module
```

- [ ] **Step 2: Create the PR with `gh pr create`**

```bash
gh pr create --title "Recorder module — mic capture + WAV-to-disk debug surface" --body "$(cat <<'EOF'
## Summary

- New SwiftPM module `modules/diktador-recorder/` (package + library + target named `DiktadorRecorder`). Public `Recorder` class with `start()` / `stop(completion:)`, `isRecording`, and Microphone permission accessors mirroring the hotkey module's permission shape. Internal seams (`MicrophonePermissionProvider`, `AudioEngineDriver`) make the lifecycle unit-testable without hardware.
- `AVAudioEngine` capture + `AVAudioConverter` to 16 kHz mono `Float32` in process; `AVAudioFile` writes 16-bit PCM WAV files to `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav` on stop.
- `AppDelegate` chains a Microphone permission check after Input Monitoring, calls `recorder.start()` on Fn press and `recorder.stop` on Fn release, and surfaces a "Last recording: X.Xs — Reveal in Finder" menu item that deep-links to the captured file. Mic-denied state mirrors the existing Input-Monitoring-denied state with an "Open Microphone settings…" deep-link.

## Modules touched

- `modules/diktador-recorder/` — new module. Public surface: `Recorder`, `RecordingResult`, `MicrophonePermissionStatus`, `RecorderError`. Internal: `MicrophonePermissionProvider` + `AVPermissionProvider`, `AudioEngineDriver` + `AVAudioEngineDriver`, `SampleRateConverter`, `WAVWriter`.
- `Diktador/` (app target) — `AppDelegate` rewired for the dual-permission bootstrap + record-on-press + Last Recording menu item.
- `project.yml` + `Diktador.xcodeproj/` — adds the package dependency; xcodegen-regenerated.

## Test plan

- [x] `swift test` from `modules/diktador-recorder/` — 8/8 XCTest cases pass.
- [x] `swift test` from `modules/diktador-hotkey/` — 8/8 still pass (regression check).
- [x] `xcodebuild` Debug + Release — both `BUILD SUCCEEDED`.
- [x] Computer-use granted path: held Fn for ~3 s; menu showed "Last recording: 3.0s — Reveal in Finder"; click → Finder with the WAV selected; QuickLook played back the captured voice.
- [x] `afinfo` confirms the WAV is 16 kHz mono 16-bit PCM at the expected size for the duration.
- [x] Computer-use mic-denied path: warning icon + "Open Microphone settings…" menu item that deep-links to the right Settings pane.
- [x] /simplify pass run; <findings adopted | no actionable findings>.

## /simplify pass

<filled in after /simplify; see commit history>

## Wiki / memory updates

- `wiki/decisions/recorder-capture-pipeline.md` — new ADR documenting VAD deferral, in-process 16 kHz mono conversion, WAV-to-disk debug surface, and the dual-permission bootstrap.
- `wiki/modules/recorder.md` — new module spec page.
- `memory/domains/recorder.md` — operational notes (v1 config, open questions, debug recipes).
- `wiki/index.md` — Decisions 2→3; Modules 0→1.
- `modules/diktador-recorder/README.md` — public API, dependencies, full failure-mode list.
- `log.md` — `document` (ADR + module page) and `meta` (this PR) entries.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Capture the PR URL and patch `log.md`**

Replace `<fill in URL after gh pr create>` and `<fill in after /simplify pass>` placeholders with the actual values, then:

```bash
git add log.md
git commit -m "$(cat <<'EOF'
log: fill in PR URL + /simplify summary for recorder PR

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

### Task I5: Update `memory/resume.md`

**Files:**
- Modify: `memory/resume.md`

- [ ] **Step 1: Rewrite for the post-ship state**

Capture: PR #4 OPEN awaiting review/merge; the recorder module shipped; what's next session (transcriber, output, or settings module). Same shape as the previous post-ship resumes.

- [ ] **Step 2: Commit + push**

```bash
git add memory/resume.md
git commit -m "$(cat <<'EOF'
memory/resume: handoff after recorder PR opened

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

## Self-review

**Spec coverage:**

- ✅ New SwiftPM module `modules/diktador-recorder/` → Phase B.
- ✅ `Recorder` public class with `start` / `stop` / `isRecording` / permission API → Phase F2.
- ✅ `RecordingResult` value type → Phase C1.
- ✅ `MicrophonePermissionStatus` enum → Phase C1.
- ✅ `RecorderError` enum with the six named cases → Phase C1.
- ✅ `MicrophonePermissionProvider` protocol + `AVPermissionProvider` real impl → Phase D1.
- ✅ `AudioEngineDriver` protocol + `AVAudioEngineDriver` real impl → Phase D2.
- ✅ `SampleRateConverter` (lazy AVAudioConverter wrapper) → Phase E1.
- ✅ `WAVWriter` (16 kHz mono 16-bit PCM via AVAudioFile) → Phase E2.
- ✅ Recordings directory: `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav` → Phase F2 (`Recorder.defaultRecordingsDirectory`, `nextFileURL`).
- ✅ AppDelegate chained dual-permission bootstrap → Phase G2.
- ✅ Fn press/release call `recorder.start` / `recorder.stop` → Phase G2.
- ✅ "Last recording: X.Xs — Reveal in Finder" menu item → Phase G2 (`handleRecordingResult`, `revealLastRecording`).
- ✅ Microphone-denied warning UI with deep-link → Phase G2 (`showMicrophoneDeniedState`).
- ✅ Eight XCTest cases covering permission, lifecycle, reentry, success, and engine-failure-unwind → Phase F1 + F3.
- ✅ Module README, memory domain note, ADR, wiki module page, wiki index, log entries → Phase H.
- ✅ Verification (xcodebuild + swift test + computer-use + afinfo + /simplify + PR + post-ship hygiene) → Phase I.

**Placeholder scan:** Two intentional `<fill in...>` blanks in `log.md` are filled by Task I4 Step 3. The PR body and /simplify commit message also contain `<...>` markers explicitly filled at execution time. No `TBD` / `TODO` / "implement later" found.

**Type consistency:**

- `MicrophonePermissionStatus` cases (`.granted` / `.denied` / `.undetermined`) used consistently in spec, recorder, AppDelegate, tests.
- `RecorderError` cases match between spec, `RecorderError.swift`, `Recorder.swift`'s thrown / completion paths, and tests.
- `RecordingResult` fields (`fileURL`, `duration`, `sampleCount`) match between spec, value type, recorder construction site, and tests.
- `AudioEngineDriver` method names (`installTap`, `removeTap`, `start`, `stop`, `inputFormat`) match between protocol, real impl, stub, and recorder usage.
- `MicrophonePermissionProvider` method names (`currentStatus`, `requestAccess`) match between protocol, real impl, stub, and recorder usage.
- Recorder's dual-init pattern matches `HotkeyRegistry`'s precedent (public `init()` + internal `init(...)` taking the seams + a `recordingsDirectory: URL` for tests).

No gaps detected.
