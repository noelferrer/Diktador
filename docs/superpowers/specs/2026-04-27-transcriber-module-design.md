---
title: Transcriber module — WhisperKit transcription with clipboard-copy debug surface
type: design
created: 2026-04-27
updated: 2026-04-27
status: draft
module: diktador-transcriber
---

# Transcriber module — WhisperKit transcription with clipboard-copy debug surface

## Context

PR #4 shipped the recorder: a 16 kHz mono WAV file lands at `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav` every time the user presses-and-releases Fn. The pipeline still ends at "WAV on disk" — there is no transcription, no text anywhere.

This module is the next slice: take that WAV file, run it through WhisperKit, return a `String`. The output module (text injection at the cursor) is deferred — without it, the transcript needs a temporary landing pad. v1 copies the transcript to the system clipboard so the user can verify dictation by pressing `Cmd+V` in any app, and surfaces it as a menu bar item that mirrors the recorder's "Last recording" surface.

The framework ADR ([`wiki/decisions/framework-choice.md`](../../../wiki/decisions/framework-choice.md)) locks WhisperKit as the default backend and Groq as a user-selectable cloud alternative. **Groq is deferred** to a follow-up PR: it has no v1 consumer (no settings module to expose the toggle), it adds Keychain + HTTPS + a dispatcher, and the framework ADR's "primary/fallback" logic only matters once both backends ship. The protocol seam (`Transcriber`) lands in this PR so Groq drops in later as a sibling impl without touching consumers.

The recorder ADR ([`wiki/decisions/recorder-capture-pipeline.md`](../../../wiki/decisions/recorder-capture-pipeline.md)) deferred VAD to "the transcriber PR." That deferral persists: push-to-talk + WhisperKit's batch `transcribe(audioPath:)` is the simplest correct path for v1. VAD only earns its keep when continuous-listening mode lands; this PR does not introduce continuous listening.

## Scope

In scope:

