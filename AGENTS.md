# Agent notes — da transcribuh

Branch discipline: work on `overnight-audit` only. Never ship or merge `promo-video`.

## Chrome vs overlay

Settings, onboarding, and the menu-bar panel share the **Ink** design system (`PromptAnnotator/Settings/Ink/`).

The whole app is an **MS Paint** theme: manila **folder tabs** (not a toolbox sidebar), flat classic swatches where functional, chunky outlines, hard shadows, Departure Mono chrome. Decorative palette strips are gone from the title bar, status bar, onboarding chrome, and menu panel. The **recording island**, **waveform**, **markup toolbar**, and **selection overlay** share that language. Keep hit targets, animations, and annotation ink colors intact; do not add timers or heavy per-frame effects to the waveform/overlay path.

### Brand mark

`InkDtMark` / AppIcon: Departure Mono lowercase **d** + inverted **t** block inside a square with a hard-offset bevel.

| | Light | Dark |
| --- | --- | --- |
| Tile (`markFace`) | `#FFFFFF` | `#3A3A3D` |
| “d” + outer hairline (`markInk`) | `#000000` | `#F2F2F2` |
| “t” block (`markInvertFace`) | `#000000` | `#F2F2F2` |
| “t” letter (`markInvertInk`) | `#FFFFFF` | `#3A3A3D` |
| Bevel | `Ink.bevel` | `Ink.bevel` (`#1A1A1C`) |

AppIcon / README brand PNGs stay the light plate (white square). In-app mark follows the tokens above. Regenerate AppIcon with `scripts/render_dt_icon.py`.

### Dark graphite tokens

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#2C2C2E` |
| `fill` / `card` (raised) | `#F0F0F0` / `#FFFFFF` | `#353538` |
| `front` / `tileFace` / `keycap` | `#FFFFFF` | `#3A3A3D` |
| `hairline` | `#C0C0C0` | `#4A4A4E` |
| `label` / `onTile` | `#000000` | `#F2F2F2` |
| `secondary` | `#666666` | `#A8A8AD` |
| `primaryFill` (Start invert — pop) | `#000000` | `#F2F2F2` |
| `onPrimary` | `#FFFFFF` | `#2C2C2E` |
| `statRule` (Home stats underline) | `#000000` | `#A8A8AD` |
| `controlBorder` | `#000000` | `#F2F2F2` |
| `bevel` (double-pane offset) | `#000000` | `#1A1A1C` |

Nothing in chrome should paint darker than `#1A1A1C` except the bevel itself. Route surfaces through `Ink.*` — no hard-coded `Color.white` / `Color.black` for chrome controls (functional Paint swatches, annotation ink, and export canvases are the exceptions).

### Copy / Home

Home keeps the pre-declutter structure (stats grid, Get Started checklist, tip tiles). Nits only: no yellow version badge (status bar has it), no hero tagline, no “^⌥Space starts…” caption under Start. Stat underlines are neutral (`Ink.statRule`). Start / primary stays high-contrast invert (`primaryFill` / `onPrimary`: black↔`#F2F2F2`), not a flat graphite plate.

Folder tabs are Chrome-style (`FolderTabShape`: 6pt top corners + 6pt concave feet, same height/baseline). The shelf rule and selected tab outline are **one continuous 1pt path** stroked in the selected tab’s accent (`SettingsPage.tabAccent` / `Ink.tabStroke*`, lifted in dark; Appearance = purple). Unselected tabs use `Ink.hairline` outlines. Selected fill is `Ink.front` and merges into the page. README mocks: `scripts/render_home_mocks.py`.

### Home after Get Started

`HomeGetStartedStore` (`home.getStarted.complete`) dismisses the checklist permanently once all three steps are done. Mark + Start stay; the body below is a **bento grid** of `HomeBentoCell`s (`Ink.front` face, 1pt `Ink.label` border, `Ink.bevel` offset, Departure Mono caption headers, `Ink.space3` gutters):

1. **Stats** — four equal cells (Sessions / Tiles / Words / Minutes); short tick under the number. Narrow → 2×2.
2. **RECENT (~2/3) + THIS WEEK (~1/3)** — last 4 session rows (hover Copy; click → History) beside a compact week chart (bars ~12pt, 6pt gaps; today `Ink.paintRed`; week total + best-day caption in the cell). Narrow → stack. While Get Started is incomplete it occupies this row as one full-width cell (checklist look unchanged).
3. **CAPTURE + FOLDER** — same tip actions as cells; quiet status caption lives at the bottom of CAPTURE (red-dot + Fix when needed). Regressions never revive the checklist.

Helpers: `SessionLibrary.recent`, `weeklyWordCounts`, `recentWhen`, `thumbnailURL`.

## Typography

- Chrome labels: Departure Mono (`DepartureMono-Regular`, `ATSApplicationFontsPath=Fonts`)
- Long body/caption copy: SF Mono via `.system(design: .monospaced)`
- Retune only through `Ink` type tokens

## Search

⌘K opens a Departure Mono command palette (pages, settings, history transcripts, models). ⌘F on History focuses the inline transcript filter. Hits jump to the tab and pulse-highlight the row; history Enter copies the session.

## Appearance

Folder tabs (importance order): **Home | Appearance | History** · Models · General | Sound | Perf. Gaps: primary trio, then Models alone, then app plumbing. Appearance (`paintpalette`, purple shelf accent) owns theme + the former Recording page (island Default/Compact/Minimal/Hidden, Shift-drag tool/color). Recording shortcuts stay in General. The separate Recording tab is gone.

`AppAppearance` (System / Light / Dark) lives on the **Appearance** tab and still cycles from the menu-bar panel (`theme: …`).

**One source of truth:** `AppSettings.setAppearance` → `NSApp.appearance`. Ink tokens resolve via `NSColor(name:dynamicProvider:)`. Do **not** also apply `.preferredColorScheme` on Settings / onboarding / menu roots — that double-drives the tree and makes the segment feel buggy (double-fire, flicker, sticky selection). `InkAppearanceSegment` writes only through its binding (no separate `onChange`). Re-tapping the selected mode is a no-op. `Ink.windowNSColor` must stay in sync with `Ink.window`. System mode leaves `NSApp.appearance = nil` so OS changes re-resolve live.

## Traffic lights

Custom strip calls `orderOut` / `miniaturize` / `zoom` directly. Never `performClose` while stock buttons are hidden — it no-ops. `DTSystemTrafficLights.hide` must `isHidden = true` on the theme-frame button container (alpha-only still steals hits).

## Deliberate exceptions

`PRODUCT_NAME` / `Mutter.app`, bundle ID, storage paths, and `MutterBoundary` stay as-is until a dedicated rename cut.
