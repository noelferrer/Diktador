---
type: concept
created: 2026-04-25
updated: 2026-04-25
sources: [sources/llm-wiki-pattern]
tags: [knowledge-management, thesis, foundational]
status: stable
---

# Compounding Knowledge

The thesis that a knowledge base should **accumulate understanding** as new sources arrive — not just store them. Each new source is read, integrated into existing pages, and used to update the running synthesis. Cross-references, contradictions, and higher-order claims are computed once when a source enters and persist across all future queries, rather than being rediscovered every time a question is asked.

Central thesis of [[sources/llm-wiki-pattern]] and the operating principle of this vault.

## Why it matters

The naive alternative — [[concepts/retrieval-augmented-generation]] — has no notion of accumulation. Every query is answered against raw chunks. A subtle question that depends on synthesizing five documents requires the LLM to find and piece together fragments from scratch on every ask. Nothing is built up.

A compounding system inverts this: the synthesis is computed *during ingest*, not during query. The wiki page about an entity already reflects every source that has mentioned it. The contradiction between two sources has already been flagged. The query just reads the current state.

## What enables it now

- **Maintenance cost approaches zero.** Touching 15 pages per ingest was unworkable for a human; an LLM does it without complaint. This is the unblock.
- **Markdown + wikilinks is enough.** No vector store, no specialized infrastructure required for moderate scale (~hundreds of pages).
- **Schemas can be co-evolved.** The user and LLM agree on conventions in a config file (this vault's `AGENTS.md`); the LLM enforces them automatically.

Per [[sources/llm-wiki-pattern]]: *"Humans abandon wikis because the maintenance burden grows faster than the value. LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass."*

## How it shows up in practice

- **Ingest**: a new source touches 5–15 pages, not 1.
- **Query**: answers come from already-synthesized pages, with citations back to source pages.
- **Filed queries**: when a question forces real synthesis, the answer is filed as a new page so the next query can build on it.
- **Lint**: periodic sweeps surface contradictions and gaps so the wiki self-corrects.

## Tensions

- **Pre-compilation is lossy.** The LLM's interpretation of a source at ingest time becomes the canonical representation. Nuances not captured then are hard to recover later. Mitigated by keeping the raw source immutable and re-readable.
- **Schema lock-in.** Once enough pages follow a structure, changing it costs work. The schema co-evolution discipline is meant to slow drift.
- **At very large scale** the index-file approach breaks down. [[sources/llm-wiki-pattern]] notes this and suggests CLI search tools as an escape hatch.

## Mentioned in

- [[sources/llm-wiki-pattern]]

## Related

- [[concepts/retrieval-augmented-generation]] — the foil
- [[concepts/associative-trails]] — Bush's earlier articulation of the same instinct
- [[entities/memex]] — the un-built ancestor
