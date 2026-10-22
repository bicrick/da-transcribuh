# Clipboard history — design plan

**Status:** design only — **direction A locked** (compact Maccy-like list at the cursor + delayed preview popover). No app code until remaining open questions are answered.

**Defaults:** recording **⌥Space**; clipboard panel **⌘⇧C** (both customizable). Reserved system chords: **⌘Space**, **⌥⌘Space** only.

**Mocks:** `assets/brand/mocks/clipboard-a-*.png` and `/opt/cursor/artifacts/clipboard-a-*-2x.png` — light + dark for each panel state, plus General Clipboard settings and the two onboarding steps.

---

## Goals

1. Maccy-style clipboard history in da transcribuh’s MS Paint chrome (Departure Mono, 2pt `Ink.stroke`, square edges, 3pt hard offset bevel — black in light / `#F2F2F2` in graphite dark).
2. One place for (a) copies from other apps, (b) session **transcripts**, (c) session **screenshots/tiles**.
3. Fully keyboard-navigable like Maccy: open → type to search → arrows → Enter to paste, without touching the mouse.
4. Paste-back via the Accessibility grant already required for paste follow-up — no new permission prompt.
5. Discoverable in onboarding (keybinds + clipboard steps) and toggleable in General.

Non-goals for v1: cloud sync, preview side-pane (direction B), grid/filmstrip (direction C), OCR, multi-device.

---

## How it works

### Pasteboard polling

- Poll `NSPasteboard.general.changeCount` (~0.5s) while enabled.
- On change: read string / PNG·TIFF / file URL types; fingerprint; dedupe by bumping an existing match to the top.
- Skip concealed / auto-generated / transient types (password managers, one-shot OS payloads).
- Skip our own write-backs via begin/end suppress around session export and history pick.

### Storage

- Application Support: `…/PromptAnnotator/ClipboardHistory/`
  - `index.json` — id, kind, source, preview, fingerprint, pinned, timestamps, image path
  - `images/` — PNG files for image clips
- Soft limit (default TBD, ~200); trim oldest **unpinned**. Clear keeps pinned.

### Paste-back (Accessibility)

- **Enter** / click: write to general pasteboard, then simulate **⌘V** (same path as paste follow-up).
- **⌥Enter**: copy only — no paste simulation.
- Shares Accessibility already granted for paste / global shortcuts / Shift-draw. Never re-prompt as a fourth permission.

### Session ingest

| Source tag   | When                         | Kind  |
| ------------ | ---------------------------- | ----- |
| `Copied`     | External pasteboard change   | text / image / file URL |
| `Transcript` | Session stop writes words    | text  |
| `Screenshot` | Session tile / capture write | image |

Combined image+text staging → **two rows** (screenshot + transcript) so source tags stay filterable later if needed. v1 panel is a single All list (no source tabs).

---

## Panel A — compact list at the cursor

Narrow floating non-activating panel (~360pt) near the pointer. Double-pane bevel on the chrome. Square rows, 2pt selected outline, Departure Mono throughout.

### Layout (top → bottom)

1. **Search field** — always key-focus when the panel opens. No click required to type.
2. **List** — pinned items first (pin glyph), then recents. Mixed rows: plain text, code, URL, transcript tag, screenshot thumbnail.
3. **One-line key-hint footer** — condensed chords (see below).

### Row anatomy

- Leading: optional `⌘1`…`⌘9` digit (first nine visible / filtered rows)
- Kind glyph in a 2pt square: `T` text, `{` code, `⌘` URL hint, or a tiny screenshot thumb
- Preview (single line, truncated)
- Trailing: source tag (`words` / `tile` / empty for plain copies) and pin mark when pinned
- Selected row: 2pt `Ink.label` outline + fill well

### Sample content (mocks)

- Pinned: `API_KEY=…` (concealed types never land; this is a normal pinned string for UI)
- Code: `func paste() { simulateCommandV() }`
- URL: `https://github.com/bicrick/da-transcribuh`
- Transcript: “okay so the island bevel should invert in dark mode…”
- Screenshot: thumbnail tile tagged `tile`
- Plain: meeting notes, prompt snippets

