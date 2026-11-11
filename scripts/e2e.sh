#!/bin/bash
# End-to-end check of the built app: drives dist/Charms.app with real key
# events against the CharmsHarness text host and compares what arrives.
#
#   scripts/e2e.sh [scenario ...]      run all scenarios, or only the named ones
#
# Needs a built app (scripts/build-app.sh) and a terminal that has the
# Accessibility permission, which the app started from here inherits. It
# types and moves windows on the real screen for about four minutes: do not use
# the keyboard meanwhile. Charms runs with CHARMS_HOME pointing at a temporary
# directory, so your own favourites and settings are neither read nor changed.
#
# Exit status: 0 all passed, 1 a scenario failed, 77 could not run here.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${CHARMS_BUILD_DIR:-$ROOT/.build}"
APP="${CHARMS_APP:-$ROOT/dist/Charms.app}"
# Key code of the default shortcut, Control-P (the P position on any layout).
SHORTCUT_CODE=35

skip() { echo "e2e: $1" >&2; exit 77; }

[[ -x "$APP/Contents/MacOS/Charms" ]] || skip "no app at $APP; run scripts/build-app.sh first"
pgrep -x Charms >/dev/null && skip "Charms is already running; quit it first"

swift build --product CharmsHarness --scratch-path "$BUILD_DIR" >/dev/null || skip "the harness did not build"
HARNESS="$(swift build --product CharmsHarness --scratch-path "$BUILD_DIR" --show-bin-path)/CharmsHarness"

field() { plutil -extract "$1" raw -o - - 2>/dev/null; }

[[ "$("$HARNESS" focused | field trusted)" == "true" ]] \
    || skip "this terminal lacks the Accessibility permission (System Settings, Privacy & Security)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/charms-e2e.XXXXXX")"
TRACE="$WORK/trace.log"
HOST_PID=""
APP_PID=""
SAVED_CLIPBOARD="$(pbpaste 2>/dev/null || true)"

cleanup() {
    # `wait` collects them quietly; otherwise the shell reports each as
    # "Terminated".
    for pid in $APP_PID $HOST_PID; do
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    done
    printf '%s' "$SAVED_CLIPBOARD" | pbcopy
    rm -rf "$WORK"
}
trap cleanup EXIT

# The host runs from a bundle so that it has a bundle identifier, which the
# per-application settings are keyed by.
HOST_ID=ch.lkmc.CharmsHarness
HOST_APP="$WORK/CharmsHarness.app"
mkdir -p "$HOST_APP/Contents/MacOS"
cp "$HARNESS" "$HOST_APP/Contents/MacOS/CharmsHarness"
cat > "$HOST_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$HOST_ID</string>
<key>CFBundleName</key><string>Charms Harness</string>
<key>CFBundleExecutable</key><string>CharmsHarness</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
"$HOST_APP/Contents/MacOS/CharmsHarness" host --x 240 --y 860 > "$WORK/host.log" 2>&1 &
HOST_PID=$!

