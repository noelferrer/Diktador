# Wiki Log

Append-only chronological record. Every entry begins with `## [YYYY-MM-DD] <op> | <title>` so the log stays grep-able.

`<op>` is one of: `ingest`, `document`, `query`, `lint`, `meta`.

---

## [2026-04-25] meta | Wiki initialized
- Schema written to AGENTS.md (mirrored to CLAUDE.md, GEMINI.md via symlinks)
- Prior Diktador agentic schema archived at .archive/agents-diktador-2026-04-25.md
- Folders scaffolded: raw/{articles,papers,notes,books,assets}, wiki/{sources,entities,concepts,synthesis,queries}
- Created: wiki/index.md, log.md
- Vault is already an Obsidian vault (.obsidian/ present) — wikilinks and graph view ready out of the box

## [2026-04-25] meta | Schema retargeted to Diktador app
- Workspace pivoted from pure-research wiki to **Diktador** (local desktop dictation app, modeled after albertshiney/typr).
- AGENTS.md rewritten: dropped the prior "research-only" framing; added project context (Tauri 2 + TS+Vite, free/local-first), folder shape with src/, src-tauri/, core/, modules/, six modular-construction rules, module-README convention, and a fourth wiki op `document` (ADRs / module specs / features / howtos / FAQs) so the wiki compounds toward a future SaaS docs site.
- Existing wiki pages preserved (LLM-wiki-pattern source + meta concepts) — they document the wiki layer itself, not Diktador.
- Updated: AGENTS.md, log.md, wiki/index.md, memory/project_llm_wiki.md.

## [2026-04-25] ingest | LLM Wiki Pattern (idea file)
- Source: raw/notes/llm-wiki-pattern.md
- Created: wiki/sources/llm-wiki-pattern.md
- Created: wiki/entities/vannevar-bush.md (stub), wiki/entities/memex.md (stub)
- Created: wiki/concepts/compounding-knowledge.md (stable), wiki/concepts/retrieval-augmented-generation.md (stub), wiki/concepts/associative-trails.md (stub)
- Updated: wiki/index.md
- Notes: Filed as the founding manifesto of this vault. Three stubs flagged for follow-up by ingesting Bush's 1945 essay *As We May Think* as a primary source.
- Open questions surfaced: scale-limit of index-file approach; line between filed-query and ephemeral chat; how to preserve Bush's "trail-centric" emphasis vs. drifting to document-centric structure.

## [2026-04-26] document | ADR — Framework: Swift + WhisperKit, macOS-only
- Created: wiki/decisions/framework-choice.md (status: stable)
- Updated: wiki/index.md (Decisions section now has 1 entry; "Stubs / TODO" updated — typr/WhisperKit/Groq/etc. proposed as entity stubs; Tauri dropped from proposed)
- Decision: Swift / SwiftUI menu bar app, macOS 14+, WhisperKit (Core ML / Neural Engine) as default STT with Groq HTTPS as user-selectable alternative; soffes/HotKey for hotkey; hybrid clipboard-paste + CGEvent fallback for text injection; Keychain for the Groq API key.
- Reverses the prior Tauri 2 + TypeScript + Vite assumption inherited from typr-main/. typr-main/ retained as conceptual reference (dual-backend STT pattern, settings shape, UX) but its code is not reused.
- Open questions filed in the ADR: WhisperKit model default (tiny/base/small) — pick on first measurement; hotkey default (Right-Option proposed); Groq model selection.
- Knock-on workspace edits applied in same PR: AGENTS.md (stack line + folder shape + module rule 4 generalized for Swift); .claude/skills/go/SKILL.md (test matrix + intro + .gitignore guidance + secret-check); memory/general.md (Project shape + Decisions log).

