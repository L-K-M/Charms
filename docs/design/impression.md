# Charms: finding the defining experience

Stage: both. No concept was preselected.

Charms' central object is an exact Unicode string, which may be one arrow or
an entire joined emoji. Its satisfying transformation is small but specific:
a name becomes a visible character, then becomes part of your writing. The
existing app protects the important part: the original field is captured
before opening, insertion happens once after revalidation, and Escape changes
nothing.

## 1. Impression

Choosing a character is a tiny act of typesetting. A grid helps you find it,
but seeing it at writing size tells you whether it is right.

Before searching, Charms opens as a compact composing instrument: favourites
sit on shallow, individually lit type blocks. Above them is a paper proof of
the selected character. Not a screenshot of your document: an explicitly
labelled specimen.

Typing replaces the blocks with real catalogue results. Arrow keys move a
vermilion selection saddle between them. The selected block lifts two points;
its character makes a much larger impression on the proof above. A second
specimen shows the same character between “Aa” and “Bb”, at text size. The
name and complete Unicode sequence remain readable alongside it.

The show-someone detail: hold Return. The selected block sinks, its highlight
disappears, and the proof compresses into an ink impression. Release Return
and you are back in your document with the character. There is no artificial
wait or victory animation; the existing key-release safety gate supplies the
physical gesture.

Everyday operation remains shortcut, query, Return. Clicking a block activates
it once. Hover only lifts its edge; it never changes what Return inserts.
Reduce Motion removes travel. Invisible characters use labelled guides,
never substituted output.

## 2. Orbit

A character has close relatives: arrows with different weight and direction,
faces with subtly different expression, emoji with valid variants. Discovery
is often comparative rather than verbal.

Before searching, a small central aperture contains the selected character.
Favourites form a straight lower rail. Searching “arrow” arranges results in
concentric, partial arcs around the aperture, grouped by catalogue order
rather than invented semantic relationships.

Dragging horizontally turns the outer arc beneath a fixed index mark. Arrow
keys perform the same discrete steps. Crossing a result boundary brings its
character into the central aperture; the previous two choices remain visible
as small comparison ghosts. Return inserts the indexed result. Escape closes
without moving anything into the document.

The show-someone detail: a sweep of the trackpad becomes a controlled
procession of arrows, each stopping at exactly the same optical centre. At
slow speed, neighbouring forms visibly separate; at fast speed, the rail moves
without magnifying every intermediate character.

Daily use requires a substantial concession: search still selects the first
result immediately, keyboard navigation must follow a predictable order, and
a linear accessibility representation must exist. No circular menus or
mandatory spinning. This could make browsing wonderful, but geometry
competes with the fast eight-column scan Charms already supports.

## 3. The Fold

Charms belongs beside the caret, between intention and the line being
written. Its workspace could make that boundary visible.

The picker opens as a narrow vertical fold. One side contains the search and
a conventional result grid; the other is a blank, private staging strip with
a large caret. No source text is read for decoration.

Selecting a character lays it across the fold: a large exploration specimen
on the catalogue side, a text-sized version beside the staging caret. With
pointer input, dragging a result toward the strip unfolds its large specimen
down to writing size. Releasing on the clearly marked insertion area commits
it. Dragging back or pressing Escape cancels. Keyboard users get the same
transformation through selection and Return, without dragging.

The show-someone detail: an enormous emoji turns the corner and becomes a
little character beside the caret, like a sheet folding between two scales.
The motion explains insertion rather than illustrating a generic success
state.

Convenience demands that a normal click still inserts immediately and that
the fold never pretends to be the actual document. Copy-only mode needs an
unmistakably different destination. These compromises make it safe, but the
most expressive gesture is also its least necessary one.

## Commitment: Impression

Impression concentrates the extravagance on something useful: inspecting a
character before committing it. It works equally well for arrows,
punctuation, combining marks and emoji, without inventing catalogue
relationships or reading your document for scenery.

The vocabulary is warm paper, dark ink, shallow graphite blocks, registration
marks, and a single vermilion selection colour. Motion is short and
interruptible: roughly 120 ms for hover, 180 ms for a new proof, and immediate
compression while Return is held. Sound is deliberately absent. The contrast
between a substantial object and a precise, silent action is intentional.

The prototype keeps the native AppKit search editor and the existing session
machine. Presentation observes the machine's pending choice; it does not own
a second commit state or delay dispatch. Proofs use the exact catalogue
preview and identify dotted-circle and space guides. The complete scalar
sequence remains available even when long enough to need horizontal scrolling.
The specimen's “Aa” and “Bb” are fixed demonstration text, never document text.

See [the prototype guide](prototype.md) for running, interaction timings,
captures and verification limits.

## Deliberately not doing

No shelves, smoke, weapons, random particles, fake insertion receipts,
compulsory dragging, or delayed dismissal. No font browser, new search engine,
or redesign of Settings. No document preview or retained text. This prototype
proves the composing surface first, with the existing insertion and
cancellation rules intact.
