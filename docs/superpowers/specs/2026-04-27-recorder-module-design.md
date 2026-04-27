---
title: Recorder module — mic capture + WAV-to-disk debug surface
type: design
created: 2026-04-27
updated: 2026-04-27
status: draft
module: diktador-recorder
---

# Recorder module — mic capture + WAV-to-disk debug surface

## Context

Diktador's audio pipeline is empty. PR #2 shipped the menu-bar shell and Option+Space push-to-talk. PR #3 swapped the trigger to bare Fn and surfaced Input Monitoring permission. Both PRs flip the menu icon between `mic` and `mic.fill` but no audio is actually captured. The user expected dictation-typing-text behavior at the end of PR #2 and was reminded that the transcription pipeline doesn't exist yet.

This module is the first slice of that pipeline: capture microphone audio between explicit `start()` / `stop()` calls and write a WAV file to disk on stop. The transcriber and output modules are not in scope; without them the module's only user-visible effect is a "Last recording: 2.3s — Reveal in Finder" menu item that lets the user play the captured audio in QuickLook.

The framework ADR ([`wiki/decisions/framework-choice.md`](../../../wiki/decisions/framework-choice.md)) lists `recorder` as "Audio capture + VAD." VAD is **deferred**: v1 push-to-talk uses the Fn hotkey to signal speech start/end, so VAD has no consumer until continuous-listening mode lands. WhisperKit's built-in VAD will be wired up alongside the transcriber when that PR happens.

## Scope

In scope:

1. New SwiftPM module at `modules/diktador-recorder/`. Package + library + target named `DiktadorRecorder` (lowercase directory, capitalized library — same naming workaround as `diktador-hotkey` to dodge SwiftPM identity bugs).
2. Public `Recorder` class with `start()` / `stop(completion:)`, `isRecording`, plus permission accessors (`microphonePermission`, `requestMicrophonePermission(completion:)`) mirroring the hotkey module's permission shape.
3. `AVAudioEngine` capture + `AVAudioConverter` to 16 kHz mono `Float32` in-process. WAV writer via `AVAudioFile` writing 16-bit PCM.
4. Recordings written to `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav`. Directory created lazily on first use.
5. Internal `MicrophonePermissionProvider` protocol + `AVPermissionProvider` real impl wrapping `AVCaptureDevice.authorizationStatus(for: .audio)` and `AVCaptureDevice.requestAccess(for: .audio)`. Test seam.
6. Internal `AudioEngineDriver` protocol over the AVAudioEngine surface (start/stop/installTap/removeTap). Real impl uses AVAudioEngine; test stub captures invocations and lets unit tests verify lifecycle without a real mic.
7. `AppDelegate` integration:
   - Owns a `Recorder` instance alongside `HotkeyRegistry`.
   - `bootstrapPushToTalk` chains a microphone permission check after Input Monitoring resolves to `.granted`. Mic `.undetermined` triggers `requestMicrophonePermission`; mic `.denied` shows a warning state with "Open Microphone settings…" deep-link similar to the existing Input-Monitoring-denied path.
   - `setListening(true)` calls `recorder.start()`; `setListening(false)` calls `recorder.stop` and on completion updates a `lastRecordingItem` menu entry titled `"Last recording: 2.3s — Reveal in Finder"`. Click reveals the file in Finder.
8. Tests: `swift test` from `modules/diktador-recorder/`. Stubs for both seams (`MicrophonePermissionProvider`, `AudioEngineDriver`) exercise the recorder lifecycle without hardware. Hardware capture is verified during computer-use phase.
9. Documentation: module `README.md` (Purpose / Public API / Dependencies / Known failure modes); `wiki/modules/recorder.md` (design rationale + ADR pointer); `wiki/decisions/recorder-capture-pipeline.md` (ADR — VAD deferral, WAV-to-disk debug surface, AVAudioConverter to 16 kHz mono); `memory/domains/recorder.md` (operational notes); `wiki/index.md` updates; `log.md` entries.

Deliberately out of scope:

- VAD (deferred to the transcriber PR or later — see "Open questions deferred").
- Streaming chunked transcription. Single buffer at stop. Streaming is a transcriber concern, not a recorder one.
- Retention policy. WAV files accumulate in `recordings/`; cleanup is a future settings-module concern.
- Noise gate, AGC, or any other audio preprocessing. Raw mic in, 16 kHz mono out.
- User-visible recordings folder UI beyond the "Last recording" menu item. Power users can navigate to the folder manually.
- Bluetooth / multi-input device selection. Uses the system default input.

