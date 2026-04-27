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

## Sharp edges

- **Swift 6 strict-concurrency**: AppDelegate stored-property init can't construct a `@MainActor` type directly. `@MainActor lazy var transcriber = WhisperKitTranscriber()` is the pattern. `@objc` selectors that call `@MainActor` helpers need `@MainActor @objc`.
- **Concurrent loadModel failures must coalesce consistently**: original implementation let waiter B see the raw driver error instead of `.modelLoadFailed(message:)`. Fixed by moving state mutations + error mapping INTO the in-flight `Task { @MainActor in … }` body; codified by `test_loadModel_concurrentFailures_bothCallersGetModelLoadFailed`.
- **Stale transcription completions are dropped**: `transcriptionGeneration` counter (mirrors `statusFlashGeneration`) gates post-await menu/clipboard mutations. Rapid Fn-cycle press-release-press-release would otherwise let a slower previous transcription clobber a faster newer one.

## See also

- [`modules/diktador-transcriber/README.md`](../../modules/diktador-transcriber/README.md) — public API, dependencies, full failure-mode list.
- [`wiki/decisions/transcriber-pipeline.md`](../../wiki/decisions/transcriber-pipeline.md) — VAD-redeferral, model-default, eager-load decisions.
- [`memory/domains/recorder.md`](recorder.md) — produces the WAV files this module consumes.
