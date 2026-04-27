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
- `RecorderError` — `Sendable, Equatable` error enum: `.microphonePermissionDenied`, `.alreadyRecording`, `.notRecording`, `.engineUnavailable`, `.formatConversionFailed`, `.fileWriteFailed`.

Tests run with `swift test` from `modules/diktador-recorder/`.

## Dependencies

- AVFoundation (system) — for `AVCaptureDevice`, `AVAudioEngine`, `AVAudioConverter`, `AVAudioFile`, `AVAudioPCMBuffer`.
- Foundation (system, re-exported via AVFoundation) — for `FileManager`, `URL`, `ISO8601DateFormatter`.
- Deployment target: macOS 14+.
- No environment variables, no external services, no other Diktador modules.

`INFOPLIST_KEY_NSMicrophoneUsageDescription` must be present in the app target's Info.plist (already declared in `project.yml` since PR #1). The app target's `.entitlements` file must also include `com.apple.security.device.audio-input` whenever `ENABLE_HARDENED_RUNTIME` is on; without it, `AVCaptureDevice.requestAccess` silently denies and the consent prompt never appears (see Known failure modes).

## Known failure modes

- **`com.apple.security.device.audio-input` entitlement missing under Hardened Runtime.** Without this entitlement, `AVCaptureDevice.requestAccess(for: .audio)` silently returns `false` and the app never appears in System Settings → Privacy & Security → Microphone — the consent prompt is suppressed entirely. The entitlement is wired through `Diktador/Diktador.entitlements` + `CODE_SIGN_ENTITLEMENTS` in `project.yml`. Removing it produces a recorder that "works" in unit tests but never gets mic data at runtime.
- **Microphone permission denied.** `start()` throws `RecorderError.microphonePermissionDenied`. AppDelegate catches and surfaces a warning state with a deep-link to System Settings → Privacy & Security → Microphone.
- **Microphone permission revoked at runtime.** macOS lets the user revoke access while Diktador is running; the engine's input node stops delivering samples, so the next `stop` returns a recording with zero or near-zero `sampleCount`. v1 mitigation: none. Future: poll `microphonePermission` on `NSApplication.didBecomeActiveNotification` and re-bootstrap.
- **`AVAudioEngine.start()` fails.** No input device available, hardware busy (other app holds exclusive access), or sandbox blocked. `start()` removes the tap, stops the engine, logs `[recorder] engine start failed: <error>`, and re-throws as `.engineUnavailable`.
- **Format conversion failure.** `AVAudioConverter` setup or per-buffer conversion failed. Per-buffer failures are logged and skipped — the recording continues with whatever samples have been accumulated. Setup failures throw `.formatConversionFailed` from the next `append` call.
- **WAV write failure.** Recordings directory not writable (rare; only happens if Application Support is read-only or the test points at an unwritable path) or `AVAudioFile.write` errored. `stop` completion fires with `.failure(.fileWriteFailed)`. The captured samples are lost.
- **Empty recording on stop.** `WAVWriter.write` rejects an empty `[Float]` accumulator with `.fileWriteFailed` rather than producing a zero-byte WAV. A push-to-talk session that releases too quickly to capture a single tap buffer will surface as `.fileWriteFailed`.
- **Double-`start()`.** Throws `.alreadyRecording`. Push-to-talk shouldn't trigger this (the hotkey module debounces edges), but a stuck `onPress` could.
- **`stop()` while idle.** Completion fires synchronously with `.failure(.notRecording)`.
- **App quit mid-recording.** `Recorder.deinit` removes the tap and stops the engine. The in-flight buffer is dropped; no partial WAV is written. Consumers must call `stop` explicitly for a successful capture.
- **Recorder dealloc during stop's WAV write.** The off-main write path captures `[weak self]`; if the recorder is dropped between `state = .finalizing` and the write completing, the completion never fires (and a partial file may exist on disk). v1 acceptable; the recorder is held for the app lifetime.
- **Native input format != 16 kHz mono.** The internal `SampleRateConverter` lazy-initializes on the first buffer once the device's actual `inputFormat` is known and converts every subsequent buffer. Conversion happens in process; the on-disk format is always 16 kHz mono 16-bit PCM regardless of the input device. If the input device changes mid-recording (AirPods reconnect, etc.) the cached converter continues using the stale source format and conversions may fail; restart the recording to pick up the new format.
- **Filename collision within one wall-clock second.** `nextFileURL` uses an ISO-8601 timestamp at second resolution. Two recordings released-then-pressed within 1 s produce the same filename and the second overwrites the first. Push-to-talk releases-then-presses inside 1 s are unusual but possible (rapid retry). Future remediation: add fractional seconds or a UUID suffix.
- **Tap buffer recycled mid-dispatch.** AVAudioEngine reuses its tap buffer for subsequent callbacks. `AVAudioEngineDriver.installTap` copies each buffer's float channel data into a fresh `AVAudioPCMBuffer` on the audio thread before dispatching to main; otherwise main reads the *current* buffer's data on every queued invocation rather than the snapshot from when the tap fired. Symptom of regression: every recording is exactly the size of the most recent buffer.
- **`AVAudioConverter` terminated by `.endOfStream`.** `SampleRateConverter` signals `.noDataNow` (not `.endOfStream`) when the per-call input is exhausted. `.endOfStream` would tell the converter the entire stream is finished; on the next `append` it would silently produce zero output frames and the recording would be exactly one tap buffer's worth of audio (~0.1 s at 4096-frame buffers @ 48 kHz) regardless of duration held.
