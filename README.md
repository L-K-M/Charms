# Charms

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

**Latest release:** v<!-- version -->0.2.0<!-- /version --> · [Download](https://github.com/L-K-M/Charms/releases/latest)

Charms is a small Mac menu-bar utility for typing the characters your keyboard
does not have: arrows, symbols, punctuation and emoji. Press a shortcut where
you are typing, type a name, press Return, and keep typing.

What sets it apart is where it opens. The picker appears on the display that
holds your typing, right beside the text cursor, and never on top of the line
you are writing, wherever the mouse happens to be.

### Impression: the composing picker

Choose a character on a little type block. See it large on a paper proof and
at writing size between “Aa” and “Bb”. Then press Return and keep writing.
The specimen is demonstration text, not a reading of your document. The name
and exact Unicode sequence sit beside the proof; guides for spaces and
combining marks are labelled and never inserted.

![The Impression picker showing arrow results beneath the four mode buttons and their keyboard shortcuts](docs/design/impression-arrows.png)

The raised selection and short stamping response give choosing a character
some weight, without adding a step or delaying insertion. Hover never changes
what Return inserts. Motion follows Reduce Motion; the opaque paper and
composing tray do not depend on transparency. Sound is intentionally absent.

Read the [three concepts and design decision](docs/design/impression.md),
[build and run it](docs/design/prototype.md), or
[watch the native keyboard demonstration](docs/design/impression-demo.mp4).
The catalogue and insertion policy are unchanged.

### Original picker (v0.1.0)

![Charms searching for arrows beside the typing position in TextEdit](docs/screenshots/picker-arrows.png)

## Using it

| Key | What it does |
| --- | --- |
| `⌃P` (configurable) | Open the picker; press again to close it. |
| Typing | Search by name, keyword or alias: `arrow`, `check`, `infinity`, `cmd`, `->`, `nbsp`. Everyday words find what they suggest: `urgent`, `approved`, `deadline`, `heart emoji`. A pasted character or `U+2192` finds it exactly. |
| `→` at the end of the search, `↓`, `Tab` | Move into the results. Arrow keys then move between cells; `↑` from the first row returns to the search. |
| `↵` | Insert the selected character where you were typing. The first one is selected as soon as the picker opens: your first favourite, or the best match once you search. |
| `⌘↵` | Copy it instead. |
| `⌘D` | Add the selected character to your favourites, or remove it. |
| `⌃↵` | Open the selected character's menu: skin tones, moving a favourite, Copy. |
| `esc` | Close without changing anything. |

Before you search, the picker shows your favourites and the characters you
used most recently. Names and keywords find emoji too:

![Charms showing emoji results for the search “smile”](docs/screenshots/picker-emoji.png)

### Typing `::` instead of the shortcut

Switch this on in Settings or in the menu-bar menu. Then type two colons at
the start of a field or after a space and keep going: `::arrow`, Return. The
colons and the name are replaced by the character. Escape closes the picker
and leaves the colons in your text; the name you typed into the picker is not
put there. It is off by default, and off in terminals, code editors,
password managers and applications that have their own `:shortcodes:`; the
list is yours to edit.

### GIFs

Choose a folder under **Settings → GIFs**, then drop your GIF files into it.
Open the picker with the shortcut and choose **My GIFs** (⌘2). Search by
filename, caption, or tag. The up and down arrows preview results. Return
copies the original animated GIF for pasting into an app that accepts images.
Edit a file’s search tags in GIF settings. Preview, tagging and copy support
files up to 64 MiB.

Charms analyzes sampled frames on your Mac. Vision finds subjects and text.
On macOS 27 or later, an available on-device Apple Intelligence model can
also suggest actions and reactions. Filename search works during analysis.

For web results, configure a KLIPY or GIPHY key in GIF settings and choose
**Online GIFs** (⌘3). Type a new query to search that provider. Return inserts
the selected link, or copies it when the picker has no insertion target.
Command-Return copies the link. **Characters** (⌘1) returns to the catalogue.
The picker shows each source’s shortcut beside its name. You can also
switch sources with **Control-Tab** (next) and
**Control-Shift-Tab** (previous). From Online GIFs, these go to Memes
and My GIFs respectively.
The typed `::` shortcut stays local to character and snippet search.

### Memes

Choose **Memes** (⌘4), describe a scene, and press Return. The composer
takes artwork from four places:

- **Image Playground** opens by itself after Return, unless Venice is
  switched on, and starts generating straight away. On macOS 27 or later it
  starts in **Any Style**, and all its styles run on Apple’s Private Cloud
  Compute. It requires Apple Intelligence.
- **ChatGPT…** opens the same Apple sheet with ChatGPT selected, on macOS 26
  or later. The first time, macOS offers to set ChatGPT up. Until then
  ChatGPT doesn’t appear in the sheet’s style menu. If you choose Not Now,
  the sheet uses Apple’s model instead. Charms needs no key.
- **Venice** generates inside the composer with your own API key. Add the key
  and switch Venice on under **Settings → Memes**. Choose a model, then press
  **Generate** (⌘G). Venice bills your account. At its list prices of
  22 November 2026, Z-Image Turbo costs $0.01 an image and GPT Image 2.6
  Flare $0.05, $0.07 or $0.09 at low, medium or high quality. Charms never
  retries, and a request you stop may still be billed.
- **Your own image.** Drop an image anywhere in the composer, or click
  **Choose Image…** (⌘O). This works offline with generators such as Draw
  Things. While the composer waits for an image, it stays above other apps
  so you can drag to it.

Venice and your own images need no Apple Intelligence. On macOS 27 or later,
Charms uses the available on-device Apple Intelligence model to suggest a
caption. You can edit it or write your own, and a caption you wrote stays
when you change the artwork. **Copy PNG** copies the finished meme so you can
paste it where you want. To caption an image without describing a scene,
click **Open Meme Composer** in the picker.

### Text snippets

Type `::shrug`, then Return, to insert `¯\_(ツ)_/¯`. Charms includes **20
editable starters**, including table flip/unflip, Lenny, disapproval, bear,
cat and celebration faces. Open **Settings → Snippets** to add your own short,
single-line text, edit a shortcut, or remove a starter. You can also find
snippets through the normal picker shortcut. Nothing expands automatically.

Snippet tiles show their shortcuts; the proof shows the replacement text.
Exact shortcuts take priority over emoji aliases, with the emoji still
available as another result. Favourites and recents keep exact saved copies,
so editing a snippet does not silently change them. Explicitly saved snippets
are stored locally as plain text, never included in diagnostics.

See [the snippet guide](docs/snippets.md) for limits, storage and the researched
starter list with source links.

### Applications that hide their text fields

Some applications, those built with Electron among them, do not report where
you are typing unless an app requests it. Charms can then only copy. The
first time it meets such an application it asks whether to turn this on for
that application. If you agree, Charms requests it then and each time the
application starts; it takes about two seconds to take effect, and the
application may use a little more memory and processor time. Switching to
another application while the question is open does not pull you back.
Your remembered answers are listed under Settings, General, where Ask Again
forgets all answers, including a temporary Not Now in the current run.

### Settings

Change the shortcut, choose a default emoji skin tone, or start Charms at
login in Settings.

**Appearance** offers three picker themes:
**Impression** (warm paper and vermilion), **Blueprint** (navy and cyan), and
**Plum** (rose paper and apricot). Choose System, Light or Dark independently.
Choices take effect immediately and survive relaunch. The preview uses the
same proof and character blocks as the picker. Restore Default Appearance
returns to Impression and System. [Theme details](docs/design/themes.md).

![Charms General settings, with insertion enabled and launch at login off](docs/screenshots/settings.png)

### Permission

Charms asks for one permission, Accessibility, and explains it before the
system prompt appears. (macOS 27 lists it as Device Control and Data Access.)
It uses it to find the field you are typing in and to send the chosen
character there. Without it Charms still opens, searches and copies; you paste
yourself. Charms contacts an external service only for online GIFs and for
Venice artwork you ask it to generate. Image Playground can use Apple’s or
ChatGPT’s servers. See [PRIVACY.md](PRIVACY.md).

If insertion stops after replacing the app, choose Enable Insertion in
Settings, General. In the system list, switch Charms off and on again if it
is already enabled.

## Installing

Download the `.dmg` from the [latest release](https://github.com/L-K-M/Charms/releases/latest),
drag Charms to Applications, and open it. Releases are not signed with a
Developer ID or notarized, so macOS refuses the first launch. On macOS 15 or
later, try to open Charms once, dismiss the warning, then click Open Anyway
under Privacy & Security in System Settings. On macOS 14, Control-click the
app, choose Open, then Open. Requires macOS 14 or later.

Both archives are universal (Apple Silicon and Intel); only Apple Silicon
has been runtime-tested. [SHA-256 checksums](https://github.com/L-K-M/Charms/releases/latest/download/SHA256SUMS.txt)
identify the published files, not a claim of reproducible builds.

If another utility already uses Control-P, for example PopChar, quit it or
change one of the two shortcuts; whichever registered first wins.

To remove Charms, switch off "Open Charms at login" in its Settings, quit it,
remove any saved GIF or Venice keys in Settings, delete the app, and
optionally delete `~/Library/Application Support/Charms` (favourites and
recents) and the Accessibility entry in System Settings.

What has been tested, and on which systems, is recorded in
[docs/compatibility.md](docs/compatibility.md). The released-app screenshots
under `docs/screenshots/` show v0.1.0 on macOS 27. Impression captures live
under `docs/design/`. Other macOS versions may look
different.

### Reinstalling or going back

Quit Charms before replacing the app with a copy from
[Releases](https://github.com/L-K-M/Charms/releases). Replacing the app keeps
your settings, favourites and recents.

Before trying an older version, back up `~/Library/Application Support/Charms`
and export your preferences with
`defaults export ch.lkmc.Charms Charms-preferences.plist`. Restore data and
preferences from a backup made for that version if needed. Replacing the app
does not reverse a data migration. This first release uses library schema 1;
downgrades across schema versions are unverified.

## Building

```sh
swift build                       # the package
swift test                        # CharmsCore and catalogue tests
swift run CharmsCatalogTool check # the committed catalogue matches the pinned data
./scripts/build-app.sh            # dist/Charms.app, ad-hoc signed (--debug, --universal)
./scripts/e2e.sh                  # drives the built app with real keys (see below)
```

`scripts/e2e.sh` starts the built app with a temporary home directory, opens
a test window (`CharmsHarness`), and checks insertion, Undo, Escape, copying,
placement, the typed `::` and the password-field rule with real key events. It
needs a terminal that has the Accessibility permission and uses the keyboard
for about four minutes, including checks in every theme and both explicit
appearances.

`scripts/build.sh` / `scripts/release.sh` wrap the shared `lkm-build` /
`lkm-release` engines; releases are cut by tagging. See [CICD.md](CICD.md).
Requires macOS 14 or later. Build with Xcode 27.2 to include on-device image
prompting and match CI. There are no package dependencies.

macOS ties the Accessibility grant to the app's signature, and an ad-hoc
signature is different in every build. For a build you rebuild often, sign
with a stable identity so the grant survives:

```sh
CODE_SIGN_IDENTITY="Apple Development" ./scripts/build-app.sh
```

The character catalogue (`Resources/catalog.txt`) is generated from the
Unicode and CLDR files pinned under `Data/`, the curated aliases in
`Data/aliases.tsv`, and the everyday words in `Data/related.tsv` and
`Data/preferred.tsv`. After changing any of them, run
`swift run CharmsCatalogTool generate` and commit the result.

The design, and the measurements behind it, are in [PLAN.md](PLAN.md).

## License

Charms's own code is released under the [Unlicense](LICENSE). The character
names and keywords in the bundled catalogue come from the Unicode Character
Database, Unicode Emoji data and CLDR, which keep their own license; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
