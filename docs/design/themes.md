# Picker themes

Open **Settings → Appearance**. The picker has three coordinated palettes:

| Theme | Paper | Composing tray | Selection accent |
| --- | --- | --- | --- |
| Impression (default) | Warm cream | Green graphite | Vermilion |
| Blueprint | Cool white | Navy | Cyan |
| Plum | Pale rose | Plum | Apricot |

**System**, **Light** and **Dark** control the picker’s chrome independently of
the palette. System follows macOS, including changes while Charms is running.
The proof stays paper-coloured and the tray stays dark in every appearance.
Settings itself follows macOS rather than the picker override.

Changes apply immediately and save automatically. They survive relaunch;
**Restore Default Appearance** returns both choices to Impression and System.
The example in Settings uses the actual proof and block components, with a
fixed arrow specimen. It never opens a session or reads a document.

All themes retain:

- The native query field, selection, composition, Undo and text caret.
- Exact Unicode strings and the existing single-dispatch insertion policy.
- Opaque surfaces, stronger rules and labels with Increase Contrast, and no
  travelling selection, lift or scale with Reduce Motion.
- A light selected block, outline and navigation underline in addition to
  the accent colour. Hover never changes Return’s choice.
- Named accessible actions, the unabridged scalar sequence and explicit Copy.

## Storage and extension contract

`Preferences` stores `pickerTheme` (`impression`, `blueprint`, `plum`) and
`pickerAppearance` (`system`, `light`, `dark`). The storage key remains
`preferences.v1`. Old documents get the defaults. Missing, null, malformed or
unknown fields fall back independently without losing a shortcut, trigger
preference or other setting. Older builds ignore the new fields.

`Sources/CharmsCore/Settings/PickerThemeColors.swift` defines opaque sRGB roles.
`PickerPalette` converts them to SwiftUI colours; the AppKit query and caret
use the same values. The panel’s native appearance also covers keyboard
context menus and responds to accessibility display-setting notifications.
No search editor, panel or session is reconstructed for a theme change.

To add a built-in palette, add a `PickerTheme` case and a complete role set,
then expose it in Appearance settings. The exhaustive switch and tests check
that every palette defines valid components, at least 4.5:1 contrast for text
and muted labels, and 3:1 for the selection accent against tray and blocks.
Run the complete unit and real-input suites, add the new theme to their
matrix, and inspect the actual app in both appearances and contrast modes.
Do not change preview strings or insertion payloads to suit a palette.

User-authored theme files, arbitrary accent pickers and per-application theme
rules are deliberately not supported. Compatibility and runtime checks are
recorded in [compatibility](../compatibility.md#impression-prototype).