## Architecture

`Recorder` is a single public class owning four internal collaborators:

```
Recorder
  ├─ permissionProvider:  MicrophonePermissionProvider  (default: AVPermissionProvider)
  ├─ engineDriver:        AudioEngineDriver             (default: AVAudioEngineDriver)
  ├─ converter:           SampleRateConverter           (wraps AVAudioConverter, file-private)
  └─ writer:              WAVWriter                     (wraps AVAudioFile, file-private)
```

The recorder transitions between three internal states: `idle`, `recording(buffer: [Float], startedAt: Date)`, and a brief `finalizing` window during `stop` where the file is being written. `isRecording` is true for `recording`. Only main-thread access in v1 (matches the hotkey module's threading contract).

### Public API

```swift
public final class Recorder {
    public init()
    internal init(
        permissionProvider: MicrophonePermissionProvider,
        engineDriver: AudioEngineDriver,
        recordingsDirectory: URL? = nil  // defaults to Application Support
    )

    public var microphonePermission: MicrophonePermissionStatus { get }
    public func requestMicrophonePermission(completion: @escaping (MicrophonePermissionStatus) -> Void)

    public var isRecording: Bool { get }

    public func start() throws
    public func stop(completion: @escaping (Result<RecordingResult, Error>) -> Void)
}

public struct RecordingResult: Sendable, Equatable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let sampleCount: Int
}

public enum MicrophonePermissionStatus: Sendable, Equatable {
    case granted, denied, undetermined
}

public enum RecorderError: Error, Equatable {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case engineUnavailable        // AVAudioEngine failed to start
    case formatConversionFailed   // AVAudioConverter setup or per-buffer convert failed
    case fileWriteFailed          // WAV writer failed
}
```

The dual-init pattern matches `HotkeyRegistry`: a public `init()` for app use and an internal `init(permissionProvider:engineDriver:recordingsDirectory:)` for tests. `recordingsDirectory: nil` in the internal init resolves to the same Application Support path the public init uses; tests can pass a temp directory.

### Permission flow

`MicrophonePermissionStatus` mirrors `InputMonitoringStatus` from the hotkey module:

| `MicrophonePermissionStatus` | `AVCaptureDevice.AuthorizationStatus` |
|---|---|
| `.granted` | `.authorized` |
| `.denied` | `.denied` or `.restricted` |
| `.undetermined` | `.notDetermined` |

`requestMicrophonePermission(completion:)` calls `AVCaptureDevice.requestAccess(for: .audio) { granted in … }` on a background queue, then dispatches the completion to main with `.granted` / `.denied`. macOS shows the consent prompt only the first time per app-bundle / user pair.

### `AudioEngineDriver` seam

```swift
internal protocol AudioEngineDriver: AnyObject {
    var inputFormat: AVAudioFormat { get }
    func installTap(bufferSize: AVAudioFrameCount, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    func removeTap()
    func start() throws
    func stop()
}
```

The real `AVAudioEngineDriver` constructs an `AVAudioEngine`, installs a tap on the input node with the requested buffer size, and forwards each captured buffer to `onBuffer`. The test stub `StubAudioEngineDriver` records `start` / `installTap` / `removeTap` / `stop` calls in order and lets tests synthesize buffers via a `feed(_ buffer: AVAudioPCMBuffer)` helper.

### Capture pipeline

1. `start()` checks `microphonePermission` — throws `.microphonePermissionDenied` if not granted.
2. Configures `engineDriver`: installs a tap (4096-sample buffer size — ~85 ms at 48 kHz, low-latency without per-buffer overhead).
3. Each tap callback: pass the native-format buffer to `SampleRateConverter` (lazily initialized to source-format → 16 kHz mono Float32 on first buffer once the actual `inputFormat` is known). Append converted samples to the in-memory `[Float]`.
4. `stop(completion:)` removes the tap, stops the engine, then on a background queue:
   - Opens an `AVAudioFile` for write at `recordingsDirectory/<ISO-timestamp>.wav`, settings = 16 kHz, 1 channel, 16-bit PCM, non-interleaved.
   - Writes the accumulated `[Float]` as one buffer.
   - Returns `.success(RecordingResult(fileURL:, duration:, sampleCount:))` on main.

If any step fails, returns `.failure(RecorderError…)` on main; the in-memory buffer is discarded.

## Error handling / failure modes

- **Permission denied at `start()`** — throws `.microphonePermissionDenied`. AppDelegate catches and surfaces the warning state.
- **AVAudioEngine fails to start** — no input device available, hardware busy, sandbox blocked. `engineDriver.start()` throws; recorder unwinds (removes tap, returns to `idle`) and re-throws as `.engineUnavailable`. Logged `[recorder]` prefix.
- **Double-`start()`** — `RecorderError.alreadyRecording`. Push-to-talk shouldn't trigger this (the hotkey module debounces edges), but a stuck `onPress` or test reentry might.
- **`stop()` while idle** — completion fires synchronously with `.failure(.notRecording)`.
- **Format conversion failure** — `.formatConversionFailed`. Captured samples discarded; partial recording not salvaged. v1 contract is "16 kHz WAV"; partial native-format files would lie about that contract.
- **WAV writer failure** — `.fileWriteFailed`. Captured samples lost. Future remediation: keep the buffer in memory until consumer (transcriber) succeeds; not in scope here since there's no consumer.
- **Permission revoked at runtime** — same shape as Input Monitoring revocation: monitor stays installed but events stop arriving (mic permission revocation actually invalidates the engine; the next tap callback never fires). v1 mitigation: none. Future: poll on `NSApplication.didBecomeActiveNotification`.
- **App quit mid-recording** — `Recorder.deinit` removes the tap and stops the engine. The in-flight buffer is dropped; no partial WAV is written. Consumers are expected to call `stop` explicitly for a successful capture.

## `AppDelegate` integration

The bootstrap state machine becomes a chained two-permission flow:

```
applicationDidFinishLaunching
  └─ configureStatusItem
  └─ bootstrapPushToTalk
       ├─ inputMonitoringPermission == .granted?
       │    ├─ no, .undetermined → request → recurse
       │    └─ no, .denied       → showInputMonitoringDeniedState; STOP
       │    └─ yes               → continue
       └─ microphonePermission == .granted?
            ├─ no, .undetermined → request → recurse
            └─ no, .denied       → showMicrophoneDeniedState; STOP
            └─ yes               → registerFnPushToTalk
```

`registerFnPushToTalk` is unchanged from PR #3; the press/release callbacks gain `recorder.start()` / `recorder.stop` calls:

```swift
onPress:  { [weak self] in
    self?.setListening(true)
    do {
        try self?.recorder.start()
    } catch {
        self?.handleRecorderStartFailure(error)
    }
}
onRelease: { [weak self] in
    self?.setListening(false)
    self?.recorder.stop { [weak self] result in
        self?.handleRecordingResult(result)
    }
}
```

`handleRecordingResult`:

- `.success(result)` → updates a stored `lastRecordingItem` menu entry (created on demand, inserted after the status row) with title `"Last recording: <duration>s — Reveal in Finder"`. Click reveals the file via `NSWorkspace.shared.activateFileViewerSelecting([fileURL])`.
- `.failure(error)` → updates the status row title briefly to a one-line error description (`"Recording failed: <error>"`) and logs the underlying error. Reverts to "Diktador (idle)" after 3 seconds.

`handleRecorderStartFailure` is the analog for `start()` throws: same brief status-row update + log.

The "needs Microphone" warning UI mirrors the existing Input-Monitoring-denied UI: warning icon, status row title `"Diktador (needs Microphone)"`, an "Open Microphone settings…" menu item that deep-links to `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`.

## Testing strategy

`swift test` from `modules/diktador-recorder/`. Test cases:

1. **`microphonePermission` reflects provider** — set stub status to `.granted`, expect `.granted`; flip to `.denied`, expect `.denied`.
2. **`requestMicrophonePermission` calls provider, returns result on completion** — exercises the async + main-hop pattern.
3. **`start()` throws when permission denied** — `RecorderError.microphonePermissionDenied`.
4. **`start()` installs the tap and starts the engine** — assert via `StubAudioEngineDriver`.
5. **`stop()` removes the tap, stops the engine, writes a WAV file, returns a `RecordingResult`** — feed three synthetic buffers totaling N samples through the stub; assert the WAV exists at the expected path with the expected sample count and duration.
6. **`start()` while recording throws `.alreadyRecording`**.
7. **`stop()` while idle returns `.failure(.notRecording)`**.
8. **WAV writer failure path** — point `recordingsDirectory` at a path the test process can't write; expect `.failure(.fileWriteFailed)`.

Out of scope for unit tests, verified via computer-use:

- Real microphone capture (no stable harness for hardware audio in CI; `swift test` doesn't have permission to access the mic anyway).
- The `AVCaptureDevice.requestAccess` system prompt.
- The actual `AVAudioConverter` 48 kHz → 16 kHz pipeline against real audio (verified by playing the resulting WAV in QuickLook and hearing your voice).

## Open questions (decided)

- **VAD?** No, deferred to the transcriber PR.
- **Streaming?** No, single buffer at stop. Streaming is a transcriber concern.
- **Format?** 16 kHz mono `Float32` in memory; 16 kHz mono 16-bit PCM on disk. Matches WhisperKit's expected input; smaller than native; pre-converted means the transcriber can read straight from `RecordingResult.fileURL` without re-conversion.
- **Recordings folder?** `~/Library/Application Support/Diktador/recordings/`. Standard macOS location for app-managed user data.
- **Filename?** ISO-8601 timestamp `YYYY-MM-DDTHH-MM-SS.wav` (colons replaced with hyphens for filesystem safety on cross-platform mounts).
- **Buffer size?** 4096 samples at the input format's native rate (~85 ms at 48 kHz). Low-latency-ish without per-buffer overhead.
- **Retention?** None in v1. Files accumulate. Future settings-module concern.
- **Permission state machine?** Chained: Input Monitoring first (gates the hotkey), then Microphone (gates the recording). Both prompt on first launch in sequence.

## Open questions deferred

- **VAD integration with the transcriber PR.** WhisperKit has a `VAD` setting; whether the recorder also runs an energy-based fallback for early end-of-speech detection in continuous mode is a question for that PR.
- **Multi-device selection** (use a non-default mic). Settings-module concern.
- **Recording history UI** beyond the "Last recording" menu item.
- **Auto-cleanup of recordings/** (e.g., delete after successful transcription, or LRU keep-the-last-N).
- **Bit depth tradeoffs.** 16-bit PCM is conservative; 24-bit would marginally improve dynamic range but costs disk space. Whisper doesn't benefit; keep 16-bit.

## Module-rule check

1. **One feature.** "Capture mic audio between start/stop and produce a WAV file." One sentence. ✓
2. **Boundary dependencies.** AppKit, AVFoundation, Foundation. Declared at the top of each source file. No other Diktador modules depended on. ✓
3. **Own errors.** Failure modes wrapped as `RecorderError` with named cases. AppDelegate is the consumer; underlying AVFoundation errors are logged with `[recorder]` prefix and surfaced as the typed `RecorderError`. ✓
4. **One public surface per module.** `Recorder` plus the value types it exposes (`RecordingResult`, `MicrophonePermissionStatus`, `RecorderError`). Internal: `MicrophonePermissionProvider`, `AudioEngineDriver`, `SampleRateConverter`, `WAVWriter`, `AVPermissionProvider`, `AVAudioEngineDriver`. ✓
5. **No shared mutable state.** All state lives on the `Recorder` instance; main-thread-only access. ✓
6. **One communication style.** Direct calls, completion handlers for the async stop flow. No registry / event escalation. Same pattern as the hotkey module. ✓

## Documentation deliverables

- `modules/diktador-recorder/README.md` — Purpose / Public API / Dependencies / Known failure modes (the four-section convention from `AGENTS.md`).
- `wiki/decisions/recorder-capture-pipeline.md` — ADR ratifying VAD deferral, WAV-to-disk debug surface, the in-process 16 kHz mono conversion, and the dual-permission bootstrap.
- `wiki/modules/recorder.md` — module spec page (Purpose / Public API / Design decisions / Dependencies / Open questions). Links to the ADR.
- `memory/domains/recorder.md` — operational notes (recordings folder location, file naming, debug recipe for capture-not-working).
- `wiki/index.md` — Decisions section bumps to 3, Modules section bumps to 1.
- `log.md` — `document` (ADR + module spec) and `meta` (PR ship) entries.
- `memory/resume.md` — rewritten for the post-ship state at the end.
