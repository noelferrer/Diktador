# Agent Instructions — Diktador

> Mirrored across CLAUDE.md, AGENTS.md, GEMINI.md (symlinks) so the same instructions load in any AI environment.

## What Diktador is

A local desktop dictation app. Press a hotkey, speak, transcribed text is inserted at the cursor.

- **Reference points**: [Whisper Flow](https://wisprflow.ai) and [Glaido](https://www.glaido.com) for UX and feature targets — what users expect from a polished, modern dictation tool (low-latency transcription, post-processing cleanup, app-aware insertion, command vocabulary). [typr](https://github.com/albertshiney/typr) is a **conceptual reference** for how to wire dual-backend STT (local + cloud) into a dictation app; its code (Tauri/Rust) does not transfer to Diktador's stack but its architecture and UX patterns do. A copy lives at `typr-main/` as read-only reference.
- **Stack** (locked, see [`wiki/decisions/framework-choice.md`](wiki/decisions/framework-choice.md)): **Swift 5.10+ / SwiftUI**, single Xcode project, menu bar app (`LSUIElement`), **macOS 14.0 (Sonoma) minimum**.
- **STT**: [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple Silicon, Core ML / Neural Engine) as default; Groq HTTPS API selectable as an alternative; Groq key in Keychain. Local default keeps the "no cost ever" floor.
- **Hotkey**: [`soffes/HotKey`](https://github.com/soffes/HotKey) Swift package. **Text injection**: hybrid clipboard-paste + CGEvent fallback.
- Built free: open-source first; local STT default; cloud STT optional via free tier.
- Distribution path: personal use → friends → possibly a SaaS site. Mac-only on day 1; Windows is deferred and would be a separate codebase, not a recompile (SwiftUI is not cross-platform). Documentation accumulates from day one toward that future.
- Repo: https://github.com/noelferrer/Diktador.git

## Four layers of this workspace

1. **App code** — the running dictation app. Swift / SwiftUI + feature modules (one Swift target per module).
2. **Wiki** (`wiki/`) — markdown knowledge base. Decisions, module specs, features, howtos, FAQs, external research summaries. Compounds toward a future docs/SaaS site. Public-facing voice.
3. **Memory** (`memory/`) — operational working memory across conversations. Claude's notebook; not user-facing. See "Memory system" below.
4. **Schema** (this file) — the contract between user and LLM about how the workspace is operated. Co-evolves; do not edit without explicit user approval.

## Folder shape

```
Diktador/
├── AGENTS.md                # this file (CLAUDE.md, GEMINI.md are symlinks)
├── log.md                   # chronological append-only log
├── .env / .env.example      # secrets + template (gitignored / safe to commit)
├── .tmp/                    # intermediates, gitignored, regenerable
├── .archive/                # superseded files; reference only
├── typr-main/               # conceptual reference (Tauri/Rust) — read-only; code does not transfer
├── Diktador.xcodeproj/      # Xcode project — added when building starts
├── Diktador/                # main app target sources (Swift + SwiftUI)
├── DiktadorTests/           # XCTest suite
├── core/                    # boilerplate / shared contracts — add when needed, not before
├── modules/                 # feature modules (recorder, transcriber, hotkey, output, settings, ui)
│   └── feature_x/
│       ├── Sources/         # Swift sources; one public entry point (the module's primary type)
│       ├── Tests/           # XCTest target
│       └── README.md        # Purpose | Public API | Dependencies | Known failure modes
├── raw/                     # immutable external sources (articles, papers, notes, books, assets)
├── memory/                  # operational working memory (cross-conversation context)
│   ├── memory.md            # lean index — links to general, domains, tools, daily
│   ├── general.md           # cross-cutting facts, environment, preferences
│   ├── domains/             # one file per topic area (recorder, transcriber, …)
│   ├── tools/               # one file per external tool (whisperkit, swift, xcode, github, …)
│   └── daily/               # YYYY-MM-DD.md session logs; promote stable items upward
├── .claude/                 # workspace-level Claude Code config
│   └── skills/              # workspace skills (override global ones with the same name)
└── wiki/
    ├── index.md             # the catalog — every wiki page listed here
    ├── decisions/           # ADRs: why we picked X over Y
    ├── modules/             # per-module spec/rationale (1:1 with /modules/<name>)
    ├── features/            # user-facing features (push-to-talk, model selection, …)
    ├── howtos/              # operational + future end-user guides
    ├── faq/                 # recurring questions (project-internal + future user)
    ├── concepts/            # technical terms (VAD, STT, beam search, …)
    ├── entities/            # libraries / services / products (Whisper, WhisperKit, Swift, …)
    ├── sources/             # summaries of ingested external sources
    └── synthesis/           # comparisons, evaluations, theses
```

`core/` and subfolders inside `entities/`, `concepts/`, etc. are added only when content warrants. Default is flat.

## Modular construction — six rules

Default to modular. Break a rule only with a documented reason. The goal is **fault isolation**: when something breaks, it must be traceable to one module within seconds.

1. **One feature = one module.** If you can't explain it in one sentence, it's doing too much.
2. **Declare dependencies at the boundary.** Each module states what it needs (other modules, env vars, config, services) at the top of its entry file. Missing dependency = fail at load with a clear message.
3. **Own your errors.** Wrap external-facing functions; catch, log with the module name as prefix, then re-raise with context or return a structured error. No raw library exceptions leaking out.
4. **Public vs private is explicit.** One public surface per module — for Swift modules that means a single primary public type or namespace exposed via the module's Swift target; everything else stays `internal` or `private`. Other modules consume only that public surface — never reach into internals.
5. **No shared mutable state between modules.** Pass data as arguments, or go through a documented store. Never import a variable from another module and mutate it.
6. **One communication style per project.** Direct calls through entry points are the default. Escalate to a registry only when 3+ modules need to discover each other. Escalate to events only when behavior is genuinely async/broadcast. Pick once, document, stick with it.

### Module README

Every module under `modules/` has a `README.md` with exactly:

- **Purpose** — one sentence
- **Public API** — what other modules can call
- **Dependencies** — other modules, env vars, external services
- **Known failure modes** — what breaks it, error signature, how to diagnose

Add to **Known failure modes** every time a new failure is diagnosed. The READMEs compound into a debugging index.

Deeper rationale for a module — design alternatives considered, decisions made, references — lives in `wiki/modules/<name>.md` (frontmatter `type: module`).

## Wiki operations

Four operations: **ingest**, **document**, **query**, **lint**. Every interaction is one of these or a meta-conversation about the schema.

### ingest

User drops something in `raw/` or pastes a URL.

1. Read the source fully.
2. Brief takeaways (3–5 bullets) unless user said "just file it."
3. File summary at `wiki/sources/<slug>.md`.
4. Update affected `entities/`, `concepts/`, and `synthesis/` pages. Create new pages only when significant.
5. Update `wiki/index.md`.
6. Append to `log.md`.

### document

A user decision, module spec, or feature is captured. This is the compounding loop for the future docs site.

- Decision → `wiki/decisions/<slug>.md` (ADR: context, decision, consequences, alternatives).
- Module spec → `wiki/modules/<name>.md` (1:1 with `modules/<name>/`).
- Feature → `wiki/features/<slug>.md`.
- FAQ entry → append to `wiki/faq/<topic>.md`.
- Howto → `wiki/howtos/<slug>.md`.

Always update `wiki/index.md` and append to `log.md`.

### query

User asks a question.

1. Read `wiki/index.md` first.
2. Read relevant pages.
3. Answer with citations (every claim links to its source page).
4. If the answer required real synthesis, file at `wiki/queries/<slug>.md` (or `wiki/synthesis/` if it is a durable thesis). Quick lookups need no filing.
5. If filed: update index, append to log.

### lint

User says "lint" or "health check" (or it has been ~10 ingests/documents since the last one).

Look for: contradictions between pages, stale claims, orphan pages, thin hubs, missing cross-references, concepts mentioned across pages without their own page, open questions never investigated. Report ordered by severity. Don't fix without approval.

## Memory system

Two independent persistence layers, each with a distinct job:

| | `wiki/` | `memory/` |
|---|---|---|
| Audience | future docs site, end users, agents reading the wiki | Claude's working context across conversations |
| Voice | encyclopedic, neutral, dense | operational, shorthand OK |
| Lifetime | permanent (public knowledge) | working (subject to reorganization) |
| Citations | required (wikilinks to sources) | optional |
| Filing rule | one home per concept | indexed but reorganizable |

`memory/` follows a 6-level architecture (after Simon Scrapes' "Every Claude Code Memory System Compared"). **Levels 1–2 are implemented by default**; Levels 3–6 (Memsearch, MemPalace, OpenBrain, Mem0) are off until the user asks.

### Layout

- `memory/memory.md` — lean index. Table-of-contents only; under ~200 lines; link, don't inline.
- `memory/general.md` — cross-cutting facts, environment setup, preferences that span domains.
- `memory/domains/<topic>.md` — one file per topic area (recorder, transcriber, hotkeys, output, packaging, …).
- `memory/tools/<tool>.md` — one file per external tool (whisperkit, swift, xcode, hotkey, groq, github, …).
- `memory/daily/<YYYY-MM-DD>.md` — append-only session logs. Promote stable facts upward to general/domains/tools.

### Memory commands

- **"reorganize memory"** — scan `memory/`, delete empty/trivial files, dedupe overlaps, merge related entries, split overbroad files, normalize headings (`Decisions` / `Open questions` / `Configs`), refresh `memory.md`. Output a checklist of files deleted/merged/split/updated.
- **"summarize today's work into memory"** — write today's `memory/daily/<YYYY-MM-DD>.md` (decisions, new concepts, important bugs, shipped work). Promote durable facts to `general.md` or the relevant domain/tool file and link them from the daily note.
- **"promote recurring items to long-term memory"** — scan recent dailies, surface recurring items, promote to long-term files, mark stale items for archiving.

### Wiki ↔ memory promotion

- A `memory/daily/` note that contains a stable, citable fact about Diktador (a decision, module spec, feature) → promote to `wiki/` per the `document` operation.
- A `wiki/` claim that turns out to be an operational shortcut not worth publishing → demote to `memory/`.
- Never duplicate. The promoted/demoted file replaces, not mirrors.

### Three memory layers — don't confuse them

1. **Workspace memory** (`memory/` here) — shared with anyone who clones this repo. Operational facts about Diktador.
2. **User auto-memory** (`~/.claude/projects/<project-path>/memory/`) — Claude's private cross-conversation memory about the user (preferences, collaboration patterns). Never check this into the repo.
3. **Wiki** (`wiki/` here) — public encyclopedic knowledge.

When in doubt: facts about *the project* go to wiki/ or memory/ (here); facts about *the user* go to user auto-memory.

## Page conventions

### Filenames

Lowercase kebab-case. One concept = one file. Source-summary filenames mirror the source.

### Frontmatter

```yaml
---
type: source | entity | concept | synthesis | query | decision | module | feature | howto | faq
created: 2026-04-25
updated: 2026-04-25
tags: [tag1, tag2]
source: raw/articles/example.md         # source pages only
sources: [...]                           # entity/concept/synthesis: list of cited source pages
status: draft | stable | stub | contested
---
```

`updated` bumps to today's absolute date on every material change.

### Body

Skimmable. Lead with the punchline. H2 sections. Common shapes:

- **Source**: one-paragraph summary, then `## Key claims`, `## Notable quotes`, `## Connections`, `## Open questions`.
- **Entity**: one-line ID, then `## Background`, `## Notable contributions`, `## Mentioned in`, `## Related`.
- **Concept**: one-paragraph definition, then `## How it appears`, `## Tensions / debates`, `## See also`.
- **Synthesis**: thesis up top, evidence, dissents, `## Sources`.
- **Query**: question as H1, answer, `## Sources consulted`, `## Filed because`.
- **Decision (ADR)**: `## Context`, `## Decision`, `## Consequences`, `## Alternatives considered`, `## Sources`.
- **Module**: `## Purpose`, `## Public API`, `## Design decisions` (link relevant ADRs), `## Dependencies`, `## Open questions`.
- **Feature**: `## What it does`, `## How it works` (user-facing), `## Limitations`, `## Related modules`.
- **Howto / FAQ**: question or task as H1, terse answer, `## See also`.

### Linking

Obsidian wikilinks: `[[page-slug]]` or `[[page-slug|display]]`. Link entities and concepts on first appearance per page. Never invent a link target — create a stub or leave unlinked and add to the index's "missing pages" list.

### Citations

Wiki-page factual claims cite the source page at the end of the relevant paragraph: `([[sources/example]])`.

### Tone

Encyclopedic, neutral, dense. No filler, no hedging. Match the prose of a well-edited fan wiki or Wikipedia. These pages are headed for a public docs site — every line earns its space.

## Dev-time vs run-time

**Run-time:** the app is running on the user's machine. Claude is not in the loop unless invoked for a task.

**Dev-time:** building or extending modules, adding a feature, writing a new module spec. Different methodology applies.

A trivial fix (typo, obvious missing import, env var swap) stays run-time. If you'd think about it for more than a minute, it is dev-time.

### Dev-time methodology

When building or materially extending modules, use the Superpowers flow. Invoke skills, don't paraphrase:

1. **`brainstorming`** — pull the real requirement out through questions. Input/output shape, failure modes, simplest version that works. No jumping to code.
2. **`writing-plans`** — break work into 2–5 minute tasks with file paths and verification steps. Show the plan before executing.
3. **`test-driven-development`** — every new module gets tests. "It is just a script" is how scripts grow into 400-line monsters.
4. **`subagent-driven-development`** — for multi-file work. Parallel where independent, serial where not.
5. **`verification-before-completion`** — run the tests, run the module end-to-end, show output. "Should work" is not done.
6. **`systematic-debugging`** — when things break. Reproduce, hypothesize, test, fix, verify. Don't rationalize.

Once code works, **switch back to run-time:** update the module's `README.md`, the matching `wiki/modules/<name>.md`, and any `wiki/decisions/` or `wiki/features/` pages affected.

## Self-annealing loop

When something breaks:

1. Fix it.
2. Update the module.
3. Test it.
4. Update the module's `README.md` "Known failure modes" with error signature and fix.
5. If a design assumption changed, log a new ADR in `wiki/decisions/`.

Material fixes are dev-time.

## When rules conflict

If a Superpowers skill conflicts with this file or the user, **the user wins, then this file, then the skill.** Example: skill says "always TDD"; user says "one-off prototype, skip tests" — follow the user.

## How to use the wiki at session start

When a session opens and the user asks anything beyond a trivial greeting:

1. Read `wiki/index.md` to load context.
2. Skim the last ~10 entries of `log.md` for recent activity.
3. Then engage.

## Don't

- Don't modify `raw/`. Read-only.
- Don't modify `typr-main/`. It is reference material — clone of an external repo.
- Don't modify `.archive/`.
- Don't edit `AGENTS.md` (this file) without explicit user approval. Propose changes, then wait.
- Don't write wiki facts into the user's auto-memory system (`~/.claude/projects/...`). Public/citable facts live in `wiki/`; operational working facts live in `memory/`; user auto-memory is reserved for collaboration patterns and user preferences.
- Don't create a wiki page for every passing mention. If an entity/concept appears once and is not load-bearing, mention it in the source page only.
- Don't paraphrase the same content into multiple wiki pages. Information has one home; other pages link to it.
- Don't silently overwrite a contradicting claim. Flag it: `> ⚠ Earlier sources said X ([[sources/old]]); newer source says Y ([[sources/new]]).`
- Don't generate slide decks, diagrams, charts, or external integrations unless asked. Markdown-first.

## `log.md` format

Append-only. Every entry begins:

```
## [YYYY-MM-DD] <op> | <title>
```

`<op>` is one of: `ingest`, `document`, `query`, `lint`, `meta`.

Body lists: source (if any), files created, files updated, notes, contradictions surfaced. Facts only — no commentary.

## Tone for user-facing output

Match the wiki's voice: dense, neutral, terse. After ingest/document, give a tight summary — created/updated pages, contradictions surfaced, suggested next questions — and stop. No throat-clearing.
