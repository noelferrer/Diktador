---
name: go
description: Diktador ship-it workflow. Use when the user types /go, says "ship it", "let's go", "wrap it up", or signals a chunk of dictation-app work is done and they want it tested, simplified, and pushed as a PR to https://github.com/noelferrer/Diktador.git. Runs three phases — end-to-end test (bash / browser / computer use depending on surface), /simplify pass, then PR — in order without asking between phases. Handles workspace bootstrap (git init + remote) on first run.
---

# /go — Test, Simplify, Ship (Diktador)

The user has finished a chunk of work and wants it shipped. Run the three phases **in order, without pausing between them**. Do not ask "ready for phase 2?" — just go. If a phase fails, stop and report.

This is the **Diktador-specific** override of the global `/go`. Differences from the global version:

- Repo target is fixed: `https://github.com/noelferrer/Diktador.git`
- Workspace may not be a git repo yet on first invocation — bootstrap if needed
- Test matrix is tuned for a native macOS Swift / SwiftUI dictation app with WhisperKit, hotkey, and text injection (see [the framework ADR](../../../wiki/decisions/framework-choice.md))
- After shipping, append to `log.md` (`meta` op) and `memory/daily/<today>.md` per workspace conventions

---

## Phase 0 — Workspace bootstrap (first run only)

Before testing, ensure the repo is in a state that can produce a PR:

```bash
cd "/Users/user/Desktop/Aintigravity Workflows/Diktador"
git rev-parse --git-dir 2>/dev/null
```

If this fails (no git repo yet):

1. Confirm with the user: "Workspace isn't a git repo yet. Initialize, set remote to `https://github.com/noelferrer/Diktador.git`, and proceed?" — wait for yes.
2. On confirmation:
   ```bash
   git init
   git remote add origin https://github.com/noelferrer/Diktador.git
   ```
3. Verify a sensible `.gitignore` exists (or create one covering: `.tmp/`, `.DS_Store`, `.env`, `build/`, `DerivedData/`, `.build/`, `.swiftpm/`, `xcuserdata/`, `*.xcuserstate`).
4. Create an initial branch — never commit straight to `main` for `/go` work. Use `feature/<short-slug>` derived from what changed, or ask the user.

If the repo exists but the current branch is `main` / `master`: stop and ask which branch name to use. Do not push to main directly.

If the remote `origin` does not point to `https://github.com/noelferrer/Diktador.git`: stop and ask before retargeting.

---

## Phase 1 — End-to-end test

**Goal:** verify the work actually works, beyond what type-checks and unit tests prove.

First, figure out what changed:

```bash
git status
git diff --stat
git log --oneline origin/$(git symbolic-ref --short HEAD 2>/dev/null || echo main)..HEAD 2>/dev/null || git log --oneline -10
```

Pick the right test method by surface. **`xcodebuild` succeeding is not "tested" — it's compiled.**

| What changed | How to test |
|---|---|
| Swift modules (audio capture, transcriber dispatch, hotkey registration, output, settings) | **Bash** — `xcodebuild test -scheme Diktador -destination 'platform=macOS'` for the affected target. For audio/STT modules, run the module's integration test that feeds a known WAV and asserts on transcription. |
| SwiftUI settings window, menu bar UI, onboarding screens | **Computer use** — open the built app, drive the menu bar / settings window, screenshot, verify visual state. SwiftUI previews don't count. |
| Hotkey registration, text injection at cursor, microphone capture, Accessibility / mic permissions UX | **Computer use** — drive the actual built `.app`. Hold the configured hotkey, dictate a short phrase, verify text lands in a target app (TextEdit, browser URL bar). This cannot be faked with bash. |
| Module under `modules/<name>/` | **Bash** — run that module's XCTest target. Every module README declares its test scheme in "Public API" or near it. |
| Wiki / memory / docs only | No code test needed. Verify markdown renders (`grep -rn '\[\[[^]]*\]\]'` to enumerate wikilinks, then check each target exists in `wiki/`). |
| Mixed | Test each surface separately. Don't skip the boring one. |

