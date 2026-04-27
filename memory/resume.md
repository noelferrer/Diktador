---
type: memory-resume
updated: 2026-04-27
session_ended: 2026-04-27 PR #6 ready to push (transcriber module — all phases complete; code review approved ship)
---

# Resume point

> Where we left off, what's pending from you, what to do first next session. Read this file *first* on resume — it's the canonical handoff.

## Active state at end of session

- **Branch on disk**: `feat/transcriber-module`. **Not yet pushed.** Working tree clean.
- **PR #6**: ready to open. All implementation, docs, simplify pass, and final whole-branch code review complete.
- **Most recent commit**: `90002c0 simplify: drop narrating comments; bound title-truncation work`.
- **Build status**: `xcodebuild` Debug + Release green. `swift test` 15/15 in `modules/diktador-transcriber/`. Recorder 9/9 + hotkey 8/8 unaffected.
- **Final whole-branch review verdict**: **ship**. Three Minor findings + four Follow-ups, none blocking.

## What the app does today (after PR #6 lands)

1. **App launch** → menu bar icon `mic` (idle); status row `Diktador (idle)`; transcription status row shows `Transcription: loading model…` while WhisperKit downloads `openai_whisper-base` (~140 MB on first run, cached at `~/Library/Application Support/Diktador/models/`).
2. **Once cached**, status flips to `Transcription: ready` in 1–2 s on subsequent launches.
3. **Hold Fn** → menu icon `mic.fill`, recorder captures (PR #4).
4. **Release Fn** → recorder writes WAV (PR #4), AppDelegate fires Task → `transcriber.transcribe(audioFileURL:)`. Status flashes `transcribing…` then `ready`. Transcript copied to `NSPasteboard.general`; `Last transcript: "<60 chars>…" — Copied` menu item appears (or updates in place). Click re-copies.
5. **Empty hold** → status `Transcription: no speech detected`, clipboard untouched (preserves prior good transcript).
6. **`Cmd+V` in any app** → pastes the latest transcript.
7. **Rapid press-release-press-release** → only the latest transcription wins. Stale completions are silently dropped via `transcriptionGeneration` counter.

What the app **does not yet do**: inject text at the cursor. Clipboard-copy is the v1 stand-in.

## Pending action from you

1. **Hold Fn computer-use verification (Task H1)** — I cannot run the app and hold Fn. Recipe at `memory/domains/transcriber.md`'s "/go computer-use verification recipe" section: launch Release `Diktador.app`, watch status flow `loading model… → ready`, hold Fn + speak + release, verify clipboard + menu, test cached relaunch, test empty-hold path, click "Last transcript" to confirm re-copy.
2. **Push branch + open PR (Task H5)**:
   ```
   git push -u origin feat/transcriber-module
   gh pr create --title "Transcriber module — WhisperKit transcription with clipboard-copy debug surface (#6)" --body "<see plan Task H5 for the body>"
   ```
3. **Post-merge cleanup (Task H6)**: `git checkout main && git pull && git branch -d feat/transcriber-module`. Then start the next session — output module is the natural next pick (text injection at cursor; replaces clipboard-copy stand-in).

## What to do next session (assuming PR #6 merged)

### Option A — Output module ⭐ recommended next

Text injection at cursor. Pairs with the now-shipped transcriber: recorder → transcriber → output. Per the framework ADR, hybrid clipboard-paste primary + CGEvent fallback. Both require Accessibility permission. Effort: ~90–120 min including ADR (pasteboard preserve-and-restore strategy, key-down-key-up timing for CGEvent path), spec, plan, TDD, /simplify, PR.

Once the output module ships, dictation works end-to-end: hold Fn → speak → release → text appears at the cursor. The clipboard-copy in PR #6 becomes the preserve-and-restore intermediary the output module will refactor.

### Option B — Settings module

Model picker (`tiny` / `base` / `small`), Groq backend toggle, API-key entry (Keychain). Surfaces the dual-backend framework decision. Effort: ~120–180 min — heavier UI work.

### Option C — Groq backend

Add `GroqTranscriber: Transcriber` sibling impl + a `DispatchingTranscriber` that owns primary/fallback. Needs settings module to expose the toggle. Effort meaningless without settings.

**Recommendation: Option A.** It closes the dictation loop — the largest user-visible step left.

## Phase summary (what shipped in PR #6)

| Phase | What | Commits |
|---|---|---|
| Spec + plan | Brainstorm, design doc, task-by-task plan | `c2ab3c7`, `9086985` |
| A | Pre-flight | (verification only, no commit) |
| B | SwiftPM scaffold + WhisperKit dep | `8fb62ab` |
| C | `Transcriber` protocol + `TranscriberState` + `TranscriberError` | `9b3e4f5` |
| D | State machine TDD (12 commits, 14 tests + I2 fix → 15 tests) | `41736f9` through `3626cfc`, plus `dcad58f` (plan `nonisolated` fix) and `4ef39fc` (I2 concurrent-failure-coalesce fix) |
| E | `LiveWhisperKitDriver` + `project.yml` wiring | `99c7c9e`, `209ba3d` |
| F | AppDelegate integration (load on launch + auto-transcribe + clipboard + menu) | `4ccf89e`, `3e7a3df`, `72f00cd` (I1 dead-state + I2 generation-counter fix), `8e5abf7` (spec menu-order docs) |
| G | Docs (README + ADR + wiki + memory + index + log) | `c647fc3` through `6cdd77f`, plus `db67450` (review-pass clarifications) |
| H2 | /simplify pass — single-agent findings, applied two safest | `90002c0` |
| H3 | Final whole-branch review | (review-only, no commit; verdict: ship) |
| H4 | This resume.md update | (this commit) |
| H5/H6 | Push + PR + post-merge cleanup | (your turn) |

## Key files to load on resume

1. **This file** — `memory/resume.md`
2. `wiki/index.md` — workspace catalog (now: 4 decisions, 2 modules)
3. `memory/general.md` — operational facts
4. `memory/domains/transcriber.md` — operational notes for the new module (sharp edges, debug recipes)
5. `memory/domains/recorder.md` and `memory/domains/hotkey.md` — sibling-module operational state (unchanged)
6. `wiki/decisions/transcriber-pipeline.md` — the new ADR
7. Last ~10 entries of `git log --oneline` — recent activity
8. If picking Option A (output module): `wiki/decisions/framework-choice.md` (locks hybrid clipboard-paste + CGEvent fallback for text injection)
9. If picking Option B (settings module): `wiki/decisions/transcriber-pipeline.md` "Open questions deferred" section

`AGENTS.md` (the schema) and the framework ADR auto-load via the project `CLAUDE.md` symlink.

## Sharp edges to remember (load-bearing — don't regress)

### Transcriber-specific (this PR — load on resume of any transcriber work)

- **Swift 6 strict-concurrency requires `nonisolated static func defaultModelStorage()`.** `@MainActor`-isolated static funcs can't be called from default-arg expressions in nonisolated contexts. Function body uses Sendable Foundation APIs only, so `nonisolated` is safe. Documented inline at `modules/diktador-transcriber/Sources/DiktadorTranscriber/WhisperKitTranscriber.swift`.
- **`AppDelegate` stored-property init can't construct a `@MainActor` type.** Use `@MainActor lazy var transcriber = WhisperKitTranscriber()`. Defers construction to first access (which happens on `MainActor`).
- **`Task { @MainActor [weak self] in }` is the spawn pattern in non-`@MainActor` `AppDelegate`.** Captures the actor isolation at the call site. Follow-up FU1: declaring `AppDelegate` itself `@MainActor` would collapse the nine `@MainActor` annotations in the file to zero — worth a one-commit refactor in a future PR.
- **`@objc` selectors that call `@MainActor` helpers need `@MainActor @objc`** (e.g. `copyLastTranscript(_:)`). NSMenu dispatches on main anyway.
- **Concurrent `loadModel` failures must coalesce consistently.** Initial naive impl let waiter B see the raw driver error rather than `.modelLoadFailed(message:)`. Fix: state mutations + error mapping happen INSIDE the in-flight `Task<Void, Error> { @MainActor in … }` body so any caller awaiting `task.value` sees identical throw semantics. Codified by `test_loadModel_concurrentFailures_bothCallersGetModelLoadFailed` (commit `4ef39fc`).
- **Stale transcription completions are dropped via `transcriptionGeneration` counter** (mirrors `statusFlashGeneration`). Each `runTranscription` increments at entry, captures the value, gates every post-await mutation. Without this, rapid Fn-cycle press-release-press-release lets a slower previous transcription clobber a newer one's result.
- **`@unchecked Sendable` on `LiveWhisperKitDriver`** is required because `WhisperKit` is `open class` with mutable public vars and no `Sendable` conformance. The `NSLock` around the held pipeline reference is what makes the wrapper safe.
- **`prewarm: true` in `WhisperKitConfig` doubles first-run model load time** per WhisperKit's `Configurations.swift:55-66`. Trade-off accepted to keep peak memory bounded on 8 GB Apple Silicon. Symptom of regression: first launch hangs at "loading model…" for 60+ s. Captured in ADR + README + memory domain.
- **WhisperKit version drift**: `Package.swift` declares `from: "0.9.0"`; first integration resolved to `0.18.0`. Workspace convention gitignores `Package.resolved` — fresh clones may resolve to a later tag. API stable across 0.9–0.18; pin if a regression bisect demands it.
- **`results.map(\.text).joined(separator: " ")` matches WhisperKit's own merge convention.** WhisperKit trims each `TranscriptionResult.text` at construction; no double-space risk.
- **Eager-load on launch can race the first hotkey press.** Recorder is independent — WAV always lands. Transcribe await joins the in-flight `loadModel` via Swift structured concurrency; no queue data structure needed.

### Carried forward (still apply)

- **Hardened Runtime requires `com.apple.security.device.audio-input`** (PR #4). Outbound HTTPS for WhisperKit's HuggingFace fetch is allowed without a separate `network.client` entitlement.
- **Rebuilding ad-hoc-signed apps invalidates TCC grants.** After every rebuild during dev, toggle Diktador OFF and ON in Input Monitoring + Microphone. `tccutil reset Microphone com.noelferrer.Diktador` purges entries that get stuck. Same for `tccutil reset ListenEvent com.noelferrer.Diktador`.
- **macOS `Press 🌐 to` setting must be "Do nothing"** for bare-Fn push-to-talk to work without firing Apple's globe action.
- **`AVAudioEngine` tap callbacks fire on the Core Audio thread**, recorder copies the buffer + dispatches to main; never regress this (PR #4 lessons).
- **`AVAudioConverter` `.endOfStream` is permanent**; signal `.noDataNow` for streaming usage (PR #4 lesson).
- **No pushing to `main` directly** — workspace hook blocks it. PRs merge through `gh pr merge`.
- **Subagent-driven cadence**: implementer (general-purpose) → spec reviewer (general-purpose) → code-quality reviewer (`superpowers:code-reviewer`, opus) → final whole-branch review. Pattern is working — keep using it. Phase F's I2 race fix (concurrent loadModel failures) is the case study where the per-phase quality reviewer caught a subtle correctness issue that 15 unit tests + spec review didn't.
- **`/simplify` 3-agent convergence pattern**: when ≥2 agents flag the same finding, that's high signal. Single-agent flags are usually defensible-as-is. PR #6's H2 simplify pass surfaced 4 single-agent findings; only 2 trivial subtractions were applied.

## Follow-ups tracked from PR #6 reviews (none blocking)

- **FU1**: `AppDelegate` could be `@MainActor`-annotated at class level to drop the 9 per-member `@MainActor` annotations. One-commit refactor in a future PR.
- **FU2**: Naming for the future Groq sibling — confirmed scales (`GroqTranscriber`, `GroqDriver`, `LiveGroqDriver`, `StubGroqDriver`).
- **FU3**: Operational readiness on offline first launch — settings module concern (in-app retry button).
- **M1** (defensible): `LiveWhisperKitDriver.transcribe` throws `TranscriberError.transcriptionFailed("pipeline not loaded")` directly from the driver. Path is unreachable in practice (transcribe always drives loadModel first). Could be `preconditionFailure(...)` or an internal-driver enum + boundary mapping. Left as-is.
- **M2** (defensible): README implies `defaultModelStorage()` creates the directory; actually `LiveWhisperKitDriver.loadModel` does. README's wording is fine for in-repo readers.

## Auto-memory note

Nothing user-facing changed in user-level auto-memory this session. The workspace memory under `memory/` is the canonical record of project state.
