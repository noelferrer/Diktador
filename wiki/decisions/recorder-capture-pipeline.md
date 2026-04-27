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

**Test seam mirrors the hotkey module's pattern**: an internal `MicrophonePermissionProvider` protocol with an `AVPermissionProvider` real impl, and an internal `AudioEngineDriver` protocol with an `AVAudioEngineDriver` real impl. Test stubs let the recorder lifecycle be exercised without real hardware. The real `AVAudioEngineDriver` dispatches its tap callback to `DispatchQueue.main` so the `Recorder.state` mutations match the documented main-thread-only contract; otherwise Core Audio's tap thread races against `start`/`stop` on main.

## Consequences

- **No VAD code today.** The transcriber PR will need to either invoke WhisperKit's built-in VAD or add an energy-based pre-pass; the decision is deferred to that PR's brainstorming.
- **Pre-converted-to-16-kHz means smaller in-memory buffers** (~31 KB/s vs ~376 KB/s native 48 kHz × 2 channels × 4 bytes). Negligible for short push-to-talk dictation; matters when the buffer accumulates over 10+ minutes (currently impossible — push-to-talk gates duration).
- **Per-buffer dispatch hop to main** is the cost of the simple threading model. ~12 callbacks/s; immeasurable on Apple Silicon.
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
6. **Skip the dispatch-to-main on the tap callback** and rely on the documentation alone. Rejected during Phase F review when a reviewer caught that `state` mutations from the audio thread race against `start`/`stop` on main. The single hop is the smallest correct fix.

## Sources

- [`modules/diktador-recorder/README.md`](../../modules/diktador-recorder/README.md) — public API, dependencies, full failure-mode list.
- [`memory/domains/recorder.md`](../../memory/domains/recorder.md) — operational notes + open questions.
- [`docs/superpowers/specs/2026-04-27-recorder-module-design.md`](../../docs/superpowers/specs/2026-04-27-recorder-module-design.md) — design doc this ADR ratifies.
- [[decisions/framework-choice]] — parent ADR (locks Swift / AVAudioEngine / WhisperKit).
- [[decisions/hotkey-modifier-only-trigger]] — sibling ADR; establishes the dual-init test-seam pattern this module follows.
