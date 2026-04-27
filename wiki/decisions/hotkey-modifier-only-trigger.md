---
type: decision
created: 2026-04-27
updated: 2026-04-27
tags: [hotkey, architecture, macos, permissions]
status: stable
sources: []
---

# Hotkey: bare-modifier triggers over NSEvent

## Context

PR #2 shipped `HotkeyRegistry` over [soffes/HotKey](https://github.com/soffes/HotKey), which wraps Apple's Carbon Events API. Carbon Events does not model the **Fn (🌐)** key as a modifier and does not report **sidedness** (Right-Option vs Left-Option). The canonical Mac dictation push-to-talk UX, used by Whisper Flow and Glaido, holds bare Fn — unreachable through the Carbon path.

The user explicitly asked for bare-Fn push-to-talk during Phase G of PR #2. Filed in `memory/domains/hotkey.md`. The question for this ADR: how to extend the existing `HotkeyRegistry` to support modifier-only triggers without breaking its current public surface.

## Decision

Extend `HotkeyRegistry` with a parallel internal code path built on `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` (for events arriving while another app is frontmost) paired with `addLocalMonitorForEvents(matching: .flagsChanged)` (for events while Diktador itself is frontmost), exposed through a new `register(modifierTrigger:onPress:onRelease:)` overload and a new public `ModifierTrigger` enum. The existing `register(combo:)` Carbon path is unchanged. Both paths produce the same opaque `RegistrationToken`; `unregister` looks in two internal storage maps.

The NSEvent global monitor requires the macOS **Input Monitoring** TCC permission (granted via System Settings → Privacy & Security → Input Monitoring). Surface this as a public `inputMonitoringPermission: InputMonitoringStatus` getter and a `requestInputMonitoringPermission(completion:)` method on the registry; let the app target orchestrate the user-facing permission flow (`AppDelegate.bootstrapPushToTalk` does this in v1).

`AppDelegate` rewires its v1 push-to-talk from Option+Space to bare Fn. Option+Space is dropped from the v1 default; the future settings module will reintroduce user choice.

## Consequences

- **Two parallel internal paths** in one module. Acceptable: the public surface stays a single registry with one token type; the dual paths reflect a real OS-API split (Carbon vs Cocoa) that no SwiftPM library currently bridges cleanly.
- **New runtime dependency: Input Monitoring permission.** First launch shows a system prompt; denial leaves the app non-functional until granted. The denied state shows a warning status icon and a one-click jump to the right System Settings pane — Apple does not allow auto-opening the consent dialog after the first denial, so a deep-link is the best UX available.
- **Required user-side setup.** macOS's `Press 🌐 to` setting must be set to "Do nothing" or every Fn press also triggers Apple's chosen globe-key action (Apple Dictation, emoji picker, input source switch). Documented in `wiki/howtos/first-run-setup.md`. Same constraint applies to Whisper Flow and Glaido.
- **Internals leak through the seam.** A new internal `PermissionProvider` protocol is introduced so tests can swap in a stub. Stays internal; promoted to public only when an external caller needs it.
- **Right-side modifiers still pending.** Same NSEvent infrastructure unblocks `.rightOption`, `.rightCommand`, etc. — but they're a *sided* variant of existing `KeyCombo.modifiers`, not a modifier-only trigger. Different API surface. Filed for the next PR.

## Alternatives considered

1. **Extend `KeyCombo` to express modifier-only combos.** Rejected: forces a `Key?` field, contorting the value type for a single edge case, and conflates "key + modifier" with "modifier alone" — different OS APIs handle each.
2. **A separate `ModifierMonitor` module/class.** Rejected: doubles the public surface for a feature whose semantics ("global hotkey") match the existing module exactly. Would also force the app target to keep two registries in sync.
3. **Bundle right-side modifiers in the same PR.** Rejected on scope: their public-API shape is different (sided variants of `KeyCombo.modifiers`, not new `ModifierTrigger` cases) and their UX implications (which side is which in user-facing labels?) deserve their own design pass.

## Sources

- `modules/diktador-hotkey/README.md` — public API, full failure-mode list.
- `memory/domains/hotkey.md` — v1 configuration + remaining open questions.
- `docs/superpowers/specs/2026-04-27-hotkey-fn-trigger-design.md` — design doc this ADR ratifies.
- soffes/HotKey upstream documentation (Carbon Events constraints).
