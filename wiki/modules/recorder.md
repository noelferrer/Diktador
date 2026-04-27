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
- **Tap callback hopped to main** inside `AVAudioEngineDriver` — Core Audio delivers tap buffers on a real-time background thread; the hop makes the recorder's documented main-thread contract real.

## Dependencies

- AVFoundation (system) — `AVCaptureDevice`, `AVAudioEngine`, `AVAudioConverter`, `AVAudioFile`, `AVAudioPCMBuffer`.
- Foundation (system, re-exported via AVFoundation) — `FileManager`, `URL`, `ISO8601DateFormatter`.
- macOS 14+.
- No other Diktador modules. AppDelegate composes recorder + hotkey.

## Open questions

- VAD integration in continuous-listening mode (transcriber-PR concern).
- Streaming chunks vs single-buffer-at-stop (transcriber-PR concern).
- Multi-input device selection (settings-module concern).
- Recordings retention policy (settings-module concern).
- Filename collision within one wall-clock second (rare; press-release-press inside 1 s).
- Test coverage for the format-conversion-failed path requires a `SampleRateConverter` protocol seam — defer until needed.