# Starts Charms with the given preferences document, replacing a running one.
CURRENT_PREFERENCES=""
start_charms() {
    [[ "$1" == "$CURRENT_PREFERENCES" ]] && return 0
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null
        wait "$APP_PID" 2>/dev/null
    fi
    printf '%s' "$1" > "$WORK/preferences.json"
    : > "$TRACE"
    CHARMS_HOME="$WORK" CHARMS_SKIP_ONBOARDING=1 CHARMS_TRACE=1 "$APP/Contents/MacOS/Charms" > /dev/null 2>> "$TRACE" &
    APP_PID=$!
    CURRENT_PREFERENCES="$1"
    for _ in $(seq 1 100); do
        grep -q "catalogue-loaded" "$TRACE" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

# --- helpers -----------------------------------------------------------------

send() { "$HARNESS" send "$@"; }
editor() { send --op state | field editor; }
press() { "$HARNESS" key --name "$@" >/dev/null; }
shortcut() { "$HARNESS" hotkey --code "$SHORTCUT_CODE" --control >/dev/null; }
typing() { "$HARNESS" type --text "$1" --gap-ms "${2:-25}" >/dev/null; }
clipboard() { "$HARNESS" pasteboard | field string; }
clipboard_count() { "$HARNESS" pasteboard | field changeCount; }

# Waits until the trace has a line matching $1 after line number $2.
await() {
    local pattern="$1" from="$2" tries=0
    while (( tries < 150 )); do
        tail -n +"$((from + 1))" "$TRACE" | grep -q -- "$pattern" && return 0
        sleep 0.02
        tries=$((tries + 1))
    done
    return 1
}
mark() { wc -l < "$TRACE" | tr -d ' '; }

# Puts the host in front with the given text and the caret at its end.
reset() {
    press escape
    send --op activate >/dev/null
    send --op focus --target editor >/dev/null
    send --op setText --text "$1" >/dev/null
    sleep 0.15
}

FAILURE=""
expect() {
    # expect <what> <actual> <wanted>; bash compares bytes, so canonically
    # equivalent but different strings do not pass for each other.
    [[ "$2" == "$3" ]] && return 0
    FAILURE="$1: got '$2', wanted '$3'"
    return 1
}

open_picker() {
    local from; from="$(mark)"
    shortcut
    await "presented-" "$from" || { FAILURE="the picker did not open"; return 1; }
}

choose() {
    # choose <query> [key options...]: type a query and press Return.
    local from; from="$(mark)"
    typing "$1"
    shift
    press return "$@"
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
}

# --- scenarios ---------------------------------------------------------------

scenario_insert() {
    reset "A "
    local count; count="$(clipboard_count)"
    open_picker && choose "arrow" || return 1
    expect "text" "$(editor)" "A →" || return 1
    expect "clipboard change count" "$(clipboard_count)" "$count" || return 1
    send --op undo >/dev/null
    expect "text after one undo" "$(editor)" "A "
}

scenario_escape() {
    reset "A "
    local count; count="$(clipboard_count)"
    open_picker || return 1
    typing "heart"
    press escape
    sleep 0.3
    expect "text" "$(editor)" "A " || return 1
    expect "clipboard change count" "$(clipboard_count)" "$count" || return 1
    expect "key window" "$(send --op state | field isKeyWindow)" "true"
}

scenario_replace_selection() {
    reset "A xyz"
    send --op select --location 2 --length 3 >/dev/null
    open_picker && choose "check" || return 1
    expect "text" "$(editor)" "A ✓"
}

scenario_sequence() {
    # A joined emoji sequence has to arrive scalar for scalar.
    reset ""
    open_picker && choose "technologist" || return 1
    expect "text" "$(editor)" "$(printf '\xf0\x9f\xa7\x91\xe2\x80\x8d\xf0\x9f\x92\xbb')"
}

scenario_navigate() {
    reset ""
    open_picker || return 1
    local from; from="$(mark)"
    typing "arrow"
    press right
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "←"
}

scenario_first_selected() {
    # Nothing typed, nothing moved: Return takes the first favourite.
    reset "A "
    open_picker || return 1
    local from; from="$(mark)"
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "A →"
}

scenario_copy() {
    reset "A "
    open_picker && choose "infinity" --command || return 1
    expect "text" "$(editor)" "A " || return 1
    expect "clipboard" "$(clipboard)" "∞"
}

scenario_placement() {
    # The picker is on the caret's display, beside the caret and not over
    # the line being typed.
    reset "The caret is at the end of this line"
    local caret picker
    caret="$("$HARNESS" focused)"
    open_picker || return 1
    picker="$("$HARNESS" windows --pid "$APP_PID")"
    press escape
    local cx cy ch px py pw ph index=0 found=""
    cx="$(field caretBounds.0 <<< "$caret")"; cy="$(field caretBounds.1 <<< "$caret")"; ch="$(field caretBounds.3 <<< "$caret")"
    # The status item is a window too; the picker is the wide one.
    while pw="$(field "windows.$index.bounds.2" <<< "$picker")" && [[ -n "$pw" ]]; do
        if awk "BEGIN { exit !($pw > 300) }"; then found="$index"; break; fi
        index=$((index + 1))
    done
    [[ -n "$found" ]] || { FAILURE="no picker window on screen"; return 1; }
    px="$(field "windows.$found.bounds.0" <<< "$picker")"; py="$(field "windows.$found.bounds.1" <<< "$picker")"
    ph="$(field "windows.$found.bounds.3" <<< "$picker")"
    awk "BEGIN { exit !(($py >= $cy + $ch) || ($py + $ph <= $cy)) }" \
        || { FAILURE="picker (y $py, height $ph) covers the caret line (y $cy, height $ch)"; return 1; }
    awk "BEGIN { exit !($px <= $cx && $cx <= $px + $pw) }" \
        || { FAILURE="picker (x $px, width $pw) is not at the caret (x $cx)"; return 1; }
}

# Top-left corner of the picker window while it is open, as "x y".
picker_origin() {
    local windows index=0 width
    windows="$("$HARNESS" windows --pid "$APP_PID")"
    while width="$(field "windows.$index.bounds.2" <<< "$windows")" && [[ -n "$width" ]]; do
        if awk "BEGIN { exit !($width > 300) }"; then
            echo "$(field "windows.$index.bounds.0" <<< "$windows") $(field "windows.$index.bounds.1" <<< "$windows")"
            return 0
        fi
        index=$((index + 1))
    done
    return 1
}

scenario_click_cell() {
    reset ""
    open_picker || return 1
    local from origin px py
    from="$(mark)"
    typing "arrow"
    sleep 0.2
    origin="$(picker_origin)" || { FAILURE="no picker window on screen"; return 1; }
    read -r px py <<< "$origin"
    # Second result: masthead 32, search 46, proof 154, grid padding 19,
    # heading 12 + gap 8; cells 44 with 6 between. See PickerViewModel.
    "$HARNESS" click --x "$(awk "BEGIN { print $px + 19 + 50 + 22 }")" --y "$(awk "BEGIN { print $py + 32 + 46 + 154 + 19 + 12 + 8 + 22 }")" >/dev/null
    await "outcome-" "$from" || { FAILURE="the click did not end the session"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "←"
}

scenario_hover_keeps_selection() {
    reset ""
    open_picker || return 1
    typing "arrow"
    local from origin px py
    from="$(mark)"
    origin="$(picker_origin)" || { FAILURE="no picker window on screen"; return 1; }
    read -r px py <<< "$origin"
    "$HARNESS" mouse --x "$(awk "BEGIN { print $px + 19 + 50 + 22 }")" --y "$(awk "BEGIN { print $py + 32 + 46 + 154 + 19 + 12 + 8 + 22 }")" >/dev/null
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text after hovering the second result" "$(editor)" "→"
}

scenario_no_results() {
    reset "A "
    local count; count="$(clipboard_count)"
    open_picker || return 1
    typing "zzzznocharactermatcheszzzz"
    press return
    expect "text with no selection" "$(editor)" "A " || return 1
    expect "clipboard change count" "$(clipboard_count)" "$count" || return 1
    picker_origin >/dev/null || { FAILURE="Return closed an empty picker"; return 1; }
    # Select back to the start of the native query, without a layout-specific
    # key code for Select All. Typing must still edit normally after Return.
    press left --command --shift
    choose "arrow" || return 1
    expect "text after correcting the query" "$(editor)" "A →"
}

scenario_preview_guides() {
    reset "A "
    open_picker && choose "U+0301" || return 1
    expect "combining mark without the dotted-circle guide" "$(editor)" "$(printf 'A \314\201')" || return 1
    reset "A "
    open_picker && choose "U+00A0" || return 1
    expect "space without the open-box guide" "$(editor)" "$(printf 'A \302\240')"
}

scenario_keyboard_menu() {
    reset ""
    open_picker || return 1
    typing "infinity"
    local from; from="$(mark)"
    "$HARNESS" pasteboard --set "MENU_PROBE" >/dev/null
    press return --control
    press down
    press return
    await "outcome-dispatched" "$from" || { FAILURE="Control-Return did not open the character action menu"; press escape; return 1; }
    sleep 0.15
    expect "text after the first character-menu action" "$(editor)" "∞"
}

scenario_click_proof() {
    reset "A "
    local count origin px py
    count="$(clipboard_count)"
    open_picker || return 1
    typing "arrow"
    origin="$(picker_origin)" || { FAILURE="no picker window on screen"; return 1; }
    read -r px py <<< "$origin"
    "$HARNESS" click --x "$(awk "BEGIN { print $px + 80 }")" --y "$(awk "BEGIN { print $py + 130 }")" >/dev/null
    expect "text after clicking the specimen" "$(editor)" "A " || return 1
    expect "clipboard change count" "$(clipboard_count)" "$count" || return 1
    picker_origin >/dev/null || { FAILURE="clicking the proof closed the picker"; return 1; }
    press escape
}

scenario_click_outside() {
    # A click anywhere else closes the picker and changes nothing.
    reset "A "
    open_picker || return 1
    local from frame height x y
    from="$(mark)"
    typing "arrow"
    frame="$(send --op state)"
    height="$("$HARNESS" displays | field displays.0.frame.3)"
    x="$(awk "BEGIN { print $(field windowFrame.0 <<< "$frame") + $(field windowFrame.2 <<< "$frame") / 2 }")"
    # The title bar of the host window, converted to top-left coordinates.
    y="$(awk "BEGIN { print $height - ($(field windowFrame.1 <<< "$frame") + $(field windowFrame.3 <<< "$frame")) + 12 }")"
    "$HARNESS" click --x "$x" --y "$y" >/dev/null
    await "outcome-cancelled" "$from" || { FAILURE="clicking outside did not cancel"; return 1; }
    expect "text" "$(editor)" "A "
}

scenario_cancel_while_held() {
    # Escape pressed while Return is still down. The picker keeps the
    # keyboard until Return comes up, so that the held key cannot repeat
    # into the document; then it closes without inserting.
    reset "A "
    open_picker || return 1
    local from holder; from="$(mark)"
    typing "arrow"
    "$HARNESS" key --name return --hold-ms 900 >/dev/null &
    holder=$!
    sleep 0.25
    press escape
    if ! picker_origin >/dev/null; then
        wait "$holder"
        FAILURE="the picker closed while Return was still held"
        return 1
    fi
    wait "$holder"
    await "outcome-cancelled" "$from" || { FAILURE="the session was not cancelled"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "A "
}

scenario_paste_backend() {
    # For applications set to "insert by pasting".
    reset "A "
    "$HARNESS" pasteboard --set "KEEP" >/dev/null
    local from; from="$(mark)"
    open_picker && choose "arrow" || return 1
    expect "text" "$(editor)" "A →" || return 1
    tail -n +"$((from + 1))" "$TRACE" | grep -q "sent-paste" || { FAILURE="the paste backend was not used"; return 1; }
    sleep 1
    # The clipboard is put back unless the system would have had to ask
    # before letting Charms read it; then it is left alone.
    if ! tail -n +"$((from + 1))" "$TRACE" | grep -q "clipboard-snapshot-skipped"; then
        expect "clipboard after restore" "$(clipboard)" "KEEP" || return 1
    fi
}

scenario_pass_through() {
    # In a listed application the shortcut belongs to that application:
    # Control-P moves the caret up a line there and Charms stays closed.
    reset "$(printf 'one\ntwo')"
    local from; from="$(mark)"
    shortcut
    sleep 0.4
    if tail -n +"$((from + 1))" "$TRACE" | grep -q "invoked-"; then
        FAILURE="the picker opened in a pass-through application"
        return 1
    fi
    expect "caret position" "$(send --op state | field editorSelection.0)" "3"
}

scenario_typed_trigger() {
    reset "x "
    local from; from="$(mark)"
    typing "::arrow"
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "x →"
}

scenario_typed_trigger_first_selected() {
    # The colons alone and Return: the first favourite is already selected.
    # (With Tab in between this worked before as well, since Tab selects.)
    reset "x "
    local from; from="$(mark)"
    typing "::"
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "x →"
}

scenario_typed_trigger_late_selection() {
    # Chromium applies a selection made through Accessibility a moment
    # after the call returns. The colons must still be replaced.
    reset "x "
    send --op selectionDelay --ms 30 >/dev/null
    local from ended=0; from="$(mark)"
    typing "::arrow"
    await "presented-" "$from" || { send --op selectionDelay --ms 0 >/dev/null; FAILURE="typing :: did not open the picker"; return 1; }
    press return
    await "outcome-" "$from" || ended=1
    sleep 0.15
    send --op selectionDelay --ms 0 >/dev/null
    (( ended == 0 )) || { FAILURE="the session did not end"; return 1; }
    expect "text" "$(editor)" "x →"
}

scenario_typed_trigger_focus_moves_during_selection() {
    # While the selection is on its way, another field of the same
    # application takes the keyboard. The first field still ends up with the
    # colons selected, but nothing may be sent: it would land in the other.
    reset "x "
    send --op selectionDelay --ms 60 --target field >/dev/null
    local from blocked=0 closed=0; from="$(mark)"
    typing "::arrow"
    await "presented-" "$from" || { send --op selectionDelay --ms 0 >/dev/null; FAILURE="typing :: did not open the picker"; return 1; }
    press return
    await "blocked-focus-moved" "$from" || blocked=1
    sleep 0.3
    press escape
    await "outcome-cancelled" "$from" || closed=1
    send --op selectionDelay --ms 0 >/dev/null
    local other; other="$(send --op state | field field)"
    expect "the other field" "$other" "" || return 1
    (( blocked == 0 )) || { FAILURE="the insertion was not blocked for the moved focus"; return 1; }
    (( closed == 0 )) || { FAILURE="Escape did not end the session"; return 1; }
    expect "text" "$(editor)" "x ::"
}

scenario_typed_trigger_selection_refused() {
    # A field that accepts the selection call and never honours it: nothing
    # is sent, the picker comes back for copying, and a second Return copies.
    reset "x "
    send --op selectionDelay --ms -1 >/dev/null
    local from refused=0 copied=0; from="$(mark)"
    typing "::arrow"
    await "presented-" "$from" || { send --op selectionDelay --ms 0 >/dev/null; FAILURE="typing :: did not open the picker"; return 1; }
    press return
    await "blocked-selection-refused" "$from" || refused=1
    sleep 0.2
    press return
    await "outcome-copied" "$from" || copied=1
    send --op selectionDelay --ms 0 >/dev/null
    (( refused == 0 )) || { press escape; FAILURE="the refusal was not recorded"; return 1; }
    (( copied == 0 )) || { press escape; FAILURE="the second Return did not copy"; return 1; }
    expect "clipboard" "$(clipboard)" "→" || return 1
    # The name was typed into the picker; the field holds the colons only.
    expect "text" "$(editor)" "x ::"
}

scenario_typed_trigger_fast() {
    reset "x "
    local from; from="$(mark)"
    typing "::check" 6
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    sleep 0.3
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "x ✓"
}

scenario_typed_trigger_escape() {
    # Escape leaves the colons exactly as typed.
    reset "x "
    local from; from="$(mark)"
    typing "::ar"
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    press escape
    sleep 0.3
    expect "text" "$(editor)" "x ::"
}

scenario_colons_inside_a_word() {
    reset ""
    local from; from="$(mark)"
    typing "std::cout"
    sleep 0.4
    expect "text" "$(editor)" "std::cout" || return 1
    if tail -n +"$((from + 1))" "$TRACE" | grep -q "invoked-"; then
        FAILURE="colons inside a word opened the picker"
        return 1
    fi
}

scenario_password_field() {
    # Nothing is ever sent into a password field; Return copies instead.
    reset "A "
    send --op focus --target secret >/dev/null
    sleep 0.15
    open_picker && choose "arrow" || return 1
    expect "password field length" "$(send --op state | field secretLength)" "0" || return 1
    expect "text" "$(editor)" "A " || return 1
    expect "clipboard" "$(clipboard)" "→"
}

scenario_snippet_insert() {
    reset "A "
    local count; count="$(clipboard_count)"
    open_picker && choose "shrug" || return 1
    expect "snippet text" "$(editor)" 'A ¯\_(ツ)_/¯' || return 1
    expect "clipboard change count" "$(clipboard_count)" "$count" || return 1
    send --op undo >/dev/null
    expect "snippet after one undo" "$(editor)" "A "
}

scenario_snippet_typed() {
    reset "x "
    local from; from="$(mark)"
    typing "::shrug" 6
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    sleep 0.2
    press return
    await "outcome-dispatched" "$from" || { FAILURE="the snippet was not dispatched"; return 1; }
    sleep 0.15
    expect "typed snippet" "$(editor)" 'x ¯\_(ツ)_/¯'
}

scenario_snippet_escape() {
    reset "x "
    local from count before; from="$(mark)"; count="$(clipboard_count)"
    before="$(shasum "$WORK/library.json")"
    typing "::"
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    typing "shrug"
    press escape
    await "outcome-cancelled" "$from" || { FAILURE="Escape did not cancel the snippet"; return 1; }
    expect "source after Escape" "$(editor)" "x ::" || return 1
    expect "clipboard after Escape" "$(clipboard_count)" "$count" || return 1
    expect "library after Escape" "$(shasum "$WORK/library.json")" "$before"
}

scenario_snippet_copy() {
    reset "A "
    open_picker && choose "shrug" --command || return 1
    expect "source after copying snippet" "$(editor)" "A " || return 1
    expect "copied snippet" "$(clipboard)" '¯\_(ツ)_/¯'
}

scenario_snippet_starters() {
    # Read the shipped list through actual first-run storage. read -r and a
    # tab-only separator preserve backslashes and spaces in every payload.
    local query replacement cases="$WORK/snippet-cases.tsv"
    python3 - "$WORK/snippets.json" > "$cases" <<'PY'
import json, sys
snippets = [s for s in json.load(open(sys.argv[1]))['snippets']
            if s['id'].upper().startswith('43686172-6D73-4000-8000-')]
assert len(snippets) == 20
for snippet in snippets:
    print(snippet['shortcut'] + '\t' + snippet['text'])
PY
    [[ $? == 0 ]] || { FAILURE="the starter fixture did not load"; return 1; }
    while IFS=$'\t' read -r query replacement; do
        reset ""
        open_picker && choose "$query" || return 1
        expect "starter $query" "$(editor)" "$replacement" || return 1
    done < "$cases"
}

scenario_snippet_custom() {
    # A saved custom string takes the same real storage/search/dispatch path.
    # Stop before writing the fixture; Settings editing is checked manually.
    kill "$APP_PID"; wait "$APP_PID" 2>/dev/null || true
    APP_PID=""; CURRENT_PREFERENCES=""
    python3 - "$WORK/snippets.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data['snippets'] = [s for s in data['snippets'] if s['shortcut'] != 'sampletext']
data['snippets'].append(dict(id='00000000-0000-4000-8000-000000000001',
    shortcut='sampletext', name='Exact sample', text=' \u212b e\u0301 👩🏽‍💻  '))
with open(path, 'w') as file:
    json.dump(data, file)
PY
    start_charms "$(preferences_for snippet_custom)" || { FAILURE="custom snippets did not load"; return 1; }
    reset "A "
    open_picker && choose "sampletext" || return 1
    expect "exact custom text" "$(editor)" 'A  Å é 👩🏽‍💻  '
}

snippet_toggle_favourite() {
    press return --control
    press down; press down; press down
    press return
    sleep 0.1
}

shrug_is_favourite() {
    python3 - "$WORK/library.json" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))['favourites']
sys.exit(0 if any(s['string'] == r'¯\_(ツ)_/¯' for s in items) else 1)
PY
}

scenario_snippet_favourite() {
    reset ""
    open_picker || return 1
    typing "shrug"
    if shrug_is_favourite; then snippet_toggle_favourite; fi
    snippet_toggle_favourite
    shrug_is_favourite || { FAILURE="snippet favourite was not saved"; return 1; }
    press escape
    reset ""
    open_picker || return 1
    local from; from="$(mark)"
    # Eight original favourites, then the snippet: Down from the first
    # block lands on it. Its saved presentation must still be text.
    press down
    press return
    await "outcome-dispatched" "$from" || { FAILURE="saved snippet was not dispatched"; return 1; }
    sleep 0.15
    expect "saved favourite text" "$(editor)" '¯\_(ツ)_/¯' || return 1
    open_picker || return 1
    typing "shrug"
    snippet_toggle_favourite
    press escape
}

scenario_snippet_paste() {
    reset "A "
    local from; from="$(mark)"
    open_picker && choose "shrug" || return 1
    expect "pasted snippet" "$(editor)" 'A ¯\_(ツ)_/¯' || return 1
    tail -n +"$((from + 1))" "$TRACE" | grep -q "sent-paste" || { FAILURE="the paste backend was not used"; return 1; }
    sleep 1
}

# Exercise the native query editor, exact sequences, guides, cancellation and
# keyboard menus under every palette and both explicit appearances. Preferences
# are loaded through the real storage boundary, not injected into the views.
scenario_theme_impression_light() { theme_round_trip; }
scenario_theme_impression_dark() { theme_round_trip; }
scenario_theme_blueprint_light() { theme_round_trip; }
scenario_theme_blueprint_dark() { theme_round_trip; }
scenario_theme_plum_light() { theme_round_trip; }
scenario_theme_plum_dark() { theme_round_trip; }

theme_round_trip() {
    scenario_navigate && scenario_escape && scenario_sequence && scenario_preview_guides && scenario_keyboard_menu && scenario_snippet_insert
}

ALL=(insert escape replace_selection sequence navigate first_selected copy placement click_cell click_outside
     hover_keeps_selection no_results preview_guides click_proof keyboard_menu
     cancel_while_held typed_trigger typed_trigger_first_selected typed_trigger_late_selection
     typed_trigger_focus_moves_during_selection typed_trigger_selection_refused typed_trigger_fast
     typed_trigger_escape colons_inside_a_word password_field
     paste_backend pass_through
     snippet_insert snippet_typed snippet_escape snippet_copy snippet_starters snippet_favourite snippet_custom snippet_paste
     theme_impression_light theme_impression_dark theme_blueprint_light theme_blueprint_dark
     theme_plum_light theme_plum_dark)

# The preferences a scenario runs with. Charms is restarted when they change.
preferences_for() {
    case "$1" in
        paste_backend|snippet_paste) echo "{\"pasteApplications\": [\"$HOST_ID\"]}" ;;
        pass_through) echo "{\"shortcutPassThrough\": [\"$HOST_ID\"]}" ;;
        theme_*)
            local theme="${1#theme_}"
            echo "{\"typedTriggerEnabled\": true, \"pickerTheme\": \"${theme%_*}\", \"pickerAppearance\": \"${theme##*_}\"}"
            ;;
        *) echo '{"typedTriggerEnabled": true}' ;;
    esac
}

# --- run ---------------------------------------------------------------------

for _ in $(seq 1 100); do
    grep -q '"ready"' "$WORK/host.log" 2>/dev/null && break
    sleep 0.1
done
grep -q '"ready"' "$WORK/host.log" 2>/dev/null || skip "the test window did not open"
start_charms "$(preferences_for insert)" || skip "Charms did not start"
grep -q "insertion-enabled" "$TRACE" || skip "Charms started without the Accessibility permission"

failed=0
for name in "${@:-${ALL[@]}}"; do
    declare -F "scenario_$name" >/dev/null || { echo "e2e: unknown scenario '$name'" >&2; exit 2; }
    FAILURE=""
    start_charms "$(preferences_for "$name")" || { echo "FAIL  $name: Charms did not restart"; failed=1; continue; }
    # Another application taking the foreground cancels a session, as it
    # should. That is the screen's doing, not the app's: try once more.
    if "scenario_$name" || { sleep 1; FAILURE=""; "scenario_$name"; }; then
        echo "ok    $name"
    else
        echo "FAIL  $name: $FAILURE"
        # What the app recorded last, to see where the session went.
        tail -n 12 "$TRACE" | sed 's/^/        /'
        failed=1
    fi
done
press escape

exit "$failed"
