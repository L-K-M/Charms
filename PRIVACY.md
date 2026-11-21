# Privacy

Charms has no account, server, or analytics. Character search, snippets and
your local GIF library work offline.

**My GIFs.** Charms reads GIFs in the folder you choose. It keeps the folder
selection, file information and search tags in local application support.
Vision and the available on-device Apple Intelligence model analyze frames
locally. Copy GIF places the original image data on the clipboard.

**Online GIFs.** Typing in this source sends the new search to your selected
provider, KLIPY or GIPHY. The provider receives the query, API key, rating,
and connection information including your IP address. Requests can include
language, region, and for KLIPY an anonymous client identifier. Viewing
a preview contacts the provider’s media host. Switching sources clears the
search field. Charms never includes local GIFs, local tags, document text or
ordinary character searches in provider requests.

## What Charms looks at

**When you open the picker.** Charms asks the application you are typing in,
through the Accessibility interface, which field has the keyboard focus, where
that field and its window are on screen, where the text cursor is, and where
the one character on either side of the cursor is drawn. These are positions,
not text. It uses them to open the picker beside the cursor and to make sure
the chosen character goes back to the same field. It does not read what the
field contains, the window title, or the clipboard.

**Password fields.** A field that the application marks as secure, or any
moment when the system reports secure keyboard entry, is never read and never
receives an insertion. The picker then only copies.

**When the `::` trigger is on.** This is off unless you turn it on. While it
is on, Charms is notified of keys typed in other applications so that it can
notice two colons in a row. It keeps one thing: the fact that a colon was just
typed, in which application, and when. After `::` it also keeps the few
characters you type next, as the start of your search, until the picker
closes. To replace the colons it reads the text directly before the cursor,
limited to the colons, those characters, and the one character before them.
None of this is stored or logged. Turning the trigger off removes the
observer.

**The clipboard.** Copy puts the chosen character on the clipboard; that is
its purpose. Ordinary insertion does not touch the clipboard. Only for
applications you list under "Insert by pasting" does Charms place the
character on the clipboard, send Paste, and put the previous contents back.
It holds those contents in memory for under a second, never writes them to
disk, and leaves the clipboard alone if you copied something else meanwhile.

## What Charms stores

In `~/Library/Application Support/Charms/library.json`: your favourites and
your fifty most recently used characters, each with its name.

In its preferences: the shortcut, the preferred skin tone, whether the `::`
trigger is on, the three application lists, and the applications you
answered about when Charms asked whether to turn on text field reporting.

It does not store searches, typed text, document contents, window titles,
clipboard contents, or which application you used a character in.

## Diagnostics

Charms keeps a short log in memory while it runs: timings, outcome categories
such as "placed beside the cursor" or "insertion blocked: focus moved", and
the bundle identifier of the application involved. The log has no free-text
field, so typed text cannot enter it. It is written to a file only when you
choose Export Diagnostics in Settings, at the place you choose, and it is
never sent anywhere.

## The permission

Charms uses one privacy permission, Accessibility. The system grants the
right to read another application's interface and the right to send it
keyboard input together, and the same permission covers noticing the two
colons. You can revoke it at any time in System Settings under Privacy &
Security (Accessibility, or Device Control and Data Access on macOS 27);
Charms then goes back to browsing and copying.
