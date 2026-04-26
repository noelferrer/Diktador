---
type: concept
created: 2026-04-25
updated: 2026-04-25
sources: [sources/llm-wiki-pattern]
tags: [llm, knowledge-management, foil]
aliases: [RAG]
status: stub
---

# Retrieval-Augmented Generation (RAG)

Standard pattern for grounding LLM output in a document corpus: at query time, the system retrieves relevant chunks (typically by vector similarity) and stuffs them into the prompt. The model then generates an answer based on those chunks. Used by NotebookLM, ChatGPT file uploads, and most production "chat with your documents" systems.

## How it works (sketch)

1. Documents are chunked and embedded into a vector index up front.
2. User asks a question; the question is embedded.
3. The system retrieves the top-k chunks by similarity.
4. Those chunks are inserted into the prompt as context.
5. The LLM generates an answer over that context.

## What [[sources/llm-wiki-pattern]] argues against it

- **No accumulation.** Every query starts from raw chunks. The system never builds a higher-level understanding that persists between queries.
- **Synthesis is re-derived.** A question that requires connecting five documents forces the model to find and synthesize those fragments from scratch, every time.
- **Cross-references are implicit and probabilistic.** Connections between documents only exist as similarity scores at retrieval time, not as durable, inspectable links.
- **Contradictions are invisible.** A new document that contradicts older ones produces no flag — they just sit in the index together.

## The contrast it sets up

The [[sources/llm-wiki-pattern]] is not against retrieval per se — it's against retrieval as the *only* layer. The proposed alternative compiles knowledge into a maintained wiki ([[concepts/compounding-knowledge]]), which can then itself be retrieved over. The wiki is the durable artifact RAG never produces.

## Where RAG still wins

- Massive corpora (millions of documents) where compilation isn't tractable.
- Frequently changing source data where re-compilation cost exceeds re-retrieval cost.
- Systems where the user genuinely just wants a one-shot answer and accumulating knowledge would be overhead.

(These nuances are not in [[sources/llm-wiki-pattern]] — added here to keep the page balanced. Mark as stub until corroborated by another source.)

## Mentioned in

- [[sources/llm-wiki-pattern]]

## Related

- [[concepts/compounding-knowledge]] — the proposed alternative pattern.
- [[entities/memex]] — historical antecedent of compiled-knowledge thinking.
