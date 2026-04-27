---
type: memory-resume
updated: 2026-04-27
session_ended: end-of-session 2026-04-27 (PR #4 open awaiting review/merge)
---

# Resume point

> Where we left off, what's pending from you, what to do first next session. Read this file *first* on resume — it's the canonical handoff.

## Active state at end of session

- **Branch on disk**: `feat/recorder-module`. Pushed. Working tree clean.
- **PR #4**: https://github.com/noelferrer/Diktador/pull/4 — **OPEN**, awaiting your review/merge.
- **PRs #1–#3**: merged earlier (workspace bootstrap, hotkey module + menu bar shell, Fn-key trigger + Input Monitoring permission flow).
- **Build status**: `xcodebuild` Debug + Release green; `swift test` 9/9 (recorder) + 8/8 (hotkey) pass.
- **App location** (Release): `~/Library/Developer/Xcode/DerivedData/Diktador-bgxnmdzjhoodkyaftdnhajichfan/Build/Products/Release/Diktador.app`.
- **Debug artifact**: `/Applications/DiktadorDev.app` exists from this session's TCC-debugging (a copy with bundle ID `com.noelferrer.DiktadorDev`). Safe to delete after merge — it's not part of the PR; the production binary lives in DerivedData with the canonical `com.noelferrer.Diktador` bundle ID.

## Pending action from you (do before resuming)

1. **Review and merge PR #4** if the diff looks right: `gh pr merge 4 --squash --delete-branch`, or via the GitHub UI.
2. After merge: `git checkout main && git pull origin main` so local `main` is synced.
3. (Optional) `rm -rf /Applications/DiktadorDev.app` — debug artifact from this session's TCC dance.

## What got built this session (skim)

Single feature: `diktador-recorder` SwiftPM module + AppDelegate integration. Eighteen-plus commits. Subagent-driven cadence (implementer → spec reviewer → code-quality reviewer per phase) plus three runtime-discovered fixes during computer-use verification plus a /simplify pass.

- **Public surface**: `Recorder` class with `start() throws` / `stop(completion:)` / `isRecording`; `microphonePermission` getter + `requestMicrophonePermission(completion:)`. Value types `RecordingResult`, `MicrophonePermissionStatus`, `RecorderError`. Mirrors the hotkey module's permission-seam pattern.
- **Internals**: `MicrophonePermissionProvider` protocol with `AVPermissionProvider` real impl; `AudioEngineDriver` protocol with `AVAudioEngineDriver` real impl (input-node tap, audio-thread buffer copy, main-queue dispatch); `SampleRateConverter` (lazy `AVAudioConverter` to 16 kHz mono Float32, signaling `.noDataNow` per call so the converter survives across buffers); `WAVWriter` (`AVAudioFile`-backed; rejects empty samples; 16 kHz mono 16-bit PCM).
- **AppDelegate**: chained `bootstrapPushToTalk` → `checkMicrophonePermission` 3-state machine; Fn press/release call `recorder.start` / `recorder.stop`; "Last recording: X.Xs — Reveal in Finder" menu item updates in place; mic-denied state mirrors the existing Input-Monitoring-denied state.
- **Hardened Runtime entitlement**: new `Diktador/Diktador.entitlements` with `com.apple.security.device.audio-input`; wired via `CODE_SIGN_ENTITLEMENTS` in `project.yml`. Without it, `AVCaptureDevice.requestAccess` silently denies and the app never appears in the Mic panel.
- **Tests**: 9 XCTest cases covering permission, lifecycle, reentry guards, success path, engine-failure unwind, and write failure. Stubs (`StubPermissionProvider`, `StubAudioEngineDriver`) for hardware-free CI.

Three runtime fixes worth remembering for future audio work — none of these were caught by unit tests:
1. **Hardened Runtime requires the audio-input entitlement** for AVCaptureDevice/AVAudioEngine. No prompt, no panel entry, silent denial.
2. **AVAudioEngine recycles its tap buffer** between callbacks. Must memcpy the float channel data on the audio thread before dispatching to main; otherwise main reads the latest buffer's data on every queued invocation.
3. **AVAudioConverter `.endOfStream` terminates the stream**. For streaming usage (one tap buffer per `convert` call across many calls), the input-callback must signal `.noDataNow` instead. Symptom of regression: every recording is exactly one tap buffer worth of audio (~0.1s) regardless of duration held.

The /simplify pass landed five focused fixes: extract `flashFailure(_:)` with generation-counter cancellation; drop `lastRecordingURL` in favor of `NSMenuItem.representedObject`; main-thread-only invariant comment in `handleBuffer`; `samples.reserveCapacity` for ~60s; collapse a redundant double-guard in `SampleRateConverter`.

Full retrospective lives in [`daily/2026-04-27.md`](daily/2026-04-27.md) — to be appended in this session's daily note (currently still has only the Fn-trigger PR's retrospective; if a session-summary command is invoked, add a "## Recorder PR" section).

