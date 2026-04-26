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
