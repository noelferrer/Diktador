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
- **First-run model load is slower than expected.** `WhisperKitConfig` ships with `prewarm: true`, which per WhisperKit's `Configurations.swift:55-66` doubles first-run model load time (load-unload-load Core ML specialization warm-up) in exchange for lower peak memory during compilation. Trade-off accepted to keep peak memory bounded on 8 GB Apple Silicon. Symptom: status line stuck on "loading model…" for 30–60 s on first launch with the `base` model. Subsequent launches load from cache in 1–2 s. Revisit if first-load latency exceeds ~60 s on representative user hardware.
- **WhisperKit minor-version drift past the declared floor.** `Package.swift` declares `from: "0.9.0"` (up-to-major); `Package.resolved` actually resolves the latest tag at the time the package was first integrated, currently `0.18.0`. The API surfaces used by `LiveWhisperKitDriver` (`WhisperKitConfig` fields, `pipeline.transcribe(audioPath:)` returning `[TranscriptionResult]` with `.text`) are stable across that range. If a future bisect reveals a regression introduced by an Argmax minor bump, pin `Package.swift` to the last known-good tag.