## What to do next session — pick one

### Option A — Transcriber module ⭐ unblocks the actual app

Reads the WAV files the recorder produces, runs them through WhisperKit (default) or Groq (user-selectable cloud fallback), produces a `String` transcript. The hotkey module + recorder module now provide everything needed: hotkey says "start/stop", recorder produces a 16 kHz mono PCM WAV at the WhisperKit-ready format. Adding the transcriber gets us *most* of the way to the dictation user experience — only the output module (text injection at cursor) would remain. Effort: ~90–120 min including ADR (model selection — `tiny` / `base` / `small`), download bootstrap (first-run model fetch), spec, plan, TDD, /simplify, PR.

Open question filed in [`domains/recorder.md`](domains/recorder.md): VAD integration (continuous-listening; not push-to-talk).

### Option B — Output module

Text injection at cursor — Accessibility-permission flow + clipboard-paste + CGEvent fallback. Pairs with the recorder via the (not-yet-existing) transcriber: recorder → transcriber → output → text appears at the cursor. Without the transcriber, output has no consumer; ship transcriber first.

### Option C — Bundle: transcriber + output

Bigger PR, delivers the full "talk → see typed text" UX in one shot. Riskier; recommended only after each piece's own brainstorm + spec.

**Recommendation: Option A.** It's the largest single user-visible step from "icon flips and a debug WAV is saved" toward "speech is transcribed and visible". Output then completes the loop.

## Key files to load on resume (in order)

1. **This file** — `memory/resume.md`
2. `wiki/index.md` — workspace catalog (now: 3 decisions, 1 module, 1 howto)
3. `memory/general.md` — operational facts
4. Last ~10 entries of `log.md` — recent activity
5. If picking Option A: `wiki/decisions/framework-choice.md` (locks WhisperKit + Groq), `wiki/decisions/recorder-capture-pipeline.md` (locks 16 kHz mono WAV format), `memory/domains/recorder.md` (recorder open questions including VAD deferral).
6. If picking Option B: `wiki/decisions/framework-choice.md` (locks hybrid clipboard-paste + CGEvent fallback for text injection).

`AGENTS.md` (the schema) and the framework ADR auto-load via the project `CLAUDE.md` symlink.

## Sharp edges to remember

- **No pushing to `main` directly** — workspace hook blocks it. PRs merge through `gh pr merge`.
- **Rebuilding ad-hoc-signed apps invalidates TCC grants.** Each rebuild gets a new codesign hash; macOS treats it as a new binary for TCC purposes. Toggle Diktador OFF and ON in System Settings → Input Monitoring (and Microphone) after each rebuild during development. `tccutil reset Microphone com.noelferrer.Diktador` purges the entry entirely if the toggle dance fails.
- **`com.apple.security.device.audio-input` entitlement is now load-bearing.** It lives in `Diktador/Diktador.entitlements` and is wired through `CODE_SIGN_ENTITLEMENTS` in `project.yml`. Removing it = silent mic denial; do not delete.
- **`AVAudioEngine` tap callbacks fire on the Core Audio thread**, not main. The driver hops to main internally; if you write a different tap, copy the buffer first.
- **`AVAudioConverter` `.endOfStream` is permanent.** For streaming, signal `.noDataNow` and reuse the converter across calls.
- **macOS `Press 🌐 to` setting must be "Do nothing"** for bare-Fn push-to-talk to work without firing Apple's globe action (from PR #3).
- **macOS only shows each TCC consent prompt once per app-bundle/user pair.** Re-trigger by changing the bundle ID or running `tccutil reset <Service> <bundle-id>`.
- **NSEvent monitor handles aren't ARC-managed** (from PR #3). The hotkey module's `unregister` and `deinit` both call `NSEvent.removeMonitor`.
- **Workspace `/go` skill** at `.claude/skills/go/SKILL.md` is the ship cycle. Used for PR #4 (Phase I2–I4 in the plan map onto /go's Phases 1–3); the post-ship `log.md` + `memory/daily/` updates land as Phase 4 hygiene.
- **`/simplify` 3-agent convergence pattern**: when reuse + efficiency or quality + efficiency flag the same finding, that's high signal and worth fixing. Single-agent flags are usually defensible-as-is.
- **`pushToTalkToken`** in `AppDelegate` is held for hygiene but never read in v1 (from PR #3). The settings module will read + unregister + re-register when the user changes the trigger.
- **`/Applications/DiktadorDev.app`** is a session-debug artifact (different bundle ID for TCC isolation during this PR). Not part of the canonical install. Safe to delete.

## Auto-memory note

Nothing user-facing changed in user-level auto-memory this session. The workspace memory under `memory/` is the canonical record of project state.