Test the **golden path** plus at least one **edge case** for whatever changed (empty audio buffer, denied mic permission, hotkey already taken, no internet for cloud-fallback STT, etc.). For UI: monitor adjacent features for regressions — a fix in the recorder shouldn't break the hotkey config screen.

If you cannot test something (no signing cert for packaging, no test fixtures, dev environment unavailable): **say so explicitly** in the report. Do not silently skip.

Capture evidence as you go: command output snippet, screenshot path, or a one-line note of what you verified. This goes into the PR body.

If a test fails: fix it, retest, then continue. Don't proceed with broken work. If a fix is non-trivial, consider whether it's still scoped to "this chunk of work" or whether the scope just expanded — flag to user if the latter.

---

## Phase 2 — /simplify

Invoke the `simplify` skill:

```
Skill(skill="simplify")
```

Let it run. It reviews changed code for reuse, quality, and efficiency, and fixes issues it finds.

After it returns:

1. `git status` / `git diff` to see what it changed.
2. If it touched code that Phase 1 exercised, re-run only that test. Skip if changes are cosmetic only.
3. Note any non-trivial changes for the PR body.

---

## Phase 3 — PR

Use the standard PR creation flow described in the system prompt's "Creating pull requests" section. Diktador-specific notes:

1. **Stage focused commits.** If both Phase 1 (fix-from-testing) and Phase 2 (simplify pass) made changes, separate them into two commits. Don't lump everything into one "/go: ship" blob.
2. **Push the branch:**
   ```bash
   git push -u origin <branch-name>
   ```
3. **Create the PR** with `gh pr create`. Title under 70 chars. Body must include:
   - **Summary** — 1–3 bullets of what changed and why (terse, encyclopedic voice — matches the workspace's wiki tone)
   - **Modules touched** — list of `modules/<name>/` affected (helps with fault isolation per the six modular rules)
   - **Test plan** — what you actually verified in Phase 1, with evidence (command output snippet, screenshot path, or "verified by clicking through X → Y → Z"). A record of what passed, **not** a TODO checklist of unrun tests.
   - **Simplify pass** — one line on what `/simplify` changed, or "no changes" if it was a no-op
   - **Wiki / memory updates** — list of `wiki/` or `memory/` files touched, if any (this workspace ships docs alongside code)

4. **Return the PR URL.**

---

## Phase 4 — Post-ship workspace hygiene

After the PR is up, before reporting done:

1. Append to `log.md` with a `meta` entry summarizing the ship:
   ```
   ## [YYYY-MM-DD] meta | <PR title>
   - PR: <url>
   - Modules touched: …
   - Tests run: …
   - Simplify changes: …
   ```
2. Append to `memory/daily/<YYYY-MM-DD>.md` (create the file if today's note doesn't exist) under a `## Done` heading.
3. If a module's behavior changed, verify its `modules/<name>/README.md` "Known failure modes" reflects anything new diagnosed during testing. If a design assumption shifted, flag that an ADR should be filed in `wiki/decisions/` (don't auto-file — propose it to the user).

---

## Guardrails

- **Don't push to `main`.** `/go` always creates / pushes a feature branch.
- **Don't `--force` push.** If push is rejected, investigate (likely upstream changed) before doing anything destructive.
- **Don't skip hooks.** If a pre-commit hook fails, fix the underlying issue and create a new commit. Never `--no-verify`.
- **Don't merge the PR.** Stop at "PR created and URL returned." Merging is the user's call.
- **Don't retarget the remote** without confirmation. The remote is fixed at `https://github.com/noelferrer/Diktador.git`; if it's pointing somewhere else, ask before changing.
- **Don't commit secrets.** Verify `.env` is gitignored and not staged. Verify no `build/`, `DerivedData/`, `.build/`, or `*.xcuserstate` artifacts are staged. Groq API keys live in Keychain — never in repo.
- **If there are no changes to ship** (clean working tree, branch identical to remote): say so and stop. No empty PRs.

## Reporting

End-of-turn: one or two lines. What was tested, what `/simplify` did, PR URL. That's it. No throat-clearing, no recap of the rules.
