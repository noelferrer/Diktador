---
type: howto
created: 2026-04-27
updated: 2026-04-27
tags: [setup, permissions, hotkey]
status: stable
---

# First-run setup

Two one-time settings the user must apply before Diktador's bare-Fn push-to-talk works correctly.

## 1. Grant Input Monitoring permission

When the app launches for the first time, macOS shows a consent prompt for Input Monitoring. Click **Allow**.

If the prompt was already dismissed or denied, grant access manually:

1. **System Settings → Privacy & Security → Input Monitoring**
2. Toggle **Diktador** on.
3. Quit and relaunch Diktador.

The Diktador menu bar icon shows a warning triangle and the menu reads "Diktador (needs Input Monitoring)" until access is granted. The menu's "Open Input Monitoring settings…" item deep-links to the right pane.

## 2. Disable the macOS globe-key action

macOS reserves the **Fn (🌐)** key for one of: change input source, show Emoji & Symbols, start Apple Dictation, or do nothing. With anything other than "Do nothing", *every* Fn press fires both Diktador's handler and the macOS action — emoji picker pops up while Diktador starts listening, etc.

To prevent this:

1. **System Settings → Keyboard → Press 🌐 to: Do nothing**

This is the same constraint Whisper Flow and Glaido document.

## See also

- [[decisions/hotkey-modifier-only-trigger]] — why bare-Fn requires Input Monitoring.
- `modules/diktador-hotkey/README.md` — full list of hotkey-related failure modes.