---

## Keyboard model (Maccy-like)

Panel opens from **⌘⇧C** (customizable). Focus is on search immediately. Character keys go **straight into search** — there is no separate “focus search” step and no need to click the field.

| Input | Action |
| --- | --- |
| *any character* / paste into field | Append to search query; filter list live; selection resets to first match |
| `⌫` (search non-empty) | Delete last search character |
| `↑` or `⌃P` | Move selection up |
| `↓` or `⌃N` | Move selection down |
| `Enter` | Paste selected into frontmost app (write + simulate ⌘V); close panel |
| `⌥Enter` | Copy selected only (no paste); keep panel open |
| `⌘1` … `⌘9` | Instant pick that numbered row (paste + close) |
| `⌥P` | Pin / unpin selected |
| `⌥⌫` | Delete selected from history |
| `Esc` | If search non-empty → clear search; if search empty → close panel |
| `⌘,` | Open Settings → General (Clipboard card); close panel |

### Footer (one line)

Always visible, secondary ink, Departure Mono ~9–10pt:

`↑↓ ⌃N⌃P · ↩ paste · ⌥↩ copy · ⌘1–9 · ⌥P pin · ⌥⌫ · Esc · ⌘,`

(Exact glyph packing may tighten in implementation; mocks use this model.)

### Focus / activation notes

- Non-activating panel so the target app stays frontmost until paste runs.
- Local key monitor (or equivalent) while panel is visible — same family as other floating chrome.
- `⌘1`–`⌘9` map to **currently filtered / visible** order (pinned still first within the filter).
- Mouse still works: click row to select, double-click or Enter to paste, hover optional.

### Preview popover (Maccy-style)

A second floating plate appears **beside the list** when a row is **hovered or keyboard-selected**, after a short delay (~**400ms**) so arrowing through the list does not flash previews.

**Placement:** prefer the side with more room (right of the list if the panel is in the left half of the display, else left). Keep a small gutter (~8pt) from the list chrome; align roughly with the selected row, then clamp vertically so the popover stays on-screen.

**Chrome:** same Paint language as the list — square corners, 2pt `Ink.stroke`, 3pt hard offset bevel (black in light / `#F2F2F2` in dark), Departure Mono, graphite surfaces. Independent non-activating window (or sibling view) so it does not steal key focus from search.

**Content by kind:**

| Kind | Preview body |
| --- | --- |
| Screenshot / image | Large scaled image (letterboxed inside the popover) |
| Plain text / transcript | Wrapped body text |
| Code-like text | Wrapped **monospaced** block (Departure Mono) |
| URL | Full URL string, wrapped; no truncated single-line |

**Metadata block** (below the preview, separated by a 1pt hairline):

| Field | Examples |
| --- | --- |
| Source | Frontmost app name at copy time (`Safari`, `Cursor`), or **`da transcribuh · transcript`** / **`da transcribuh · screenshot`** for session ingest |
| First copied | Absolute or relative timestamp |
| Last copied | Absolute or relative timestamp (same as first until re-copied / dedupe bump) |
| Copies | Integer count of times this fingerprint was seen |
| Key hints | `⌥P pin/unpin` · `⌥⌫ delete` (and optionally `↩ paste` · `⌥↩ copy`) |

**Behavior notes:**

- Delay resets when selection/hover changes; hide immediately when the panel closes, Esc clears/closes, or the pointer leaves both list and popover (with a small grace so moving into the popover does not dismiss).
- Empty / no-match states: no popover.
- Pin and delete from the keyboard still apply to the selected row while the popover is visible; the popover updates after pin/delete.
- Popover is **read-only** — no editable fields; clicks on it do not paste (Enter / ⌘N still target the list selection).

Mocks: `clipboard-a-preview-image-{light,dark}`, `clipboard-a-preview-text-{light,dark}` (list + popover composed).

---

## Global shortcut

| Chord | Role |
| --- | --- |
| **⌥Space** (default) | Start / stop recording |
| **⌘⇧C** (default) | Toggle clipboard panel |
| ⌘Space / ⌥⌘Space | Reserved — reject in chord editors |

