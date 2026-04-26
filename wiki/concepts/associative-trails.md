---
type: concept
created: 2026-04-25
updated: 2026-04-25
sources: [sources/llm-wiki-pattern]
tags: [knowledge-management, computing-history]
status: stub
---

# Associative Trails

Term from [[entities/vannevar-bush]]'s 1945 description of the [[entities/memex]]. A trail is a user-curated path through documents in a personal knowledge store, recording the connections the user finds important. Trails are first-class artifacts — they persist, can be shared, and become as valuable as the documents themselves.

Conceptual ancestor of the hypertext link, but with a stronger emphasis on **the path** than the individual link.

## Why it matters here

[[sources/llm-wiki-pattern]] frames the LLM Wiki as a modern realization of associative trails: wikilinks between markdown pages, maintained automatically by the LLM, are the trails. The connections between pages — backlinks, the graph view in Obsidian, the cross-references in synthesis pages — are the trails made browsable.

## How a trail-centric mindset shapes wiki maintenance

- Linking is not decoration. The first time an entity or concept appears on a page, it gets a wikilink.
- Synthesis pages exist to formalize trails — they're the user's "I followed this thread of reasoning across these sources" made permanent.
- Orphan pages (no inbound links) are a lint signal: a node with no trail running through it isn't doing knowledge-work.

## Open questions

- The original 1945 essay distinguishes trails from a mere collection of links. What's the operational difference, and how should that show up in this wiki? (Answer requires ingesting the primary source.)
- Should the wiki maintain explicit "trail" pages — sequences of pages meant to be read in order — or is the implicit graph enough?

## Mentioned in

- [[sources/llm-wiki-pattern]]

## Related

- [[entities/vannevar-bush]]
- [[entities/memex]]
- [[concepts/compounding-knowledge]]