## [2026-04-26] meta | Hotkey module shipped — PR #2
- PR: https://github.com/noelferrer/Diktador/pull/2 (feat/hotkey-module → main)
- Modules touched: modules/diktador-hotkey/ (new); Diktador/ app target (new)
- Plan executed: docs/superpowers/plans/2026-04-26-xcode-scaffold-and-hotkey-module.md (8 phases A–H, all done)
- Tests run: xcodebuild Debug + Release BUILD SUCCEEDED; swift test 3/3 XCTest cases pass; computer-use verification (user-driven) confirmed Option+Space → menu bar icon flips between mic/mic.fill and menu label between idle/listening
- Simplify changes: 3 findings fixed (Entry struct redundant closures dropped; AppDelegate menu titles deduped into static constants; test extensions collapsed into single class body); plus minor comment trims
- Naming deviations from plan (forced by upstream bugs): module identity DiktadorHotkey not Hotkey; package directory modules/diktador-hotkey/ not modules/hotkey/. Cited SwiftPM #8471 and #7931. Documented in plan top-of-file naming note + README.
- v1 hotkey: Option+Space (Whisper Flow's classic default). F13 swapped during Phase G after the user reported they don't have F13.
- Deferred (filed in memory/domains/hotkey.md): bare Fn-key trigger (next PR — needs NSEvent.addGlobalMonitorForEvents + Input Monitoring permission); right-side modifiers; conflict detection; user-configurable trigger (settings module).
- Bootstrap note: Xcode.app installation by the user was a one-time prerequisite for ANY phase; resolved mid-flow.

## [2026-04-26] document | First implementation plan — Xcode scaffold + hotkey module
- Created: docs/superpowers/plans/2026-04-26-xcode-scaffold-and-hotkey-module.md
- New convention: implementation plans live in docs/superpowers/plans/ (skill default; matches typr-main precedent). Not yet enshrined in AGENTS.md — will land if/when a second plan accumulates.
- Plan covers 8 phases (A-H): branch prep, Xcode menu-bar scaffold, hotkey Swift Package, TDD for HotkeyRegistry (3 unit tests), wire-to-icon, README + memory domain, computer-use verification, ship via /go.
- Deliberate deferrals tracked in the plan and memory/domains/hotkey.md (created by plan task F2): Right-Option-vs-plain-Option, F13-less keyboard fallback, hotkey conflict detection.
- Plan blocks on PR #1 merging before Phase A can begin (so the workspace schema is on main).

## [2026-04-26] meta | Initial ship — workspace bootstrap PR
- PR: https://github.com/noelferrer/Diktador/pull/1 (feat/initialize-workspace → main)
- Repo: https://github.com/noelferrer/Diktador (initialized; main has just .gitignore; feature branch carries everything else)
- Modules touched: none (no app code yet)
- Tests run: wiki/memory/docs verification — every active wikilink resolves to an existing file; symlinks (CLAUDE.md, GEMINI.md → AGENTS.md) preserved at mode 120000
- Simplify changes: 5 stale Tauri/JS references in .claude/skills/go/SKILL.md + memory/memory.md updated to Swift/Xcode/WhisperKit equivalents; one stale open question in memory/daily/2026-04-26.md marked resolved
- Notes: bootstrap required a one-time manual `git push -u origin main` from the user since the workspace hook blocks automated pushes to main (correctly enforcing /go's own rule). Future /go runs use feat/* → main exclusively and never trigger the hook.

## [2026-04-26] meta | Schema audit + memory system + workspace /go skill
- Updated AGENTS.md:
  - Added Whisper Flow + Glaido as UX/feature reference points alongside typr (technical scaffold).
  - Added repo URL: https://github.com/noelferrer/Diktador.git.
  - Folder shape now includes `memory/` (operational working memory) and `.claude/skills/` (workspace skills).
  - Renamed "Three layers" → "Four layers" (App / Wiki / Memory / Schema).
  - New section "Memory system": 6-level architecture (Levels 1–2 implemented; 3–6 deferred), commands ("reorganize memory", "summarize today's work into memory", "promote recurring items"), wiki↔memory promotion rules, and the three-memory-layer distinction (workspace memory vs user auto-memory vs wiki).
  - Updated `Don't` rule to distinguish workspace `memory/` from user auto-memory.
- Created: memory/memory.md (index), memory/general.md, memory/daily/2026-04-26.md
- Created: memory/domains/ memory/tools/ memory/daily/ (empty)
- Created: .claude/skills/go/SKILL.md — workspace override of the global /go. Adds Phase 0 bootstrap (git init + remote add for https://github.com/noelferrer/Diktador.git), Tauri-specific test matrix (cargo + Vite + computer-use for hotkey/native), and Phase 4 post-ship hygiene (log.md + memory/daily append).
- Levels 3–6 of memory architect spec NOT enabled (Memsearch, MemPalace, OpenBrain, Mem0). Session-start hook NOT wired up — user already has user-level auto-memory loading.
- No contradictions surfaced.

## [2026-04-27] document | ADR — Hotkey modifier-only trigger via NSEvent
- Created: wiki/decisions/hotkey-modifier-only-trigger.md (status: stable)
- Created: wiki/howtos/first-run-setup.md
- Updated: wiki/index.md (Decisions 1→2; Howtos 0→1)
- Decision: bare-modifier triggers (Fn for v1) live on a parallel NSEvent global-monitor path inside HotkeyRegistry. Carbon Events stays for keyed combos. Input Monitoring permission surfaces through a new InputMonitoringStatus enum and registry getters. Right-side modifiers deferred to a separate PR.
- Open questions filed in the ADR: right-modifier API shape (sided variant of KeyCombo.modifiers vs new enum); conflict detection still v2.

## [2026-04-27] meta | Fn-key trigger shipped — PR #3
- PR: https://github.com/noelferrer/Diktador/pull/3
- Modules touched: modules/diktador-hotkey/ (new files: ModifierTrigger, InputMonitoringStatus, PermissionProvider; HotkeyRegistry extended; tests +3); Diktador/ app target (AppDelegate rewired)
- Plan executed: docs/superpowers/plans/2026-04-27-hotkey-fn-trigger.md (8 phases A–H, all done)
- Tests run: xcodebuild Debug + Release BUILD SUCCEEDED; swift test 8/8 cases pass; computer-use verification confirmed bare-Fn press flips the menu bar icon between mic and mic.fill, the denied-state path surfaces the warning icon + Open Input Monitoring settings… menu item, and the globe-key sanity path confirmed the Press 🌐 to: Do nothing user setup is required.
- Simplify changes: 8 findings adopted in commit d58a5e7 — AppDelegate image-factory dedupe (templateSymbol helper) + static var → static let; AppDelegate menu-item caching (statusRowItem + openSettingsItem) with double-insert guard; HotkeyRegistry construct ModifierMonitorEntry once with handles populated; HotkeyRegistry drop "— unchanged from PR #2" + WHAT-only doc comment on internal init; HotkeyRegistry one-line invariant comment naming global-vs-local non-overlap; HotkeyRegistry deinit removes still-registered NSEvent monitors; HotkeyRegistry handleFlagsChanged extracts callback to local var before invoke; tests rename test_modifierTrigger_isHashableAndDistinguishesCases → test_modifierTrigger_isHashable.
- Naming deviations from plan: none.
- Notes: AppDelegate push-to-talk swapped from Option+Space to bare Fn. Option+Space dropped from v1 default; settings module will reintroduce user choice.
- Required user setup documented in wiki/howtos/first-run-setup.md: System Settings → Keyboard → Press 🌐 to: Do nothing.

## [2026-04-27] document | ADR — Recorder capture pipeline + module page
- Created: wiki/decisions/recorder-capture-pipeline.md (status: stable)
- Created: wiki/modules/recorder.md
- Created: memory/domains/recorder.md
- Updated: wiki/index.md (Decisions 2→3; Modules 0→1)
- Decision: v1 recorder is pure capture (no VAD); in-process AVAudioConverter to 16 kHz mono Float32; WAV-to-disk at ~/Library/Application Support/Diktador/recordings/. Test seam = MicrophonePermissionProvider + AudioEngineDriver protocols. AppDelegate chains Microphone permission after Input Monitoring. AVAudioEngineDriver hops tap to main to honor the recorder's documented main-thread contract.
- Open questions filed in the ADR + memory note: VAD integration (transcriber-PR concern); streaming chunks (transcriber-PR concern); multi-input device selection (settings-module concern); retention policy (settings-module concern); SampleRateConverter test seam (deferred unless needed).

## [2026-04-27] meta | Recorder module shipped — PR #4
- PR: <fill in URL after gh pr create>
- Modules touched: modules/diktador-recorder/ (new package: Recorder, RecordingResult, MicrophonePermissionStatus, RecorderError, MicrophonePermissionProvider, AudioEngineDriver, SampleRateConverter, WAVWriter; tests +9); Diktador/ app target (AppDelegate dual-permission bootstrap + recording on Fn press/release + Last Recording menu item); project.yml + Diktador.xcodeproj/ (new package dep).
- Plan executed: docs/superpowers/plans/2026-04-27-recorder-module.md (9 phases A–I, all done)
- Tests run: xcodebuild Debug + Release BUILD SUCCEEDED; swift test 9/9 cases pass; computer-use verification confirmed bare-Fn hold records audio, "Last recording: X.Xs — Reveal in Finder" appears in the menu, and QuickLook playback of the WAV plays the user's voice.
- Simplify changes: <fill in after /simplify pass>
- Notes: VAD deferred to transcriber PR. AppDelegate now requests Microphone permission on first launch after Input Monitoring resolves to .granted. Tap callback hopped to main to make the recorder's main-thread-only contract real.
- Required user setup unchanged: System Settings → Keyboard → Press 🌐 to: Do nothing (from PR #3); plus Allow on the new Microphone consent prompt.
