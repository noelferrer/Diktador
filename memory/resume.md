---
type: memory-resume
updated: 2026-04-27
session_ended: end-of-session 2026-04-27 (PR #4 merged; ready for next feature)
---

# Resume point

> Where we left off, what's pending from you, what to do first next session. Read this file *first* on resume — it's the canonical handoff.

## Active state at end of session

- **Branch on disk**: `main`, clean, synced with `origin/main` at commit `b5c67ac`.
- **PR #4** (recorder module): **MERGED** — `b5c67ac` Recorder module — mic capture + WAV-to-disk debug surface (#4).
- **PRs #1–#3**: merged earlier (workspace bootstrap, hotkey module + menu bar shell, Fn-key trigger + Input Monitoring permission flow).
- **Build status**: `xcodebuild` Debug + Release green; `swift test` 9/9 (recorder) + 8/8 (hotkey) pass.
- **App location** (Release): `~/Library/Developer/Xcode/DerivedData/Diktador-bgxnmdzjhoodkyaftdnhajichfan/Build/Products/Release/Diktador.app`.
- **Debug artifact still on disk**: `/Applications/DiktadorDev.app` (a copy with bundle ID `com.noelferrer.DiktadorDev` from this session's TCC-debugging). Safe to delete — it's not part of the canonical install. `rm -rf /Applications/DiktadorDev.app` if you want it gone.

## Pending action from you

None — clean handoff.

## What the app does today

1. Press and hold **Fn** → menu bar icon flips from `mic` (idle) to `mic.fill` (listening), `AVAudioEngine` starts capturing 48 kHz mic input.
2. Each tap buffer is converted in-process to 16 kHz mono `Float32` and accumulated.
3. Release Fn → engine stops, the accumulator is written off-main as a 16-bit PCM WAV at `~/Library/Application Support/Diktador/recordings/<ISO-timestamp>.wav`.
4. A "Last recording: X.Xs — Reveal in Finder" menu item appears (or updates in place); clicking it opens Finder selecting the file. QuickLook plays back the captured voice.
5. Permissions: bootstrap chains Input Monitoring → Microphone, both with deep-link warning UI on denial. Required entitlement: `com.apple.security.device.audio-input` in `Diktador/Diktador.entitlements`.

What the app **does not yet do**: transcribe the audio or inject text at the cursor. Those are the next two PRs.

## What to do next session — pick one

### Option A — Transcriber module ⭐ recommended next

Reads the WAV files the recorder produces, runs them through **WhisperKit** (default — local, Apple Silicon Core ML / Neural Engine) or **Groq** (user-selectable cloud fallback, free tier), produces a `String` transcript. The hotkey + recorder modules now provide everything needed: hotkey says "start/stop", recorder produces a 16 kHz mono PCM WAV at the WhisperKit-ready format. Adding the transcriber gets us *most* of the way to dictation — only the output module (text injection at cursor) would remain. Effort: ~90–120 min including ADR (model selection — `tiny` / `base` / `small`), download bootstrap (first-run model fetch), spec, plan, TDD, /simplify, PR.

Open question filed in `memory/domains/recorder.md`: VAD integration (continuous-listening; not push-to-talk).

### Option B — Output module

Text injection at cursor — Accessibility-permission flow + clipboard-paste primary + CGEvent fallback. Pairs with the recorder via the (not-yet-existing) transcriber: recorder → transcriber → output → text appears at the cursor. Without the transcriber, output has no consumer; ship transcriber first.

### Option C — Bundle: transcriber + output

Bigger PR, delivers the full "talk → see typed text" UX in one shot. Riskier; recommended only after each piece's own brainstorm + spec.

**Recommendation: Option A.** It's the largest single user-visible step from "icon flips and a debug WAV is saved" toward "speech is transcribed and visible". Output then completes the loop.

## Key files to load on resume (in order)

1. **This file** — `memory/resume.md`
2. `wiki/index.md` — workspace catalog (now: 3 decisions, 1 module, 1 howto)
3. `memory/general.md` — operational facts
4. Last ~10 entries of `log.md` — recent activity
5. If picking Option A: `wiki/decisions/framework-choice.md` (locks WhisperKit + Groq), `wiki/decisions/recorder-capture-pipeline.md` (locks 16 kHz mono WAV format the transcriber will consume), `memory/domains/recorder.md` (recorder open questions including VAD deferral).
6. If picking Option B: `wiki/decisions/framework-choice.md` (locks hybrid clipboard-paste + CGEvent fallback for text injection).

`AGENTS.md` (the schema) and the framework ADR auto-load via the project `CLAUDE.md` symlink.

## Sharp edges to remember

### Audio / recorder lessons (load-bearing — don't regress)

- **Hardened Runtime requires the `com.apple.security.device.audio-input` entitlement.** It lives in `Diktador/Diktador.entitlements` and is wired through `CODE_SIGN_ENTITLEMENTS` in `project.yml`. Removing it = silent mic denial; `AVCaptureDevice.requestAccess` returns `false` without prompting and the app never appears in the Mic panel. The transcriber may need its own entitlement (`com.apple.security.network.client` for Groq HTTPS); audit during that ADR.
- **`AVAudioEngine` tap callbacks fire on the Core Audio thread**, not main. The driver hops to main internally; if a future tap implementation skips the hop, the recorder's COW dance corrupts state. `dispatchPrecondition(.onQueue(.main))` in `Recorder.handleBuffer` makes the contract a runtime-checked invariant.
- **`AVAudioEngine` recycles its tap buffer** between callbacks. The driver memcpys the float channel data on the audio thread before dispatching to main; otherwise main reads the latest buffer's data on every queued invocation.
- **`AVAudioConverter` `.endOfStream` is permanent.** For streaming usage, signal `.noDataNow` and reuse the converter across calls. `.endOfStream` after the first buffer = every subsequent recording is exactly one tap buffer (~0.1s) regardless of duration held.
- **macOS `Press 🌐 to` setting must be "Do nothing"** for bare-Fn push-to-talk to work without firing Apple's globe action (from PR #3).

### Dev-time gotchas (will hit you on every rebuild)

- **Rebuilding ad-hoc-signed apps invalidates TCC grants.** Each rebuild gets a new codesign hash; macOS treats it as a new binary for TCC purposes. After every rebuild during dev, toggle Diktador OFF and ON in System Settings → Input Monitoring (and Microphone). `tccutil reset Microphone com.noelferrer.Diktador` purges the entry entirely if the toggle dance fails. Same for `tccutil reset ListenEvent com.noelferrer.Diktador`.
- **Each TCC consent prompt only shows once per app-bundle/user pair.** Re-trigger via `tccutil reset` or change the bundle ID. The "fresh bundle ID" trick (`com.noelferrer.DiktadorDev`) is a useful TCC-debug escape valve when state gets stuck — ship reverts to `com.noelferrer.Diktador`.
- **Privacy panel's + button refuses to browse `~/Library/Developer/...` paths**. If you need to manually add an app, copy it to `/Applications/` first (which is what `/Applications/DiktadorDev.app` was for this session).
- **Computer-use verification is the only way to catch entitlement / threading / converter-streaming bugs.** Unit tests with stubs missed all three runtime fixes from PR #4. Hold real Fn, hear real voice in the WAV — no shortcuts.

### Other workspace edges

- **No pushing to `main` directly** — workspace hook blocks it. PRs merge through `gh pr merge`.
- **NSEvent monitor handles aren't ARC-managed** (from PR #3). The hotkey module's `unregister` and `deinit` both call `NSEvent.removeMonitor`.
- **Workspace `/go` skill** at `.claude/skills/go/SKILL.md` is the ship cycle. Phase 1 (test) → Phase 2 (`/simplify`) → Phase 3 (PR) → Phase 4 (post-ship `log.md` + `memory/daily/` hygiene).
- **`/simplify` 3-agent convergence pattern**: when reuse + efficiency or quality + efficiency flag the same finding, that's high signal and worth fixing. Single-agent flags are usually defensible-as-is.
- **`pushToTalkToken`** in `AppDelegate` is held for hygiene but never read in v1 (from PR #3). The settings module will read + unregister + re-register when the user changes the trigger.
- **Subagent-driven cadence** (used through PRs #3 and #4): implementer (sonnet) → spec reviewer (haiku) → code-quality reviewer (`superpowers:code-reviewer`, opus). Final review across whole branch before merge. Pattern is working — keep using it.

## Auto-memory note

Nothing user-facing changed in user-level auto-memory this session. The workspace memory under `memory/` is the canonical record of project state.
