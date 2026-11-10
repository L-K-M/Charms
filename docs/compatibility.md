# Compatibility

What has been checked, on which system, and how. Anything not listed under
"Verified" is unverified, whatever the code intends.

## Verified

One system so far, on 10 November 2026:

| | |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Hardware | Mac Studio, Apple M4 Max |
| Toolchain | Xcode 27.2, Swift 6.4.2 |
| Displays | One 1920 x 1080 display at scale 1, plus a virtual second display to its left for the two-display checks. "Displays have separate Spaces" off. |
| Keyboard | Swiss German layout |
| Build | `scripts/build-app.sh`, release configuration, signed with an Apple Development identity |

### How

- **Automated:** `swift test` (339 tests) and `swift run CharmsCatalogTool check`.
- **End to end:** `scripts/e2e.sh` drives the built app with real key and
  mouse events against the `CharmsHarness` window (an `NSTextView`, an
  `NSTextField` and an `NSSecureTextField`) and compares the text that
  arrives, scalar for scalar. All 22 scenarios passed.
- **By hand:** the built app in the applications below, driven with the same
  synthetic keys, with screenshots and the app's own trace (`CHARMS_TRACE`).

### End-to-end scenarios

| Scenario | What it shows |
| --- | --- |
| `insert` | Control-P, a query, Return: the character arrives; the clipboard's change count is untouched; one Undo removes it. |
| `escape` | Escape leaves the text and the clipboard alone and returns the keyboard to the source. |
| `replace_selection` | A selection in the source is replaced by the character. |
| `sequence` | A joined emoji sequence (technologist, U+1F9D1 U+200D U+1F4BB) arrives exactly. |
| `navigate` | Arrow keys act on the results from the first press. |
| `first_selected` | Control-P and Return, with nothing typed: the first favourite arrives. |
| `copy` | Command-Return copies and inserts nothing. |
| `placement` | The picker window is at the caret and does not cover the caret's line. |
| `click_cell`, `click_outside` | A click on a cell inserts it; a click elsewhere cancels and changes nothing. |
| `cancel_while_held` | Escape pressed while Return is still down: the picker stays until Return is released, then closes without inserting. |
| `typed_trigger`, `typed_trigger_fast` | `::arrow` and Return replace the colons and the query, also when typed with 6 ms between keys. |
| `typed_trigger_first_selected` | `::` and Return replace the colons with the first favourite. |
| `typed_trigger_late_selection` | A field that applies a selection made through Accessibility 30 ms after the call, as Chromium does: the colons are still replaced. |
| `typed_trigger_focus_moves_during_selection` | While such a late selection is on its way, another field of the same application takes the keyboard: nothing is sent, and that field stays empty. |
| `typed_trigger_selection_refused` | A field that accepts that call and never honours it: nothing is sent, the picker comes back for copying, a second Return copies, and the colons stay. |
| `typed_trigger_escape` | Escape after `::ar` leaves `::` as typed. |
| `colons_inside_a_word` | `std::cout` does not open the picker. |
| `password_field` | In a password field nothing is sent; Return copies. |
| `paste_backend` | For a listed application the character arrives by Paste and the previous clipboard is put back. |
| `pass_through` | For a listed application Control-P reaches that application and Charms stays closed. |

### Applications

