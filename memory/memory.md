---
type: memory-index
created: 2026-04-26
updated: 2026-04-26
---

# Memory Index

Operational working memory for Diktador. Read this first when looking for prior session context. Index only — link, don't inline. Stay under ~200 lines.

For the encyclopedic knowledge layer (decisions, module specs, public-facing docs), see [`wiki/index.md`](../wiki/index.md). The `wiki/` and `memory/` distinction is documented in [`AGENTS.md`](../AGENTS.md) under "Memory system".

## General

- [general.md](general.md) — cross-cutting facts, environment, preferences

## Domains

_None yet. One file per topic area when memory accrues._

Planned (created on demand):
- `domains/recorder.md` — AVAudioEngine capture, VAD, mic permissions
- `domains/transcriber.md` — WhisperKit + Groq dispatcher, model selection, latency
- `domains/hotkey.md` — global shortcut registration via soffes/HotKey, conflicts
- `domains/output.md` — clipboard-paste + CGEvent fallback, Accessibility quirks
- `domains/settings.md` — UserDefaults + Keychain (Groq key) shape
- `domains/packaging.md` — Xcode bundling, code signing, notarization

## Tools

_None yet. One file per external tool when memory accrues._

Planned (created on demand):
- `tools/whisperkit.md` — WhisperKit quirks, model variants, Core ML / Neural Engine notes
- `tools/swift.md` — Swift / SwiftUI gotchas hit during build
- `tools/xcode.md` — project config, scheme management, build settings
- `tools/hotkey.md` — soffes/HotKey package usage, Carbon Events caveats
- `tools/groq.md` — Speech API quirks, free-tier limits, key handling
- `tools/github.md` — repo conventions, PR flow

## Daily

- [daily/2026-04-26.md](daily/2026-04-26.md) — Memory system bootstrapped; workspace `/go` skill created.

## Commands

- **reorganize memory** — scan, dedupe, merge, split, refresh this index.
- **summarize today's work into memory** — write today's daily note; promote durable facts.
- **promote recurring items to long-term memory** — scan recent dailies; surface patterns.

See [`AGENTS.md`](../AGENTS.md) → "Memory system" for the full spec.
