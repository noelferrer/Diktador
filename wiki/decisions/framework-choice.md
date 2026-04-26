---
type: decision
created: 2026-04-26
updated: 2026-04-26
tags: [framework, swift, whisperkit, architecture]
status: stable
---

# Framework: Swift + WhisperKit, macOS-only

> Diktador is built as a native Swift / SwiftUI menu bar app for macOS 14+, using WhisperKit for on-device transcription and Groq as an optional cloud fallback. The [typr](https://github.com/albertshiney/typr) reference (Tauri + Rust + whisper.cpp) informs architecture and STT-pipeline shape but its code is not reused.

## Context

Diktador is a local desktop dictation app modeled on Whisper Flow and Glaido. Initial constraints, surfaced during brainstorming:

- **Platform scope**: macOS day 1; Windows deferred ("think about it later, when there are users to justify it"). Linux not on the roadmap.
- **Distribution path**: personal use → friends → possibly a SaaS site.
- **Cost**: zero. No paid services as a hard requirement; cloud APIs allowed only if free-tier covers personal use.
- **UI ambition**: start minimal (single settings screen, status indicator), grow toward a polished Whisper-Flow-tier UI (history, model picker, command vocabulary) over time.

The original schema in `AGENTS.md` had inherited a Tauri 2 + TypeScript + Vite stack from the [typr](https://github.com/albertshiney/typr) reference clone at `typr-main/`. That assumption was revisited.

## Decision

**Stack**: Swift 5.10+ / SwiftUI / single Xcode project. macOS 14.0 (Sonoma) minimum.

**App style**: Menu bar app (`LSUIElement = YES`), no Dock icon. Settings opened from menu bar.

**STT pipeline (dual-backend, user-selectable)**:
- **WhisperKit** ([argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)) — open-source Swift package (Argmax, MIT) running Whisper on Apple Silicon via Core ML and the Neural Engine. **Default mode out of the box.**
- Groq HTTPS API (`whisper-large-v3-turbo`) — user pastes free-tier key in settings; key stored in Keychain. Selectable as the primary mode once a key is set.

User picks one primary mode in settings. If the primary fails at runtime (model load error, no network for Groq, etc.), the other is attempted as automatic fallback **only if it is configured** (Groq fallback requires a key on file; local fallback requires a model already downloaded). If no fallback is available, the failure surfaces in the menu bar.

**Audio**: `AVAudioEngine` for capture; WhisperKit's built-in VAD with energy-based fallback for end-of-speech detection.

**Hotkey**: [`soffes/HotKey`](https://github.com/soffes/HotKey) (Carbon Events wrapper, MIT). User-configurable; default proposal Right-Option held = push-to-talk.

**Text injection (hybrid)**: clipboard-paste primary (preserve & restore pasteboard), simulated keystrokes via `CGEvent` as fallback. Both require Accessibility permission.

**Persistence**: `UserDefaults` for settings; **Keychain** for the Groq API key; JSON in `~/Library/Application Support/Diktador/` reserved for future structured state.

**App lifecycle**: launch-at-login off by default, toggle via `SMAppService`. Microphone permission requested on first dictation; Accessibility permission requested on first injection.

**Modules** (per `AGENTS.md` six rules) — each a Swift target with a public API and tests:

| Module | Purpose |
|---|---|
| `recorder` | Audio capture + VAD |
| `transcriber` | WhisperKit + Groq dispatcher |
| `hotkey` | Global shortcut registration |
| `output` | Text injection at cursor |
| `settings` | Config + Keychain persistence |
| `ui` | Menu bar + settings window (SwiftUI) |

## Consequences

**Gains**:
- Apple-Silicon-optimized inference via WhisperKit (Core ML / Neural Engine). On M-series Macs this is faster than generic CPU whisper.cpp; this is the literal payoff for choosing native Swift.
- Smaller resident memory (~30–50 MB) for an always-running tool, vs ~80–150 MB for a Tauri equivalent.
- More reliable text injection in stubborn apps (CGEvent + Accessibility API beat `enigo`-style synthetic keystrokes in Electron-based targets like Slack, Discord, VSCode).
- Native macOS permission UX (microphone, Accessibility), launch-at-login (`SMAppService`), and menu bar idioms.
- No Rust learning curve.
- No bundled binaries (no whisper.cpp sidecar to ship, sign, or update).

**Losses**:
- **Windows port = full rewrite.** SwiftUI does not cross-compile. A future Windows version will need a separate codebase (likely Tauri, Electron, or .NET MAUI) that shares only the design — not the code.
- **`typr-main/` code is no longer reusable.** It remains useful as conceptual reference: dual-backend STT pattern, settings shape, menu-bar dictation UX. The Rust modules ([`audio.rs`](../../typr-main/src-tauri/src/audio.rs), [`recorder.rs`](../../typr-main/src-tauri/src/recorder.rs), [`paste.rs`](../../typr-main/src-tauri/src/paste.rs), etc.) translate to Swift idioms but are not copied.
- **macOS 14+ requirement** narrows the immediate user base slightly. Acceptable: personal use is on a recent Mac; friends most likely too.
- **Code-signing and notarization** become required when shipping outside the developer's machine (Apple Developer Program, $99/yr). Deferred until distribution actually happens; not needed for personal use.

**Knock-on workspace changes** (to be implemented after this ADR is approved):
- `AGENTS.md` "What Diktador is" section: replace the Tauri/Rust/Vite stack line with Swift/SwiftUI.
- `AGENTS.md` "Folder shape": replace `src/` + `src-tauri/` with `Diktador.xcodeproj/`, `Diktador/`, `DiktadorTests/`. `modules/` rules still apply (one Swift target per module).
- `.claude/skills/go/SKILL.md` Phase 1 test matrix: `cargo test` → `xcodebuild test`; drop the Vite/Playwright row; computer-use becomes the primary path for hotkey/injection verification.
- `memory/general.md`: update "Project shape" section.
- `wiki/index.md`: register this ADR under Decisions; add stub entries at `entities/whisperkit`, `entities/swift`, `entities/avfoundation`, `entities/cgevent` when first referenced from a second page.

## Alternatives considered

### Tauri 2 (the prior assumption)

- Cross-platform from day 1; Windows port would be a build-target addition rather than a rewrite.
- typr's existing Rust + Tauri code reusable as direct reference and partial copy.
- Bundle ~10–15 MB; the smallest webview-shell option.
- Rejected because: framework speed advantage is largely invisible in dictation (STT dominates the latency budget; framework overhead is roughly 50–100 ms of a 200–600 ms total), while native Swift gains real wins on memory footprint, injection reliability, and access to WhisperKit's Apple Silicon optimizations. The Windows port being deferred (not foreclosed) but explicitly low-priority makes the cross-platform argument weaker than the native-polish argument.

### Electron + TypeScript

- Same TS frontend dev experience; no Rust learning curve.
- Largest ecosystem of dictation/STT examples (Whisper Flow itself runs on Electron).
- Rejected because: ~150+ MB bundle and ~250+ MB resident memory for an always-running tool, with no offsetting upside vs Tauri or Swift.

### Rust-native UI (egui / iced / Slint / Dioxus)

- Cross-platform like Tauri without the webview overhead.
- Rejected because: same Rust learning curve as Tauri but loses the typr code reference; UI libraries less polished than SwiftUI for the eventual settings/history/model-picker surfaces.

### Wails (Go + web frontend)

- Tauri-shaped with Go instead of Rust.
- Rejected because: smaller community than Tauri's, no compelling reason over Tauri unless the developer specifically prefers Go.

### Hammerspoon + a Whisper script

- Smallest possible footprint; Lua daemon shells out to local Whisper.
- Rejected because: cannot grow into the polished UI target (history, model picker, onboarding). The "start minimal, grow polished" trajectory rules out this option.

### Python + PyQt / PySide6

- Best STT ecosystem (faster-whisper, whisper.cpp Python bindings).
- Rejected because: distribution is the pain — PyInstaller bundles are large, code signing on macOS is awkward, runtime performance is mediocre for an always-on tool.

## Alternatives within the Swift path

### whisper.cpp sidecar (typr's approach, ported to Swift)

- Bundle the whisper-cpp binary as a sidecar; shell out from Swift.
- Works on Intel and Apple Silicon Macs equivalently.
- Rejected because: forfeits Core ML / Neural Engine acceleration on Apple Silicon — the main reason to pick native Swift in the first place. Adds binary signing complexity. WhisperKit is the obvious win on a Swift Mac-only app.

### Apple Speech framework (`SFSpeechRecognizer`)

- Built into macOS, free, Apple-supported.
- Rejected because: cloud-routed by default for accuracy, forces an opaque dependency on Apple's online recognition; on-device mode supports limited locales and is markedly less accurate than Whisper. Diktador's local-first / accuracy-first posture rules it out.

## Sources

- [[sources/llm-wiki-pattern]] — workspace founding manifesto (informs the wiki documentation around this decision, not the decision itself).
- typr reference clone: `typr-main/` (read-only). Specifically [`typr-main/src-tauri/src/transcribe_local.rs`](../../typr-main/src-tauri/src/transcribe_local.rs), [`transcribe_groq.rs`](../../typr-main/src-tauri/src/transcribe_groq.rs), [`recorder.rs`](../../typr-main/src-tauri/src/recorder.rs), [`paste.rs`](../../typr-main/src-tauri/src/paste.rs).
- WhisperKit: https://github.com/argmaxinc/WhisperKit
- HotKey (Soffes): https://github.com/soffes/HotKey
- Groq Speech API: https://console.groq.com/docs/speech-text
- Whisper Flow (UX reference): https://wisprflow.ai
- Glaido (UX reference): https://www.glaido.com

## Open questions

- WhisperKit model default: `tiny` (fast, lower accuracy) vs `base` (balanced) vs `small` (accurate, slower) — pick on first measurement, not now.
- Hotkey default: Right-Option held is the proposed default (matches Whisper Flow). Open to user preference at first run.
- Whether to expose Groq's other models (`distil-whisper-large-v3-en`) as alternatives, or hard-code `whisper-large-v3-turbo`.
- Onboarding flow: deferred until v2; first run will be a single permission-request screen.