| Application | Field | Placement | Insertion |
| --- | --- | --- | --- |
| TextEdit 1.21 | Plain text document | Beside the caret, below; above when there is no room below | Unicode events. One Undo. Selection replaced. Paste fallback also works, clipboard restored. |
| TextEdit, full screen | Same | The picker appears in the full-screen Space and takes the keyboard | Same |
| Safari 27.0.1 | `<textarea>` | Below the caret with one guard line (the caret's line could not be confirmed from a neighbouring character) | Unicode events |
| Safari 27.0.1 | `<input type="text">` | At the end of the selection | Selection replaced |
| Safari 27.0.1 | `contenteditable` element | Beside the caret | Joined emoji sequence exact |
| Safari 27.0.1 | `<input type="password">` | Under the field | Copy only, as intended |
| Safari 27.0.1 | `<textarea>`, typed `::` | Below the caret | `::`, Tab and Return replace the colons |
| Electron 45.2.3 with its accessibility tree on | `<textarea>`, `<input type="text">`, `contenteditable` element | Beside the caret | Typed `::` with a name: the colons and the name are replaced in all three. Shortcut in the `<textarea>`: Unicode events. |
| Electron 45.2.3 with its accessibility tree off | `<textarea>` | Over its window, after the question | Charms asks whether to turn field reporting on (see below). After Turn On: Unicode events. Otherwise Copy only. |
| Terminal 2.15 | zsh prompt | Beside the cursor, estimated from the previous character | Unicode events |
| An application without a text field in front | | Over its window | Copy only |

### Applications that hide their text fields

With a bare Electron 45.2.3 window, started with its accessibility tree off:

- Control-P shows the question "Let Charms insert into Electron?". Turn On:
  the picker opened by itself about two seconds later, in insertion mode
  beside the caret, and the chosen character arrived.
- After quitting and restarting Electron, with Charms still running: no
  question, and insertion worked on the first Control-P, four seconds after
  the window came to the front.
- Typing `::arrow` and Return showed the question; the typed name and the
  Return did not answer it. Not Now gave the keyboard back to Electron, and a
  second `::` in the same run asked nothing.
- "Do not ask again" with Not Now: stored, the picker opened for copying, and
  after restarting Charms there was no question. Settings showed the answer,
  and Ask Again forgot it.

Follow-up dialog regressions were checked by hand on the same system, because
these checks need an application with a dormant accessibility tree and the
native question, which the end-to-end harness does not emulate:

- Turn On, then immediately Control-P and type a query while the fields are
  becoming available. After waiting six seconds, that picker and its query
  remain open. Before the fix, the delayed answer closed the new picker.
- While the question is open, activate the native harness, then answer Not
  Now. The harness keeps the keyboard and no picker opens. Before the fix,
  Charms brought Electron back and opened a copy-only picker there.
- Answer Not Now without ticking the box, then use Ask Again in Settings
  (with another application's remembered answer making the button visible).
  Control-P in Electron asks again in the same Charms run. This checks the
  temporary answers as well as the stored ones.

### Displays

With TextEdit on the second display (to the left of the main one, so at
negative coordinates) and the pointer on the main display, the picker opened
on the second display beside the caret, and insertion worked. The second
display was a virtual one.

### Permission

Started through Launch Services with no permission, Charms showed the welcome
window; "Browse and Copy" gave a working copy-only picker placed over the
active window. "Enable Insertion" showed the system prompt, whose button
opened System Settings at the list (named Device Control and Data Access on
macOS 27, Accessibility before). After switching Charms on there, the welcome
window reported it by itself, and both the shortcut and the typed `::`
worked without a relaunch and with no other permission. Input Monitoring is
not needed.

### Other

- The status menu, the settings window and its four tabs; recording a new
  shortcut (Control-Option-P took effect at once, the old one was released)
  and resetting it.
- Favourites (Command-D), recents, and their storage across relaunches.
- "Open Charms at login", with an ad-hoc signed build in the Applications
  folder. Before its first registration the system reports the login item
  as "not found"; the switch is usable in that state. Switching it on
  registered the item (shown as enabled by `sfltool dumpbtm`), switching it
  off disabled it again.
- Another application coming to the front while the picker is open cancels
  the session and nothing is inserted. (Seen repeatedly: other processes on
  the test machine kept activating themselves.)

### Timings

Release build, Apple M4 Max, macOS 27.0.1.

| | |
| --- | --- |
| Shortcut to picker on screen | 2 to 17 ms (reading the focused field: 1 to 14 ms) |
| Catalogue load at launch | about 60 ms, off the main thread (43,548 entries) |
| Search, per keystroke | median 0.2 ms, 95th percentile 3.6 ms, worst case about 27 ms for a single common letter |

## Impression prototype

The native interaction prototype is documented in
[the design note](design/impression.md) and
[the running and verification guide](design/prototype.md). These checks use
the same Mac Studio, macOS 27.0.1, Swiss German layout and Swift 6.4.2 as the
baseline above, on 10 November 2026. They do not re-establish the application
matrix above for the new picker.

- Release build assembled with `CODE_SIGN_IDENTITY="Apple Development"
  ./scripts/build-app.sh`; signature verified by the build script.
- `swift build`, all 339 unit tests and `swift run CharmsCatalogTool check`
  pass. The generated catalogue and insertion/session rules are unchanged.
- All **27** real-input scenarios in `scripts/e2e.sh` pass with the new
  432 by 472 point panel. This includes the prior 22 insertion, focus,
  cancellation, Undo, copy, trigger and caret-line placement scenarios.
- Added `hover_keeps_selection`: the pointer rests on the second arrow but
  Return still inserts the keyboard-selected first arrow.
- Added `no_results`: Return changes neither source nor clipboard, leaves the
  picker open, and editing the same native query recovers to an insertion.
- Added `preview_guides`: U+0301 and U+00A0 arrive exactly, without the
  dotted-circle or open-box illustrations.
- Added `click_proof`: clicking the large specimen leaves source and
  clipboard alone and does not dismiss the picker.
- Added `keyboard_menu`: Control-Return, Down, Return inserts through the
  selected character's action menu. The test failed against the original
  routing, which opened the native query menu on macOS 27, and passed after
  interception at the panel's key-equivalent boundary. Composing input is
  still left to the native editor; an IME runtime pass remains unverified.
- Inspected the Accessibility tree: the proof is `AXStaticText` with the
  selected name and full scalar sequence; cells and Insert/Copy are named
  buttons. This is an API inspection, not a VoiceOver listening pass.
- Recorded the actual release app with isolated storage, staged text and
  real keyboard events. The demonstration includes repeated selection,
  pressure during a held Return, focus return and complete emoji insertion.
  The images and ten-second silent video live under `docs/design/`.
  Motion was evaluated in dark appearance; light appearance and accessibility
  display settings were not exercised.
- Reviewing early recording frames exposed transient blank proofs during
  rapid query changes. The prototype now retains the specimen and stamps it
  instead of replacing its identity through opacity transitions. Implicit
  glyph/font crossfades are suppressed, so fast queries do not layer old and
  new proofs together. Final recording frames confirm a continuously visible
  specimen. The guide records the reproduction procedure.

Not established by this prototype: larger-text reflow, a VoiceOver listening
pass, input-method composition, runtime on macOS 14–26 or Intel, and fresh
multi-display/full-screen application coverage with the taller panel. The
existing native editor, accessibility values, contrast/motion environment
handling and session policy remain, but code paths are not a substitute for
those runtime checks.

## Published v0.1.0

Published on 10 November 2026 from commit
`bdb0a4e8cae8051e23219dc15397a53628e0ff7f` by
[release run 42881964227](https://github.com/L-K-M/Charms/actions/runs/42881964227).
The hosted macOS 26 / Xcode 26.0 job passed all 339 tests, built and ad-hoc
signed the universal app, and downloaded both uploaded assets to compare
them byte for byte with the build output.

The published ZIP and DMG were then independently downloaded with the
GitHub CLI on the Mac described above:

- SHA-256 hashes match GitHub's asset digests and the published
  [SHA256SUMS.txt](https://github.com/L-K-M/Charms/releases/download/v0.1.0/SHA256SUMS.txt).
  These identify the artifacts; byte-for-byte reproducible builds are not
  claimed.
- ZIP integrity and `hdiutil verify` passed. The read-only mounted DMG and
  extracted ZIP contain identical app bundles. The DMG's Applications link
  points to `/Applications`.
- Both apps pass strict, deep signature verification. The executable has
  `arm64` and `x86_64` slices; the version is 0.1.0, build 2, with macOS 14.0
  as the minimum and `ch.lkmc.Charms` as the bundle identifier.
- The catalogue and third-party notices match the tagged source. The icon
  decodes at 1024 x 1024 and retains transparent corners.

### Installed app checks

The downloaded app was copied to `/Applications/Charms.app`. Since the
GitHub CLI does not add quarantine, a quarantine attribute was applied for
this test. Gatekeeper blocked it; Done, then Open Anyway in Privacy &
Security, confirmation and administrator authentication allowed it to open.
This exercises the macOS 27 warning route, not a browser's download/drag
installation. The CLI-installed copy remained translocated after approval,
so its quarantine attribute was cleared before the stable-path checks.
Launch Services then reported `/Applications/Charms.app`, not App Translocation.

With `CHARMS_HOME` isolating storage for the interaction checks:

- The native Accessibility prompt appeared before insertion was enabled.
  Enabling Charms in Device Control and Data Access was reflected in Settings.
- Control-P, `arrow`, Return inserted exactly U+2192 into a staged TextEdit
  rich-text document. One Edit > Undo Typing restored the original text.
- Escape after searching for emoji left the source exactly unchanged.
- The login-item switch registered and unregistered the app. No additional
  approval was required; the switch was left off. Actual login was not tested.
- Opening the installed app again showed Settings and kept one process.
  Quitting removed that process.
- The README screenshots were captured from this published build in dark
  appearance, not from a mockup. Their provenance is in
  [screenshots/README.md](screenshots/README.md).

The test apps were quit, the temporary installation removed, and the desktop
released. This does not extend coverage to Intel or older macOS versions.

## Not verified

- **macOS 14, 15 and 26.** The deployment target is macOS 14 and CI builds
  with Xcode 26 on macOS 26, but the app has only been run on macOS 27.
- **Intel Macs.** Release builds are universal; the Intel half has not been
  run.
- **Chrome and real Electron applications** (VS Code, Slack and the like),
  **Firefox**, **Microsoft Office**, **JetBrains** IDEs. None was installed.
  Electron was tried only as a bare Electron 45 window showing a test page.
  The question about hidden text fields relies on the `AXManualAccessibility`
  attribute, which Electron documents. Whether Chrome and other Chromium
  browsers answer it the same way is not known; if they do not, Charms
  offers Copy there and asks nothing.
- **Notes, Mail, Messages, Pages.** Left alone on the test machine so as not
  to write into real data.
- **The typed `::`** outside TextEdit, the harness, a Safari `<textarea>`
  and the Electron test page. It is off by default and off in terminals,
  editors and password managers.
- **Input methods** (Japanese, Chinese, Korean). The `::` observer is
  suspended while one is composing and the picker's search field does not act
  on Return during composition; both have code and unit tests only.
- **"Displays have separate Spaces" switched on, Stage Manager, a real second
  display, mixed scale factors, vertical arrangements.** Placement geometry
  for these is covered by unit tests only.
- **Light appearance, increased contrast, larger text, VoiceOver.** Cells
  carry names, values and traits; nobody has listened to them.
- **PopChar or another utility on the same shortcut.** The first to register
  wins; what Charms shows when it is second (a message in Settings) was not
  exercised.
- **Starting at login.** The login item registers and unregisters, but
  nobody has logged out and in again to see Charms start. A login item that
  waits for approval in System Settings, and a copy that macOS runs from a
  temporary location (opened straight from Downloads or the disk image),
  have code and unit tests only.
- **A fresh browser download and drag installation**, Gatekeeper on older
  macOS versions, and the pasteboard privacy behaviour of a downloaded app
  started through Launch Services. The CLI-downloaded app and the macOS 27
  warning route were checked as described above.
- **Secure input switched on by another application** (some password
  managers and terminals do this) while Charms is used elsewhere.
- **Skin-tone variants by hand.** The preference, the per-cell menu and the
  fallback to the base emoji have unit tests; the menu was not opened.
- **Sleep, display changes and permission revocation during an open
  picker.** Each cancels the session in code; only the application-change
  case was seen.
