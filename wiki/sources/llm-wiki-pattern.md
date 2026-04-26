---
type: source
created: 2026-04-25
updated: 2026-04-25
source: raw/notes/llm-wiki-pattern.md
tags: [meta, foundational, knowledge-management]
status: stable
---

# LLM Wiki Pattern (idea file)

The founding manifesto for this vault. An abstract pattern document arguing that LLMs should **incrementally compile** knowledge into a persistent wiki rather than performing retrieval over raw documents on every query. Designed to be pasted into any LLM agent (Claude Code, Codex, etc.) so the agent and user can co-instantiate the pattern for a specific domain.

## Key claims

- **The compounding artifact thesis.** A persistent, LLM-maintained wiki accumulates knowledge across sources; standard [[concepts/retrieval-augmented-generation]] systems re-derive understanding on every query and never accumulate. ([[sources/llm-wiki-pattern]])
- **Bookkeeping is the bottleneck, not reading.** Wikis fail when humans maintain them because cross-references, contradiction-flagging, and consistency upkeep grow faster than the value. LLMs do that work at near-zero cost. This is the core insight enabling [[concepts/compounding-knowledge]].
- **Three layers separate concerns.** Raw sources (immutable), wiki (LLM-owned, mutable), schema (the agreement between user and LLM about how the wiki is organized). The schema co-evolves with the user.
- **The user curates; the LLM maintains.** The human's job is sourcing, exploration, asking good questions. The LLM's job is summarizing, cross-referencing, filing, contradiction-flagging.
- **Obsidian as the front-end.** The wiki is a folder of markdown with wikilinks; the LLM edits, the user browses. The graph view and link backlinks are the navigation primitives.
- **Three operations.** Ingest (process a new source, touch many pages), query (search the wiki, optionally file the answer back), lint (periodic health check for contradictions, orphans, gaps).
- **The Memex was right; the missing piece was the maintainer.** [[entities/vannevar-bush]]'s 1945 [[entities/memex]] vision described private, actively curated knowledge with associative links between documents. He couldn't solve who maintains the trails. The LLM handles that.

## Notable quotes

> "The wiki is a persistent, compounding artifact. The cross-references are already there. The contradictions have already been flagged. The synthesis already reflects everything you've read."

> "Obsidian is the IDE; the LLM is the programmer; the wiki is the codebase."

> "Humans abandon wikis because the maintenance burden grows faster than the value. LLMs don't get bored."

## Connections

- Foil: [[concepts/retrieval-augmented-generation]] — what this pattern argues *against*.
- Central concept: [[concepts/compounding-knowledge]] — the thesis the pattern hinges on.
- Historical antecedent: [[entities/vannevar-bush]] / [[entities/memex]] / [[concepts/associative-trails]].
- Suggests tooling: Obsidian Web Clipper, Marp, Dataview, qmd (search engine for markdown).

## Open questions

- At what scale (page count) does the index-file approach break down and force migration to a real search engine?
- How should the schema evolve when multiple ingest sub-styles emerge (deep-read papers vs. quick-clip articles vs. transcripts)?
- Where's the right line between filing a query as a wiki page vs. letting it stay ephemeral chat?

## Suggested next investigations

- Bush's original 1945 essay "As We May Think" — primary source for the [[entities/memex]] page.
- Concrete examples of fan wikis (Tolkien Gateway, MemoryAlpha) as reference for tone and structure.
- The qmd search tool — worth evaluating once this wiki has 50+ pages.
