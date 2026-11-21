# GIF support

1. Add a My GIFs source to the caret picker. Watch one user-selected folder, expose filenames as soon as they are indexed, and store searchable tags under Charms’ application support directory. Never modify source files. Keep user tags across automatic analysis.
2. Sample frames across playback time with Image I/O. On macOS 27, check the on-device Foundation Models image capability before asking for visible actions and reactions. Use Vision labels and caption text as a local baseline. Bound decoding and analysis work and keep browsing available during indexing.
3. Adapt Nevermore’s KLIPY and GIPHY search, small previews, attribution and filtering. Only explicit online browsing can contact a provider. Keep credentials separate from the library and handle missing keys, network failures and stale requests.
4. Carry a frozen choice through Charms’ session machine. Copy original GIF data for local files. Use the existing validated text insertion path for online links. Preserve Escape, focus validation, and ordinary character search.
5. Test indexing and provider behavior with fixtures, build on the supported baseline, exercise the macOS 27 tagging path where available, and run the native picker checks. Document runtime limitations and compatibility.

## Acceptance checks

- Drop a two-frame GIF into the selected directory while Charms runs. Find it
  by filename, press Return, and compare the clipboard data with the original.
- Replace the file, rename it, edit its tags, reopen the library, and remove
  it. A new revision invalidates the preview and analysis. A previously
  committed choice must never read replacement bytes.
- Analyze a staged animation containing a moving shape and a caption on a
  Mac with Apple Intelligence. Check model capability, actual image inference,
  and caption search separately.
- Exercise both providers with recorded responses and a stub HTTP transport.
  Check request fields, URL restrictions, key handling, size limits, errors
  and source switching. Live service coverage requires a provider key.
- Build a universal app and run the keyboard and mouse harness with isolated
  storage. Confirm existing character, snippet and typed-marker behavior.
