---
type: index
created: 2026-04-25
updated: 2026-04-27
---

# Index

The catalog of every page in the wiki. Read this first when answering a query — it is how you find relevant pages without scanning everything.

Update on every ingest, every `document` operation, every filed query, and every lint pass. Keep entries to one line.

This wiki documents two things in parallel:

1. **Diktador** — the dictation app being built in this workspace (decisions, modules, features, howtos, FAQs). Compounds toward a future docs/SaaS site.
2. **The wiki layer itself** — meta-pages about the LLM-wiki pattern this workspace operates under. Smaller, slower-moving section.

---

## Decisions (2)

- [[decisions/framework-choice]] — Swift + SwiftUI + WhisperKit, macOS-only. Replaces prior Tauri assumption. | 2026-04-26
- [[decisions/hotkey-modifier-only-trigger]] — Bare-modifier triggers (Fn for v1) via NSEvent global monitor; Input Monitoring permission required. | 2026-04-27

## Modules (0)

_None yet. One page per module under `modules/<name>/`, written when the module is built._

## Features (0)

_None yet. User-facing features (push-to-talk, hotkey config, model selection, output target, etc.) get filed here as built._

## Howtos (1)

- [[howtos/first-run-setup]] — Grant Input Monitoring + disable the macOS globe-key action. | 2026-04-27

## FAQ (0)

_None yet._

## Sources (1)

- [[sources/llm-wiki-pattern]] — The founding manifesto: argues for compiled, persistent wikis over RAG. | 2026-04-25

## Entities (2)

- [[entities/vannevar-bush]] — American engineer; proposed the Memex (1945). _stub_
- [[entities/memex]] — Bush's hypothetical personal knowledge device; conceptual ancestor of hypertext. _stub_

## Concepts (3)

- [[concepts/compounding-knowledge]] — The thesis that knowledge bases should accumulate, not just store. _stable_
- [[concepts/retrieval-augmented-generation]] — Standard "chat with documents" pattern; the foil this wiki argues against. _stub_
- [[concepts/associative-trails]] — Bush's term for user-curated paths through documents; ancestor of hypertext links. _stub_

## Synthesis (0)

_None yet._

## Queries (0)

_None yet._

## Stubs / TODO

Pages that exist as stubs and want filling, plus pages that probably should exist but don't yet.

- [[entities/vannevar-bush]] — needs primary-source biography. Suggested ingest: Bush's 1945 essay *As We May Think*.
- [[entities/memex]] — needs the original framing from *As We May Think*.
- [[concepts/associative-trails]] — sharper definition needed from the primary source.
- [[concepts/retrieval-augmented-generation]] — corroborate "where RAG still wins" section with a second source.
- _Proposed_: page on **Obsidian** as the user-facing front-end (mentioned in [[sources/llm-wiki-pattern]] but not yet a page).
- _Proposed_: page on **fan wikis as exemplars** (Tolkien Gateway, Memory Alpha) — referenced in [[sources/llm-wiki-pattern]].
- _Proposed_: synthesis page **personal-knowledge-bases** once a second comparable source enters.
- _Proposed_: entity page on **typr** ([[entities/typr]]) — load-bearing across the workspace (architecture reference, even after the framework swap).
- _Proposed_: entity page on **WhisperKit** ([[entities/whisperkit]]) — referenced from [[decisions/framework-choice]]; promote to entity when a second page references it.
- _Proposed_: entity page on **Swift / SwiftUI / AVFoundation / CGEvent** — same rule, create when a second page references each.
- _Proposed_: entity page on **Groq** — same rule.
- _Proposed_: concept page on **dictation-latency-budget** — STT dominates total latency; framework overhead is ~10–20% of the budget. Referenced in [[decisions/framework-choice]] alternatives section.
- _Dropped_: entity page on **Tauri** — was proposed under the prior assumption; no longer load-bearing after the Swift decision.
