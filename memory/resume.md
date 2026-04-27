---
type: memory-resume
updated: 2026-04-27
session_ended: end-of-session 2026-04-27 (PR #3 open awaiting review/merge)
---

# Resume point

> Where we left off, what's pending from you, what to do first next session. Read this file *first* on resume — it's the canonical handoff.

## Active state at end of session

- **Branch on disk**: `feat/hotkey-fn-trigger` (17 commits ahead of `main`, pushed, working tree clean).
- **PR #3**: https://github.com/noelferrer/Diktador/pull/3 — **OPEN**, awaiting your review/merge.
- **PR #2** (hotkey module + menu bar shell): merged earlier.
- **PR #1** (workspace bootstrap + framework ADR): merged earlier.
- **Build status**: `xcodebuild` Debug + Release green; `swift test` 8/8 pass (post-/simplify rerun).
- **App location** (Release): `~/Library/Developer/Xcode/DerivedData/Diktador-bgxnmdzjhoodkyaftdnhajichfan/Build/Products/Release/Diktador.app`.

## Pending action from you (do before resuming)

1. **Review and merge PR #3** if the diff looks right: `gh pr merge 3 --squash --delete-branch`, or via the GitHub UI.
2. (After merge) `git checkout main && git pull origin main` so local `main` is synced before the next branch.

`feat/*` → `main` merges via `gh pr merge` or the UI go through normal review and don't trip the workspace push-to-main hook.

## What got built this session (skim)

Two-session arc. Started with the spec + plan committed end of yesterday, paused mid-Phase-H, resumed and finished today.

- **PR #3 (open)** — bare Fn (🌐) push-to-talk replaces Option+Space. `HotkeyRegistry` extended with a parallel NSEvent global-monitor + paired local-monitor path for `ModifierTrigger.fn` (Carbon-Events doesn't see Fn). New public types `ModifierTrigger`, `InputMonitoringStatus`. New permission API on the registry (`inputMonitoringPermission`, `requestInputMonitoringPermission(completion:)`) backed by an internal `PermissionProvider` seam wrapping `IOHIDCheckAccess` / `IOHIDRequestAccess`. `AppDelegate` rewired to a 3-state bootstrap (granted → register Fn; undetermined → request + recurse; denied → warning UI + deep-link to System Settings → Privacy & Security → Input Monitoring). 8/8 XCTest cases pass; xcodebuild Debug + Release green; computer-use verified the granted/denied/globe-key paths. /simplify pass landed 8 findings (image-factory dedupe, menu-item caching with double-insert guard, struct-construct cleanup, deinit cleanup, comment trims, test rename) — see today's daily for the full list.
- **Subagent-driven cadence** (yesterday's session): six implementer dispatches across phases B–G, each followed by spec-compliance + code-quality reviewers. Zero BLOCKED / NEEDS_CONTEXT escalations.
- **/simplify** (today's session): three review agents in parallel (reuse / quality / efficiency); convergent findings adopted, divergent ones skipped with explicit reasoning.

Full retrospective lives in [`daily/2026-04-27.md`](daily/2026-04-27.md).

## What to do next session — pick one

### Option A — Right-side modifiers PR ⭐ recommended next

Same NSEvent global-monitor infrastructure that landed in PR #3 unblocks Right-Option-only / Right-Command-only / etc. — but the API surface is different: these are *sided variants* of `KeyCombo.modifiers`, not new `ModifierTrigger` cases. Likely shape: `KeyCombo` gains a `sidedness:` parameter (or a parallel `SidedKeyCombo` type), the registry routes sided combos through the NSEvent path. Requires its own brainstorm — the API decision (extend `KeyCombo` vs. new value type) is real and affects the future settings-module schema. Effort: ~60–90 min including ADR, plan, TDD, /simplify, PR. Probably warrants its own ADR.

Open question filed in [`domains/hotkey.md`](domains/hotkey.md): right-modifier API shape.

### Option B — Recorder module ⭐ unblocks the actual app

`AVAudioEngine` capture + VAD (voice activity detection). The hotkey module already provides the `setListening(true/false)` semantic via the v1 push-to-talk; `recorder` consumes it to start/stop buffering. First piece of the actual audio pipeline — required before the user can experience real dictation. Module README convention per `AGENTS.md`. Mic permission (`NSMicrophoneUsageDescription` is already declared in `project.yml`) prompts on first capture.

### Option C — Three modules together (recorder + transcriber + output)

Bigger PR; delivers the "talk → see typed text" UX in one shot. Riskier; not recommended without each piece's own brainstorm + spec.

The user expected dictation-typing-text behavior at the end of PR #2 and was reminded that the transcription pipeline doesn't exist yet. **Options B + C deliver that experience.** Option A delivers a smaller polish on the trigger surface.

## Key files to load on resume (in order)

1. **This file** — `memory/resume.md`
2. `wiki/index.md` — workspace catalog (now: 2 decisions, 1 howto)
3. `memory/general.md` — operational facts (env, conventions, current open questions)
4. Last ~10 entries of `log.md` — recent activity
5. If picking Option A: `memory/domains/hotkey.md` Open questions section + `wiki/decisions/hotkey-modifier-only-trigger.md` for the ratified dual-path architecture (the right-modifier ADR will reference it)
6. If picking Option B: re-read `wiki/decisions/framework-choice.md` for the agreed STT pipeline shape (WhisperKit + optional Groq); check `Diktador/AppDelegate.swift` for where the `setListening(true/false)` callback lives so the recorder can subscribe

`AGENTS.md` (the schema) and the framework ADR auto-load via the project `CLAUDE.md` symlink.

## Sharp edges to remember

- **No pushing to `main` directly** — workspace hook blocks it. Bootstrap exception was one-time. PRs merge through `gh pr merge`.
- **macOS only shows the Input Monitoring consent prompt once per app-bundle/user pair.** If you've already clicked Allow or Deny on a prior build, the granted/denied state is cached and `IOHIDRequestAccess` returns immediately. To re-test the undetermined-state path, either change the bundle ID or reset privacy via `tccutil reset ListenEvent com.noelferrer.Diktador`.
- **macOS `Press 🌐 to` setting must be "Do nothing"** for bare-Fn push-to-talk to work without firing Apple's globe action. Documented in `wiki/howtos/first-run-setup.md`.
- **NSEvent monitor handles aren't ARC-managed.** The `unregister` path and the new `deinit` both call `NSEvent.removeMonitor`. If a future caller drops the registry without unregistering first, `deinit` is the safety net.
- **SwiftPM identity collision** — local-package directory name lowercased = identity. If it matches a transitive dep's URL identity, `swift package resolve` silently fails. Fix: rename the consuming directory. (See `modules/diktador-hotkey/README.md` for the full case.)
- **APFS case-insensitivity** — `Hotkey.swiftmodule` vs `HotKey.swiftmodule` collapse to the same file, overwriting our build output. Same family of fix.
- **`HotKey.Key` qualifier ambiguity** — `HotKey` exports both a class and an enum at module scope, so the qualifier is ambiguous. Workaround already in `KeyCombo.swift`: `@_exported import enum HotKey.Key`.
- **Xcode is required for any Swift app build** — Command Line Tools alone don't have `xcodebuild`. Currently installed: Xcode 26.4.1 (licensed).
- **Workspace `/go` skill** at `.claude/skills/go/SKILL.md` is the ship cycle. Used for PR #3 (Phase H2–H4 in the plan map onto /go's Phases 1–3); the post-ship `log.md` + `memory/daily/` updates land as Phase 4 hygiene.
- **`/simplify` 3-agent convergence pattern**: when reuse + efficiency or quality + efficiency flag the same finding, that's high signal and worth fixing. Single-agent flags are usually defensible-as-is.
- **`pushToTalkToken`** in `AppDelegate` is held for hygiene but never read in v1. The settings module will read + unregister + re-register when the user changes the trigger.

## Auto-memory note

Nothing user-facing changed in user-level auto-memory this session. The workspace memory under `memory/` is the canonical record of project state.