Clipboard chords **may include Shift**; recording chords may not (Shift is for drawing).

---

## Settings (General) — Clipboard card

Mocked in this PR:

- Enable clipboard history (default on — open question)
- Chord editor + “click to rebind” + Reset to ⌘⇧C
- History limit
- Clear history (keeps pinned)
- Footer: Accessibility for paste already covers this — no extra grant

---

## Onboarding

Two new steps (mocks in this PR), after Permissions:

### Keybinds

- Recording: ⌥Space chord editor
- Clipboard: ⌘⇧C chord editor (Shift allowed)
- Reserved-chord copy; “click to rebind” / Listening states

### Clipboard history

- Intro to compact history at the cursor
- Enable toggle
- Keyboard teaser (type to search · Enter pastes)
- Explicit: Accessibility already granted for paste — nothing new to ask

Suggested order:

`Welcome → Permissions → Keybinds → Clipboard → Appearance → Model → Practice → Ready`

Home get-started checklist should gain a Clipboard item when implemented.

---

## Rendered states (direction A)

Each light + dark @2×:

| State | File stem |
| --- | --- |
| Default list (mixed rows, pinned on top, selection on first unpinned) | `clipboard-a-default` |
| Selected row emphasis | `clipboard-a-selected` |
| Search filtering + match highlight | `clipboard-a-search` |
| Empty state | `clipboard-a-empty` |
| Long / scrolling list | `clipboard-a-scroll` |
| Preview popover · screenshot/image | `clipboard-a-preview-image` |
| Preview popover · text/code | `clipboard-a-preview-text` |
| Settings Clipboard section | `clipboard-a-settings` |
| Onboarding Keybinds step | `clipboard-a-onboarding-keybinds` |
| Onboarding Clipboard step | `clipboard-a-onboarding-clipboard` |

Contact sheets: `clipboard-a-states-{light,dark}-2x.png`, `clipboard-a-preview-{light,dark}-2x.png`, `clipboard-a-onboarding-{light,dark}-2x.png`.

---

## Edge cases

| Case | Behavior |
| --- | --- |
| Concealed pasteboard types | Skip — never store |
| Own pasteboard write | Suppress watcher |
| Duplicate content | Dedupe — bump to top |
| Session image + text | Two tagged rows |
| Feature disabled | Unregister hotkey; hide panel; stop watcher; keep disk |
| Limit reached | Drop oldest unpinned |
| Accessibility off | Copy still works; paste simulation fails with existing recovery copy |
| Chord equals record/cancel | Reject |
| Esc with query | Clear first, second Esc closes |
| Empty history | Empty state copy + still show search + footer |
| No search matches | Empty filter state (“No matches”) |
| Preview delay while arrowing | ~400ms; previous popover hides on selection change |
| Panel near screen edge | Flip popover to the side with room; clamp vertically |
| Unknown source app | Show `Copied` or bundle-id fallback — open question |

---

## Open questions (remaining)

1. **Default enabled?** On vs off.
2. **History limit default** — 100 / 200 / 500?
3. **⌥Enter after copy** — keep panel open (proposed) or close?
4. **Menu bar row** when enabled — yes / hotkey only?
5. **Retention** — limit only, or optional auto-expire days?
6. **Match highlight** — bold/underline glyphs vs Paint fill bar behind match span?
7. **Preview delay** — stick with ~400ms, or make it a hidden default / setting?
8. **Source app** — store bundle name at copy time always, or only when available?

---

## Implementation notes (after sign-off)

- `PromptAnnotator/Clipboard/` — store, watcher, panel, keyboard monitor, controller.
- Reuse `PasteFollowUp.simulateCommandV`, nonactivating panel patterns, `Ink*`.
- `HotkeyChord.canRegister(allowingShift:)` for clipboard only.
- Tests: dedupe, pin order, concealed skip, limit trim, search filter, Esc clear-then-close.
- Land only after #19 is on `main` and this design PR is approved.

## Related

- PR #19 — wordmark cursor removal + ⌥Space default (land first)
- Closed PR #20 — premature implementation; superseded by this design pass
