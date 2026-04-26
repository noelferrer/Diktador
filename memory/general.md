---
type: memory-general
created: 2026-04-26
updated: 2026-04-26
---

# General

Cross-cutting facts that span domains. Anything domain-specific belongs in `domains/<name>.md`; anything tool-specific in `tools/<name>.md`.

## Environment

- Platform: macOS (Darwin 25.4.0)
- Shell: zsh
- Workspace path: `/Users/user/Desktop/Aintigravity Workflows/Diktador/`
- Git: not initialized at workspace root yet (will be initialized when first code lands or when `/go` is invoked)
- Remote (when initialized): `https://github.com/noelferrer/Diktador.git`
- Obsidian vault: yes (`.obsidian/` present); wikilinks render natively

## Project shape

- **Stack**: Swift 5.10+ / SwiftUI, single Xcode project. Menu bar app (`LSUIElement`). macOS 14.0+ (Sonoma). _See [[decisions/framework-choice]]._
- **STT**: WhisperKit (Apple Silicon, Core ML / Neural Engine) as default; Groq HTTPS API selectable; Keychain stores the Groq key.
- **Hotkey**: soffes/HotKey (Carbon wrapper). Default proposal: Right-Option held for push-to-talk.
- **Text injection**: hybrid — clipboard-paste primary, CGEvent keystroke fallback. Both require Accessibility.
- **Reference implementation**: [`typr-main/`](../typr-main/) — read-only clone of albertshiney/typr. Code does not transfer (Tauri/Rust); architecture and UX patterns do.
- **UX targets**: Whisper Flow, Glaido (polished modern dictation feel).
- **License/distribution**: free, open-source first; local STT default; cloud STT optional via free tier.

## Open architectural questions (current)

- WhisperKit model default: `tiny` / `base` / `small` — decide on first latency measurement, not before.
- Hotkey default: Right-Option held proposed; user-overridable at first run.
- Groq model exposure: hard-code `whisper-large-v3-turbo`, or also expose `distil-whisper-large-v3-en`?
- Onboarding flow: deferred to v2; v1 first run = single permission-request screen.

## Conventions

- Modular construction enforced (six rules in `AGENTS.md` → "Modular construction")
- Wiki voice: encyclopedic, neutral, dense
- Memory voice: operational, shorthand OK
- Filenames: lowercase kebab-case
- Dates: absolute (`YYYY-MM-DD`), never "yesterday" / "last week" in saved files

## High-level open questions (cross-cutting)

- Packaging / code signing strategy for friends-distribution phase (Apple Developer Program, $99/yr — only when actual distribution happens, not before).
- First module to build: `recorder` or `hotkey`?
- Whether to ship a default Whisper model bundled vs require first-run download.

## Decisions log

_Stable architectural decisions get promoted to `wiki/decisions/` as ADRs. This section tracks in-flight decisions before they harden._

- 2026-04-26 — Framework + STT pipeline locked. See [[decisions/framework-choice]].
