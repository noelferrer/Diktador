---
type: memory-domain
domain: hotkey
created: 2026-04-26
updated: 2026-04-27
---

# Hotkey — operational notes

Public surface and failure modes live in [`modules/diktador-hotkey/README.md`](../../modules/diktador-hotkey/README.md). This file is for working-memory shorthand only — do not duplicate the README.

## v1 configuration

- Trigger: bare **Fn (🌐)** held. `HotkeyRegistry.register(modifierTrigger: .fn, …)` over an NSEvent global monitor. Requires Input Monitoring permission.
- Behavior: hold-to-talk. `onPress` starts listening, `onRelease` stops.
- Registry: instantiated and owned by `AppDelegate`; lives in `modules/diktador-hotkey/`.
- Trigger is hardcoded in `AppDelegate`. The future `settings` module will read from `UserDefaults` and call `unregister` + `register` on change.
- Required user setup (one-time): System Settings → Keyboard → **Press 🌐 to: Do nothing** (otherwise macOS fires its own globe-key action on every press). See `wiki/howtos/first-run-setup.md`.
- Permission state machine in `AppDelegate.bootstrapPushToTalk`: `granted` → register; `undetermined` → call `requestInputMonitoringPermission`, recurse; `denied` → show warning state + "Open Input Monitoring settings…" menu item.

## Open questions (deferred to follow-up PRs / settings module)

- ~~**Bare Fn-key trigger**~~ — shipped. NSEvent global monitor + Input Monitoring permission. See `wiki/decisions/hotkey-modifier-only-trigger.md`.
- **Right-Option-only / sided-modifier support** — Carbon-Events still doesn't expose sidedness. Same NSEvent global-monitor solution as Fn, but a different API surface (lives next to `KeyCombo`, not `ModifierTrigger`, since right-modifiers ARE used as combo modifiers — they're a sided variant of `.option` etc.). Decide before promising in UI.
- **Conflict detection** — soffes/HotKey fails silently when the combo is already taken. v2 plan is `CGEventSource` introspection at registration; until then, a "test your hotkey" affordance in settings would catch most cases.
- **`IOHIDAccessType` `default:` blind spot.** `IOHIDPermissionProvider.currentStatus()` switches on `kIOHIDAccessTypeGranted` / `kIOHIDAccessTypeDenied` and routes anything else (today: only `kIOHIDAccessTypeUnknown`) to `.undetermined`. If Apple adds a fourth case (e.g., `.restricted` for MDM-managed Macs), the provider treats it as undetermined → bootstrap calls request → request resolves false → `.denied`. Functionally correct, observability poor. If a future macOS surfaces a new case, add an explicit branch and possibly a `#if DEBUG` log.

## Debug recipes

- Hotkey "doesn't work": first suspect is silent OS-level conflict. Try a different combo before chasing code.
- `onRelease` never fires: focus likely changed mid-press (Spotlight, lock screen). Treat as advisory; recorder needs its own timeout.
- Test count via `registry.activeRegistrationCount` — it's a public diagnostic, fine to read from tests and from a future debug menu.

## See also

- `modules/diktador-hotkey/README.md` — public API, dependencies, full failure-mode list.
- Plan: `docs/superpowers/plans/2026-04-26-xcode-scaffold-and-hotkey-module.md` — naming-rename rationale (SwiftPM #8471, #7931).
