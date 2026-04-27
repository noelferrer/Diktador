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
- Capture: `AVAudioEngine` input-node tap at 4096-sample buffer size (~85 ms at 48 kHz). The tap callback hops to `DispatchQueue.main` inside `AVAudioEngineDriver` so all `Recorder.state` mutations live on a single thread. Lazily-initialized `AVAudioConverter` resamples every buffer to 16 kHz mono `Float32` in process.
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
- **Filename collision within one second** — current `nextFileURL` uses second-resolution ISO timestamps; rapid press-release-press cycles can collide. Future fix: fractional seconds or UUID suffix.
- **`SampleRateConverter` testability** — the converter is held behind a `let`; no protocol seam means the format-conversion-failed failure path isn't unit-testable. Add a `SampleRateConverter` protocol if the test demand justifies the surface area.

## Debug recipes

- Recording produces a zero-byte / near-zero-sample-count file: check `microphonePermission`. If `.granted`, the most likely cause is the input device being held by another exclusive consumer (a video call, another DAW). The `[recorder] engine start failed` log line is the primary signal.
- Recording sounds pitched / time-stretched: the `SampleRateConverter` is using a stale source format. Hot-plugging an input device mid-recording is not in scope; restart the recording.
- `stop` returns `.fileWriteFailed`: check `~/Library/Application Support/Diktador/recordings/` exists and is writable. The recorder creates intermediate directories on write but cannot recover from a sandbox-blocked path.
- `stop` returns `.fileWriteFailed` with `samples.count` near zero: the recording was too short to capture a single 4096-sample tap buffer. Hold Fn longer.
- `stop` returns immediately with `.notRecording`: the `start` likely threw silently — check the press-handler's error log for `[app] recorder.start failed`.
- Mic consent prompt never appears AND Diktador isn't listed in System Settings → Privacy & Security → Microphone: missing `com.apple.security.device.audio-input` entitlement. Hardened Runtime suppresses the prompt when the entitlement is absent. Verify with `codesign -d --entitlements - /path/to/Diktador.app`.
- Every recording is exactly ~0.1s (one tap buffer) regardless of how long Fn was held: regression of the `SampleRateConverter` `.noDataNow` signal — `.endOfStream` would terminate the converter after the first buffer and silently produce zero-length output for every subsequent buffer.
- Recording captures only the most recent buffer's worth of data (intermittent garbage tail): regression of the `AVAudioEngineDriver` tap-buffer copy — the engine reuses its tap buffer between callbacks; the driver must copy the float channel data on the audio thread before dispatching to main.
- Re-grant TCC on every rebuild: ad-hoc-signed apps (`CODE_SIGN_IDENTITY: "-"`) get a fresh codesign hash on every build, and macOS treats each new hash as a different binary for TCC purposes. Toggle Diktador OFF and ON in System Settings → Input Monitoring (and Microphone) after each rebuild during dev. `tccutil reset Microphone com.noelferrer.Diktador` purges the entry entirely if the toggle dance fails.

## See also

- [`modules/diktador-recorder/README.md`](../../modules/diktador-recorder/README.md) — public API, dependencies, full failure-mode list.
- [`wiki/decisions/recorder-capture-pipeline.md`](../../wiki/decisions/recorder-capture-pipeline.md) — VAD-deferral + format choices.
- `memory/domains/hotkey.md` — the trigger surface that drives this module.
