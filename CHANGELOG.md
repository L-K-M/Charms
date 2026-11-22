# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Create meme artwork in any style on macOS 27, or with ChatGPT on macOS 26
  or later, through Image Playground.
- Generate meme artwork in the composer with your own Venice key, using
  Z-Image Turbo or GPT Image 2.6 Flare. It is off until you switch it on.
- Caption an image you drop or choose, for example one made offline with
  Draw Things.

### Changed

- Memes works on Macs without Apple Intelligence.
- Cancelling Image Playground returns to the meme composer.
- Settings has a Memes tab and is wide enough for all tab titles.

### Fixed

- The privacy policy no longer says Image Playground’s styles run on the
  device. On macOS 27 they run on Apple’s Private Cloud Compute.

## [0.2.0] - 2026-11-21

### Added

- Save, edit and insert short text snippets from the picker or the optional
  `::` trigger. Charms includes 20 editable starters.
- Search a watched GIF folder by filename or editable on-device tags. On
  supported Macs, Apple Intelligence can also identify actions and reactions.
- Search KLIPY or GIPHY from the picker using a provider key. Copy a local
  animation or insert an online GIF link at the caret.
- Create artwork with Apple’s Image Playground, edit or write a caption,
  and copy the finished meme as a PNG. On supported Macs, Apple Intelligence
  can suggest a caption.

### Changed

- The Impression picker previews characters at two sizes and shows their
  exact Unicode sequence. Choose Impression, Blueprint or Plum independently
  of System, Light or Dark appearance.
- Character search recognizes everyday words such as `urgent`, `approved`
  and `deadline`.
- Switch among picker sources with Command-1 through Command-4 or cycle
  through them with Control-Tab and Control-Shift-Tab.

## [0.1.0] - 2026-11-10

The first release.

### Added

- The picker: a compact grid with search, favourites, recents and a footer
  naming the selected character, opened with a configurable global shortcut
  (Control-P by default) or from the menu bar.
- Placement beside the text cursor on the display that holds the typing
  focus, with fallbacks to the focused field, the focused window, and the
  pointer's display. The picker never covers the line being typed.
- Insertion of the chosen character into the field the picker was opened
  from, sent once after the field has been checked again; Copy whenever that
  field cannot be confirmed.
- Optional `::` trigger: type two colons and a name, press Return, and the
  typed text is replaced by the character.
- Search over Unicode 18.0 characters and Emoji 18.0 by name, CLDR 49
  keyword, curated alias, literal character and code point, with skin-tone
  variants and a preferred tone.
- Settings for the shortcut, launch at login, skin tone, the typed trigger
  and its excluded applications, applications that keep the shortcut, and
  applications that receive characters by Paste.
- First-launch explanation of the Accessibility permission with a
  browse-and-copy alternative, and a content-free diagnostics export.
- Project scaffold in the shared setup: Swift package, build and release
  scripts, CI, tag-driven releases, automated PR review, Dependabot.