1. New SwiftPM module at `modules/diktador-transcriber/`. Package + library + target named `DiktadorTranscriber` (lowercase directory, capitalized library — same naming workaround as the hotkey and recorder modules).
2. Public `Transcriber` protocol with `loadModel()`, `transcribe(audioFileURL:)`, and a `state: TranscriberState` accessor.
3. Public `WhisperKitTranscriber` concrete impl backed by [`argmaxinc/WhisperKit`](https://github.com/argmaxinc/WhisperKit). `@MainActor`-isolated state mutations.
4. WhisperKit dependency added at the project level (`project.yml` packages section, pinned to a current stable tag).
5. Hard-coded model: `openai_whisper-base` (~140 MB). Settings module will expose the picker later. Stored under `~/Library/Application Support/Diktador/models/`.
6. Internal `WhisperKitDriver` protocol over the WhisperKit surface (init/load + transcribe). Real impl `LiveWhisperKitDriver` wraps WhisperKit; tests inject a stub. Mirrors the recorder's `AudioEngineDriver` test seam.
7. `AppDelegate` integration:
   - Owns a `WhisperKitTranscriber` instance alongside `Recorder` and `HotkeyRegistry`.
   - `applicationDidFinishLaunching` kicks off `transcriber.loadModel()` in a detached `Task` after `bootstrapPushToTalk` runs.
   - `handleRecordingResult` (the existing recorder-stop completion) gains a transcription branch: on `.success(let recording)`, schedule `transcriber.transcribe(audioFileURL: recording.fileURL)`; the transcript is copied to `NSPasteboard.general` and surfaced as a menu item.
   - New menu items: a status-line item (loading / ready / transcribing / failed) and a "Last transcript: '…' — Copied" item that re-copies on click.
8. Tests: `swift test` from `modules/diktador-transcriber/`. Stub driver covers state machine, error mapping, queue-while-loading semantics. Real WhisperKit transcription is verified during `/go` computer-use.
9. Documentation: module `README.md` (Purpose / Public API / Dependencies / Known failure modes); `wiki/modules/transcriber.md` (design rationale + ADR pointer); `wiki/decisions/transcriber-pipeline.md` (ADR — WhisperKit-only v1, base model, eager-load-on-launch, clipboard-copy debug surface, Groq + VAD deferral); `memory/domains/transcriber.md` (operational notes); `wiki/index.md` updates; `log.md` entries.

Deliberately out of scope:

- **Groq backend.** Second `Transcriber` impl + dispatcher with primary/fallback logic. Lands in a follow-up PR alongside the settings module that exposes the picker.
- **VAD / continuous-listening mode.** Push-to-talk doesn't need it; `transcribe(audioPath:)` consumes the complete WAV file. WhisperKit's built-in VAD (or an energy-based pre-pass) lands when continuous listening is on the roadmap.
- **Settings module.** No user-visible model picker, no API key entry, no primary/fallback configuration. v1 hard-codes `openai_whisper-base`.
- **Output module (text injection).** Clipboard-copy is a stand-in. The output module replaces it with `NSPasteboard` + `Cmd+V` synthesis or `CGEvent` keystroke fallback per the framework ADR.
- **Streaming transcription.** WhisperKit supports it; push-to-talk + a complete WAV file does not need it. Streaming is a transcriber-PR-2 concern if the latency budget demands it.
- **Multi-language explicit selection.** WhisperKit auto-detects; v1 accepts whatever it returns. Settings module can add an override.
- **Transcript history / log.** Only the most-recent transcript is surfaced. Future settings module can persist a rolling history.
- **Partial-download recovery.** WhisperKit handles HuggingFace Hub semantics internally; if a download is interrupted, the next launch retries. v1 does not second-guess.
- **Network connectivity check.** WhisperKit's first-run download requires network; if offline, the model load fails and surfaces as `.failed`. No proactive reachability probe.
- **Onboarding flow.** First-run experience is a single status-line message in the menu bar. No splash screen, no setup wizard.

## Architecture

`WhisperKitTranscriber` is a single `@MainActor` public class owning two internal collaborators:

```
WhisperKitTranscriber
  ├─ driver:  WhisperKitDriver           (default: LiveWhisperKitDriver)
  └─ state:   TranscriberState           (private(set), main-actor isolated)
```

State transitions form a small DAG:

```
.uninitialized
   │
   │  loadModel()
   ▼
.loading ─────► .ready ──► .transcribing ──► .ready
   │                            │
   │  underlying error          │  underlying error
   ▼                            ▼
.failed(error)               .failed(error)  (sticky until next loadModel)
```

`@MainActor` isolation matches the recorder's threading contract — every public mutation lives on main. WhisperKit's own work (model load + inference) runs on background queues internally; `LiveWhisperKitDriver` `await`s those calls and the actor isolation handles the hop back to main automatically.

### Public API

```swift
public protocol Transcriber: Sendable {
    @MainActor var state: TranscriberState { get }
    func loadModel() async throws
    func transcribe(audioFileURL: URL) async throws -> String
}

public final class WhisperKitTranscriber: Transcriber {
    public init(modelName: String = "openai_whisper-base")
    internal init(driver: WhisperKitDriver, modelName: String = "openai_whisper-base")

    @MainActor public private(set) var state: TranscriberState
    public func loadModel() async throws
    public func transcribe(audioFileURL: URL) async throws -> String
}

public enum TranscriberState: Sendable, Equatable {
    case uninitialized
    case loading
    case ready
    case transcribing
    case failed(TranscriberError)
}

public enum TranscriberError: Error, Sendable, Equatable {
    case modelLoadFailed(message: String)
    case transcriptionFailed(message: String)
    case audioFileUnreadable(URL)
    case emptyTranscript
}
```

`TranscriberError` flattens the underlying WhisperKit / Foundation errors into a `String` message field so the type stays `Equatable` (matches `RecorderError`'s pattern). The original error is logged via `NSLog("[transcriber] …")` at the throw site for diagnosis.

### Internal — `WhisperKitDriver` test seam

```swift
internal protocol WhisperKitDriver: Sendable {
    func loadModel(name: String, modelStorage: URL) async throws
    func transcribe(audioFileURL: URL) async throws -> String
}

internal final class LiveWhisperKitDriver: WhisperKitDriver {
    // Wraps `WhisperKit(model: name, modelFolder: modelStorage)` and
    // `whisperKit.transcribe(audioPath: ...)`. Holds the WhisperKit
    // instance after first load.
}
```

The driver is the only file that imports `WhisperKit`. Tests substitute a stub driver that records calls and returns canned results, exercising the `WhisperKitTranscriber` state machine without the model.

### Lifecycle — happy path

1. `AppDelegate.applicationDidFinishLaunching` runs `bootstrapPushToTalk` (existing). After that returns, AppDelegate spawns `Task { try? await transcriber.loadModel() }`. State: `.uninitialized → .loading`.
2. Background: `LiveWhisperKitDriver.loadModel` instantiates `WhisperKit(model: "openai_whisper-base", modelFolder: <appsupport>/models)`. WhisperKit's init triggers the HuggingFace Hub download if the model isn't cached. ~140 MB on first run; instant on subsequent runs. Returns when the model is loaded into memory and ready for inference.
3. State: `.loading → .ready`. AppDelegate's `await transcriber.loadModel()` returns; the next line updates the menu status line to "Ready" via `updateTranscriberStatus`.
4. User holds Fn → recorder starts (existing).
5. User releases Fn → recorder stops, fires `handleRecordingResult` with `.success(let recording)` (existing).
6. AppDelegate spawns `Task { let transcript = try await transcriber.transcribe(audioFileURL: recording.fileURL) }`. State: `.ready → .transcribing`.
7. Background: `LiveWhisperKitDriver.transcribe` calls `whisperKit.transcribe(audioPath: url.path)`, returns the concatenated segment text trimmed of leading/trailing whitespace.
8. State: `.transcribing → .ready`. AppDelegate's task continuation runs on main, copies the transcript to `NSPasteboard.general`, and updates the "Last transcript" menu item.

### Lifecycle — recording before model is ready

1. App launches; `loadModel()` is in flight (state `.loading`).
2. User holds Fn → recorder starts.
3. User releases Fn → recorder writes WAV.
4. AppDelegate spawns `Task { try await transcriber.transcribe(audioFileURL: ...) }`.
5. `transcribe` checks state: if `.loading`, awaits via a continuation registered with the in-flight load; if `.uninitialized`, calls `loadModel()` itself first.
6. Once state is `.ready`, transcription proceeds.
7. The user sees menu status: "Loading transcription model…" → "Transcribing…" → "Last transcript: …".

This is the "no first-press feels broken" guarantee. The WAV is durable on disk; the transcribe task simply suspends until the model is ready. No queue data structure — Swift structured concurrency provides one for free.

### Lifecycle — model load failure

1. `loadModel()` throws (no network, disk full, WhisperKit init error).
2. State: `.loading → .failed(.modelLoadFailed(message: ...))`.
3. AppDelegate menu shows "Model unavailable — see Console". The "Last transcript" item shows the most recent successful transcript if any (sticky).
4. The recorder still works. The user can hold Fn, speak, release; the WAV lands on disk. `transcribe` immediately throws `.modelLoadFailed` (state is `.failed`); AppDelegate logs and surfaces an error in place of the transcript.
5. To recover: relaunch Diktador. v1 has no in-app retry button; the settings module can add one later.

### Lifecycle — transcription failure

1. `transcribe(audioFileURL:)` throws (corrupt WAV, internal WhisperKit error).
2. State: `.transcribing → .ready` (transient failures don't poison the model). The error propagates to AppDelegate's task.
3. AppDelegate logs `[app] transcription failed: <error>` and surfaces "Transcription failed — see Console" in the status line until the next successful transcription.
4. The WAV remains on disk for replay (matches recorder's existing "Reveal in Finder" affordance).

### Empty transcript

If `whisperKit.transcribe` returns no segments or only whitespace, the driver returns an empty `String`. `WhisperKitTranscriber.transcribe` detects the empty case and throws `.emptyTranscript`. AppDelegate handles this specially: menu shows "No speech detected" rather than an error, and clipboard is **not** modified (preserves whatever the user had copied previously).

### Threading contract

- All `WhisperKitTranscriber` state mutations run on `@MainActor`. Public methods are `async`; the actor handles hops automatically.
- `LiveWhisperKitDriver` calls into WhisperKit on a background queue (WhisperKit's own actor isolation). The transcriber's `await` resumes on the main actor.
- `AppDelegate` does not touch transcriber state from anywhere outside the main thread. `Task` closures run on `@MainActor` because `AppDelegate` is `@MainActor`-bound.

## AppDelegate integration

The existing AppDelegate state expands by three menu items and one transcriber field. Diff (conceptual; not the literal diff):

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    // ...existing fields...
    private let transcriber = WhisperKitTranscriber()
    private var transcriberStatusItem: NSMenuItem?
    private var lastTranscriptItem: NSMenuItem?
    private var lastTranscript: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bootstrapPushToTalk()
        Task { @MainActor in
            await loadTranscriptionModel()
        }
    }

    private func loadTranscriptionModel() async {
        updateTranscriberStatus("Loading transcription model…")
        do {
            try await transcriber.loadModel()
            updateTranscriberStatus("Ready")
        } catch {
            updateTranscriberStatus("Model unavailable — see Console")
            NSLog("[app] transcriber.loadModel failed: \(error)")
        }
    }

    private func handleRecordingResult(_ result: Result<RecordingResult, Error>) {
        switch result {
        case .success(let recording):
            // ...existing "Last recording" menu update...
            Task { @MainActor in
                await runTranscription(for: recording.fileURL)
            }
        case .failure(let error):
            // ...existing failure handling...
        }
    }

    private func runTranscription(for url: URL) async {
        updateTranscriberStatus("Transcribing…")
        do {
            let transcript = try await transcriber.transcribe(audioFileURL: url)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            lastTranscript = transcript
            updateLastTranscriptItem(transcript)
            updateTranscriberStatus("Ready")
        } catch TranscriberError.emptyTranscript {
            updateTranscriberStatus("No speech detected")
        } catch {
            updateTranscriberStatus("Transcription failed — see Console")
            NSLog("[app] transcription failed: \(error)")
        }
    }
}
```

### Menu order

```
Diktador (idle | listening… | needs Input Monitoring | needs Microphone)
─── (separator)
Transcription: <Loading… | Ready | Transcribing… | Model unavailable | …>   [disabled label]
Last transcript: "<first 60 chars>…" — Copied   [click re-copies]            [hidden until first success]
─── (separator)
Last recording: 2.3s — Reveal in Finder           [hidden until first success, existing]
─── (separator)
Quit
```

`updateLastTranscriptItem` lazily inserts the menu item the first time it is needed (matches `lastRecordingItem`'s pattern). Truncation at 60 chars uses a single-line title; the full transcript is on the clipboard.

## Testing

### Unit (`swift test` from `modules/diktador-transcriber/`)

| Test | Verifies |
|---|---|
| `loadModel_happyPath_transitionsToReady` | `.uninitialized → .loading → .ready`; driver `loadModel(name:modelStorage:)` called once with `"openai_whisper-base"`. |
| `loadModel_idempotent_secondCallNoOps` | Calling `loadModel()` twice still yields `.ready`; driver `loadModel` called once total. |
| `loadModel_concurrent_callsJoin` | Two simultaneous `loadModel()` tasks both resolve; driver called once. |
| `loadModel_failure_transitionsToFailed` | Driver throws → state `.failed(.modelLoadFailed(...))`; subsequent `transcribe` throws `.modelLoadFailed`. |
| `transcribe_beforeLoadModel_loadsImplicitly` | `transcribe()` called from `.uninitialized` state triggers a `loadModel()` first. |
| `transcribe_whileLoading_awaits` | `loadModel()` in flight + `transcribe()` started → both resolve in correct order. |
| `transcribe_happyPath_returnsString` | Driver returns `"hello world"` → transcribe returns `"hello world"`. |
| `transcribe_emptyResult_throwsEmptyTranscript` | Driver returns `""` → `.emptyTranscript`; state returns to `.ready`. |
| `transcribe_whitespaceOnly_throwsEmptyTranscript` | Driver returns `"   \n  "` → `.emptyTranscript`. |
| `transcribe_driverFailure_transitionsBackToReady` | Driver throws → `.transcriptionFailed`; state goes back to `.ready` (not `.failed`); next transcribe works. |
| `transcribe_failedModelState_throwsImmediately` | After a `.failed` state, `transcribe` throws without calling the driver. |
| `transcribe_audioFileMissing_throwsAudioFileUnreadable` | Bogus URL → `.audioFileUnreadable(url)` from precondition check. |

### Integration

WhisperKit + real WAV transcription is verified during `/go` computer-use phase, not in `swift test`. The verification recipe (in `memory/domains/transcriber.md`):

1. Build Release. Launch Diktador.
2. Wait for menu status: "Ready" (proves model load works end-to-end). On a fresh install, watch for "Loading transcription model…" first; the `base` model takes ~30–60 s to download on a typical connection.
3. Hold Fn, speak a known phrase ("Hello, this is a test of Diktador transcription."), release.
4. Menu status flashes "Transcribing…" then "Ready". "Last transcript: …" item appears with the first 60 chars.
5. `Cmd+V` in any app — transcript pastes.
6. Quit + relaunch — model loads from cache (status goes "Loading…" → "Ready" within 1–2 s).

### Build verification

- `xcodebuild -scheme Diktador -configuration Debug build` — green.
- `xcodebuild -scheme Diktador -configuration Release build` — green.
- `swift test` from `modules/diktador-transcriber/` — all transcriber tests pass.
- `swift test` from `modules/diktador-recorder/` and `modules/diktador-hotkey/` — still green (no regressions).

## Open questions deferred

- **Model picker UX.** v1 hard-codes `openai_whisper-base`. The settings module will expose `tiny` / `base` / `small` and persist the choice in `UserDefaults`. Switching the model post-launch requires rerunning `loadModel()`; the transcriber's `state` already supports the transition.
- **Groq backend + dispatcher.** Second `Transcriber` impl. Adds Keychain-stored API key, HTTPS client, and a `DispatchingTranscriber` that owns primary + fallback. Lands when the settings module can expose the picker.
- **Streaming transcription.** WhisperKit supports it; consider when continuous-listening mode lands or if push-to-talk latency on `small` becomes a problem.
- **Transcript history.** Surface the last N transcripts in the menu rather than just one. Settings-module concern.
- **Cancellation.** v1 has no "cancel transcription" affordance. If a user holds Fn for 10 minutes by accident, they wait for the transcription to finish (or quit Diktador). Future: expose a cancel item in the menu while `state == .transcribing`.
- **Recordings cleanup tied to successful transcription.** Once the transcript is on the clipboard, the WAV file is technically redundant. Settings module can add a "delete after transcription" toggle. Today the WAV is kept (matches the recorder ADR's debug-surface intent).
- **Hotkey-during-transcribing.** v1 allows starting a new recording while the previous transcription is still in flight; transcriptions queue via `Task` and resolve in order. The "Last transcript" surface only ever shows the latest result. Whether to debounce or block is a settings/UX concern.
- **Network reachability probe before download.** v1 lets WhisperKit attempt the download and surfaces the failure. A proactive reachability check could improve the error message but adds a dependency on `Network.framework`.

## File layout

```
modules/diktador-transcriber/
├── Package.swift
├── Sources/
│   └── DiktadorTranscriber/
│       ├── Transcriber.swift              # protocol, state enum, error enum
│       ├── WhisperKitTranscriber.swift    # @MainActor concrete impl
│       └── WhisperKitDriver.swift         # internal driver protocol + LiveWhisperKitDriver
├── Tests/
│   └── DiktadorTranscriberTests/
│       └── TranscriberTests.swift         # state machine + error mapping; uses StubDriver
└── README.md                              # Purpose / Public API / Dependencies / Known failure modes

Diktador/
└── AppDelegate.swift                      # +transcriber, +menu items, +run-on-stop wiring, +clipboard

project.yml                                # +DiktadorTranscriber package + WhisperKit dep, +target dep
```

`Package.swift` declares WhisperKit as a dependency at the module level (so `swift test` resolves it). At the project level, WhisperKit is added once in `project.yml`'s `packages:` section so the app target picks it up via the transcriber module's transitive dependency.

## Ship sequence

Following the project's `/go` workflow (test → simplify → PR), with the Superpowers TDD flow inside Phase 1:

1. **Brainstorm** — this document.
2. **Spec review** — user reviews this file.
3. **Plan** — `writing-plans` produces `docs/superpowers/plans/2026-04-27-transcriber-module-plan.md`.
4. **Implement** — TDD per task: failing test → minimum code → green → next. WhisperKit wiring is the riskiest step; do it last (after the protocol + state machine are green via stubs).
5. **`/simplify`** — 3-agent convergence pass on the new module.
6. **PR** — single PR titled "Transcriber module — WhisperKit transcription with clipboard-copy debug surface (#6)" against `main`, with the ADR + module README + memory domain file.
7. **Post-ship** — `log.md` entry, `memory/resume.md` updated for the next session (output module is the natural next pick).

## Sources / references

- [`wiki/decisions/framework-choice.md`](../../../wiki/decisions/framework-choice.md) — locks WhisperKit + Groq as the dual-backend pipeline.
- [`wiki/decisions/recorder-capture-pipeline.md`](../../../wiki/decisions/recorder-capture-pipeline.md) — produces the 16 kHz mono WAV the transcriber consumes; defers VAD to this PR (further deferred here).
- [`wiki/decisions/hotkey-modifier-only-trigger.md`](../../../wiki/decisions/hotkey-modifier-only-trigger.md) — establishes the dual-init test-seam pattern reused here.
- [`modules/diktador-recorder/README.md`](../../../modules/diktador-recorder/README.md) — the producer side of the WAV file consumed by this module.
- [`docs/superpowers/specs/2026-04-27-recorder-module-design.md`](2026-04-27-recorder-module-design.md) — sibling spec; this document follows its shape.
- WhisperKit: https://github.com/argmaxinc/WhisperKit
- typr's `transcribe_local.rs` (read-only at `typr-main/src-tauri/src/transcribe_local.rs`) — conceptual reference for the WhisperKit-equivalent pipeline shape (typr uses whisper.cpp; same idea).
