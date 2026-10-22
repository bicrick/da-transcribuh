# Clipboard history — design plan

**Status:** design only — **direction A locked** with **Maccy structural parity** (restyled in Paint ink). No app code until remaining open questions are answered.

**Parity source:** [p0deje/Maccy](https://github.com/p0deje/Maccy) SwiftUI (`ContentView`, `ListHeaderView`, `SearchFieldView`, `ListItemView`, `HistoryListView`, `FooterView`, `PreviewItemView`, `Popup` metrics).

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

### Layout (top → bottom) — match Maccy

Metrics from `Popup` / list views (pre-macOS 26): window ~**450**pt wide, **itemHeight 22**, **horizontal/verticalPadding 5**, search field height **23**, `imageMaxHeight` default **40**.

1. **Header** — muted title **`clipboard`** (lowercase Departure Mono; Maccy shows `Maccy`) left + square search field (Maccy’s rounded field → our square 2pt stroke): magnifier, placeholder **`type to search…`**, focused caret on open.
2. **List** — borderless, **no dividers between rows**. Pinned block on top with a single separator under pins (as Maccy’s PinsView + Divider). Then unpinned history.
3. **Footer** (Maccy `showFooter`) — quiet menu rows, not key-hint chrome: **Clear** (`⌥⌘⌫`), **Preferences…** (`⌘,`), **Quit** (`⌘Q`). (Clear all is the alternate Clear with modifiers — same as Maccy.)

### Row anatomy — match Maccy

- Text: single line, **middle-truncated**; no type glyphs / boxes
- Image: thumbnail only (natural aspect, max height ~40pt) — **no caption text** beside it
- `⌘1`…`⌘9` right, muted opacity ~0.7 — **only first nine**; rows 10+ have no shortcut
- Optional app icons: off by default (Maccy `showApplicationIcons`)
- Selected: full-width highlight with the same inset rhythm as Maccy; **ours = solid ink invert** (not accent blue)
- No per-row pin dots; pinning is section + ⌥P behavior

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

### Footer (Maccy menu, not hint strip)

Divider, then selectable rows: Clear / Preferences… / Quit with trailing shortcuts. No always-on key-hint bar.

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

**Metadata block** (match Maccy `PreviewItemView` copy):

| Field | Maccy label |
| --- | --- |
| Application | `Application:` (+ app name; session ingest may show `da transcribuh`) |
| First copy | `First copy time:` |
| Last copy | `Last copy time:` |
| Copies | `Number of copies:` |
| (images) | `Dimensions:` / `Size:` when applicable |
| Hints | `Press ⌥P to pin.` / `Press ⌥P to unpin.` · `Press ⌥⌫ to delete.` |

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

**Do not start until this design PR is approved and #19 is on `main`.** New module: `PromptAnnotator/Clipboard/` (store, watcher, list panel, preview popover, keyboard monitor, controller). Prefer reusing the existing stack below rather than inventing parallel paths.

### Reuse map (codebase exploration)

| Concern | Reuse |
| --- | --- |
| Paste into frontmost app | `PasteFollowUp` / `postCommandV()` (`CGEvent` ⌘V); stage via `SessionClipboard.writeTranscript` / `writeImage` |
| Auto-paste gating | `FocusPasteDecision` + `FocusedEditableProbe` / `AXIsProcessTrusted()` when relevant |
| Global hotkey | Carbon under signature `'PAnn'` — next free id (record=`1`, paste-follow-up=`2`, cancel=`3` → clipboard=`4`); mirror `PasteFollowUp.installHotKey` or extend `HotkeyCenter` |
| Bindable chord | `HotkeyChord` + `ShortcutCapture` + `AppSettings` setter; `canRegister(allowingShift: true)` for ⌘⇧C |
| Floating chrome | `ChromePanel` (`.nonactivatingPanel`); position with `NSEvent.mouseLocation` + clamp to `ScreenGeometry` / `visibleFrame` (today’s island uses screen-under-mouse top-center — history should be cursor-local) |
| Preview popover | Second nonactivating panel sibling; same Ink double-pane bevel as list |
| Persistence | **No SwiftData.** JSON index + image files under Application Support (same family as Whisper models / error log). Small prefs in `AppSettings` / UserDefaults (pattern: `CustomWhisperCatalog`) |
| Settings | First ship as `SettingsSection` on `ConfigurationPage` (General). Full `SettingsPage` tab only if needed (then update `tabOrder`, search catalog, `InkThemeTests`) |
| Session ingest | Hook after `SessionController.copyToClipboard()` / inside `SessionClipboard.copy` & `stageCombined` so every staged paste is recorded once; tag transcript vs screenshot |
| Own-write suppress | Wrap `SessionClipboard` general-board mutations so the watcher does not echo our writes |
| Ink | `Ink.stroke` 2, `Ink.bevelOffset` 3, `Ink.bevel`, `Ink.mono` / Departure Mono, `.inkDoublePane` |
| Tests | Named `NSPasteboard` (never `.general`); isolated `UserDefaults(suiteName:)`; `Runtime.isUnitTest` skips live Carbon/panels; cover dedupe, pin order, concealed skip, limit trim, search, Esc clear-then-close |

### Suggested land order

1. Store + watcher + AppSettings keys (no UI)
2. Panel A list + keyboard model + ⌘⇧C hotkey
3. Preview popover (~400ms)
4. Session ingest + menu bar row
5. General Clipboard card + onboarding Keybinds / Clipboard steps + Home checklist

## Related

- PR #19 — wordmark cursor removal + ⌥Space default (land first)
- Closed PR #20 — premature implementation; superseded by this design pass
- Design PR — this document + `assets/brand/mocks/clipboard-a-*`
