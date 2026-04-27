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

**`prewarm: true` accepted for `WhisperKitConfig`** to keep peak memory bounded during model load on 8 GB Apple Silicon. Per WhisperKit's documentation, prewarm doubles first-run latency (~30–60 s for `openai_whisper-base`). Acceptable: the menu status line surfaces the wait honestly and subsequent launches load from cache in ~1–2 s.

## Consequences

- **No user-visible Groq toggle in v1.** The settings module's first job will be exposing the backend picker plus the API-key entry field; until then, Diktador is local-only.
- **First launch downloads ~140 MB.** Menu status line ("Loading transcription model…") makes the wait visible. On metered networks the user gets a deterministic message rather than silence.
- **Clipboard-copy is a load-bearing temporary.** It will be replaced when the output module lands. Today it provides the verification path for `/go` computer-use and the friends-distribution feedback loop.
- **`.failed` model state is sticky.** Once `loadModel` fails, transcription is unavailable until the user restarts Diktador. v1 has no in-app retry button — settings module concern.
- **The "Last transcript" menu item only ever shows one transcript.** Rapid press-release-press cycles overwrite the previous label. Persisted transcript history is a settings-module feature.
- **WhisperKit's transitive deps land in the app bundle.** Argmax's Core ML wrappers + tokenizer assets add to the binary. Acceptable: WhisperKit is the framework ADR's chosen default.
- **No network reachability probe.** WhisperKit attempts the download; failure surfaces via `.modelLoadFailed`. Adding a proactive probe would buy a marginally better error message and a `Network.framework` dependency.
- **Test seam covers everything but the WhisperKit call itself.** State machine, queue-while-loading, error mapping, sticky failure, empty-transcript handling all unit-tested. Real WhisperKit transcription is verified during `/go` computer-use, the same shape as the recorder's "real audio" verification.
- **Swift 6 strict-concurrency adaptations** were necessary at the AppDelegate boundary: `WhisperKitTranscriber` is `@MainActor`-isolated, so the `AppDelegate` stored property uses `@MainActor lazy var transcriber = WhisperKitTranscriber()` to defer construction to a main-actor context, and `@objc copyLastTranscript(_:)` carries `@MainActor` because it calls `@MainActor` helpers. These follow inevitably from the module's actor isolation; documented here so a future Groq sibling impl can match the pattern.

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
