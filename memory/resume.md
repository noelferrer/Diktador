---
type: memory-resume
updated: 2026-04-26
session_ended: end-of-day 2026-04-26
---

# Resume point

> Where we left off, what's pending from you, what to do first next session. Read this file *first* on resume — it's the canonical handoff.

## Active state at end of session

- **Branch on disk**: `feat/hotkey-module` (10 commits ahead of `main`).
- **PR #2**: https://github.com/noelferrer/Diktador/pull/2 — **OPEN**, awaiting your review/merge.
- **PR #1** (workspace bootstrap + framework ADR): merged earlier in the session.
- **Working tree**: clean as of last push.
- **Build status**: `xcodebuild` Debug + Release green; `swift test` 3/3 pass.
- **App location** (Release): `~/Library/Developer/Xcode/DerivedData/Diktador-bgxnmdzjhoodkyaftdnhajichfan/Build/Products/Release/Diktador.app` — convenience for ad-hoc launches.

## Pending action from you (do before resuming)

1. **Review and merge PR #2** if the diff looks right: `gh pr merge 2 --squash --delete-branch`, or via the GitHub UI.
2. (After merge) `git checkout main && git pull origin main` so local `main` is synced before the next branch.

The one-time `git push origin main` workspace-hook exception from the bootstrap **does not apply** to this PR — feat→main merges via `gh pr merge` or the UI go through normal review and don't trip the hook.

## What got built this session (skim)

- **PR #1 (merged)** — workspace skeleton: `AGENTS.md` schema, `wiki/`, `memory/` (Levels 1–2 of the architect spec), `.claude/skills/go/SKILL.md`, framework ADR at `wiki/decisions/framework-choice.md`. Stack pivoted from Tauri to **Swift / SwiftUI / WhisperKit, macOS 14+, menu bar app**.
- **PR #2 (open)** — first proper module: `modules/diktador-hotkey/` Swift Package wrapping `soffes/HotKey` into a `HotkeyRegistry` with a token-based API; `Diktador.app` menu bar shell scaffolded via `xcodegen` (from `project.yml`); **Option+Space** push-to-talk wired so the menu bar icon flips between idle and listening; 3 XCTest cases pass.

Full retrospective lives in [`daily/2026-04-26.md`](daily/2026-04-26.md).

## What to do next session — pick one

### Option A — Bare Fn-key trigger PR ⭐ recommended next

The user explicitly asked for the Fn key during Phase G of the previous PR. soffes/HotKey can't reach it (Carbon Events doesn't model Fn as a modifier), so this requires extending `HotkeyRegistry` with a parallel implementation path using `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`. Effort: **~30–60 min**. Probably warrants its own ADR since the public API of the registry materially extends. Same approach unblocks right-side modifiers (Right-Option, Right-Cmd) and surfaces the **Input Monitoring** permission flow that the recorder + output modules will also need.

Open questions filed in [`domains/hotkey.md`](domains/hotkey.md) → Open questions section.

### Option B — Recorder module

`AVAudioEngine` capture + VAD (voice activity detection). The hotkey module already provides the `setListening(true/false)` semantic; `recorder` consumes it to start/stop buffering. First piece of the actual audio pipeline. Module README convention per `AGENTS.md` (Purpose / Public API / Dependencies / Known failure modes).

### Option C — Three modules together (recorder + transcriber + output)

Bigger PR, delivers the "talk → see typed text" UX in one shot. Riskier; not recommended for a first integration.

The user expected dictation-typing-text behavior at end of PR #2 and was reminded that the transcription pipeline doesn't exist yet. **The integration goal of options B + C is exactly that experience.**

## Key files to load on resume (in order)

1. `wiki/index.md` — workspace catalog
2. **This file** — `memory/resume.md`
3. `memory/general.md` — operational facts (env, conventions, current open questions)
4. Last ~10 entries of `log.md` — recent activity
5. If picking Option A: `memory/domains/hotkey.md` (Open questions section is the Fn-key brief)
6. If picking Option B or C: re-read `wiki/decisions/framework-choice.md` to remember the agreed STT pipeline shape (WhisperKit + optional Groq)

`AGENTS.md` (the schema) and the framework ADR auto-load via the project `CLAUDE.md` symlink — you'll see them in context without explicitly reading.

## Sharp edges to remember

- **No pushing to `main` directly** — workspace hook blocks it. Bootstrap exception was one-time. PRs merge through `gh pr merge`.
- **SwiftPM identity collision** — local-package directory name lowercased = identity. If it matches a transitive dep's URL identity, `swift package resolve` silently fails. Fix: rename the consuming directory. (See `modules/diktador-hotkey/README.md` for the full case.)
- **APFS case-insensitivity** — `Hotkey.swiftmodule` vs `HotKey.swiftmodule` collapse to the same file, overwriting our build output. Same family of fix.
- **`HotKey.Key` qualifier ambiguity** — `HotKey` exports both a class and an enum at module scope, so the qualifier is ambiguous. Workaround already in `KeyCombo.swift`: `@_exported import enum HotKey.Key`.
- **Xcode is required for any Swift app build** — Command Line Tools alone don't have `xcodebuild`. Currently installed: Xcode 26.4.1 (licensed). If a future machine doesn't have it, the user must install it before any build phase.
- **Workspace `/go` skill** at `.claude/skills/go/SKILL.md` is the ship cycle. It expects: Phase 0 (branch / git state check), Phase 1 (xcodebuild + swift test + computer-use for native UI), Phase 2 (`/simplify`), Phase 3 (PR), Phase 4 (log + memory hygiene). Computer-use phases are user-driven; everything else can be subagent-orchestrated.
- **`/simplify` skill works on Swift surface**. Usual pattern: Agent 1 (reuse) and Agent 2 (quality) sometimes converge on findings; Agent 3 (efficiency) is often a no-op for non-hot-path code. Don't manufacture findings.

## Auto-memory note

The user-level auto-memory entry at `~/.claude/projects/-Users-user-Desktop-Aintigravity-Workflows-Diktador/memory/project_llm_wiki.md` was updated this session to remove the stale Tauri claim and reflect the Swift/WhisperKit pivot. The MEMORY.md index entry there still says "Local dictation app (Tauri+TS, after albertshiney/typr)" — likely needs a cosmetic update next session if it surfaces. Worth a `/reorganize memory` pass at user level.
