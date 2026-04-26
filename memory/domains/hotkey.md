---
type: memory-domain
domain: hotkey
created: 2026-04-26
updated: 2026-04-26
---

# Hotkey — operational notes

Public surface and failure modes live in [`modules/diktador-hotkey/README.md`](../../modules/diktador-hotkey/README.md). This file is for working-memory shorthand only — do not duplicate the README.

## v1 configuration

- Combo: `Option+F13` (placeholder; uncommon enough to dodge most OS / app reservations).
- Behavior: hold-to-talk. `onPress` starts listening, `onRelease` stops.
- Registry: instantiated and owned by `AppDelegate`; lives in `modules/diktador-hotkey/`.
- Combo is hardcoded in `AppDelegate`. The future `settings` module will read from `UserDefaults` and call `unregister` + `register` on change.

## Open questions (deferred until settings module exists)

- Right-Option-only support — Carbon Events doesn't expose sided modifiers; would need a parallel path through `NSEvent.addGlobalMonitorForEvents`. Decide before promising the feature in UI.
- F13-less keyboards — most laptops and many compact externals have no F13. Need a sensible default fallback (Right-Option? a chord?) and a way for users to rebind.
- Conflict detection — soffes/HotKey fails silently when the combo is already taken. v2 plan is `CGEventSource` introspection at registration; until then, a "test your hotkey" affordance in settings would catch most cases.

## Debug recipes

- Hotkey "doesn't work": first suspect is silent OS-level conflict. Try a different combo before chasing code.
- `onRelease` never fires: focus likely changed mid-press (Spotlight, lock screen). Treat as advisory; recorder needs its own timeout.
- Test count via `registry.activeRegistrationCount` — it's a public diagnostic, fine to read from tests and from a future debug menu.

## See also

- `modules/diktador-hotkey/README.md` — public API, dependencies, full failure-mode list.
- Plan: `docs/superpowers/plans/2026-04-26-xcode-scaffold-and-hotkey-module.md` — naming-rename rationale (SwiftPM #8471, #7931).
