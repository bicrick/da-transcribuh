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

Home keeps the pre-declutter structure (stats grid, Get Started checklist, tip tiles). Nits only: no yellow version badge (status bar has it), no hero tagline, no “^⌥Space starts…” caption under Start. Stat underlines are neutral (`Ink.statRule`); per-page Paint accents live on folder-tab top stripes (`SettingsPage.tabAccent`). Start / primary stays high-contrast invert (`primaryFill` / `onPrimary`: black↔`#F2F2F2`), not a flat graphite plate.

Selected folder tab merges into the page: fill is `Ink.front`, the shelf hairline is interrupted under it (`ShelfHairline` + preference frame), and the tab bleeds 1pt over the rule. Unselected tabs stay on `Ink.fill` with the hairline under them. README mocks: `scripts/render_home_mocks.py` (angled `FolderTabShape`, DejaVu for ⌃⌥⌘).

## Typography

- Chrome labels: Departure Mono (`DepartureMono-Regular`, `ATSApplicationFontsPath=Fonts`)
- Long body/caption copy: SF Mono via `.system(design: .monospaced)`
- Retune only through `Ink` type tokens

## Search

⌘K opens a Departure Mono command palette (pages, settings, history transcripts, models). ⌘F on History focuses the inline transcript filter. Hits jump to the tab and pulse-highlight the row; history Enter copies the session.

## Appearance

`AppAppearance` (System / Light / Dark) lives in General settings and cycles from the menu-bar panel (`theme: …`).

**One source of truth:** `AppSettings.setAppearance` → `NSApp.appearance`. Ink tokens resolve via `NSColor(name:dynamicProvider:)`. Do **not** also apply `.preferredColorScheme` on Settings / onboarding / menu roots — that double-drives the tree and makes the General segment feel buggy (double-fire, flicker, sticky selection). `InkAppearanceSegment` writes only through its binding (no separate `onChange`). Re-tapping the selected mode is a no-op. `Ink.windowNSColor` must stay in sync with `Ink.window`. System mode leaves `NSApp.appearance = nil` so OS changes re-resolve live.

## Traffic lights

Custom strip calls `orderOut` / `miniaturize` / `zoom` directly. Never `performClose` while stock buttons are hidden — it no-ops. `DTSystemTrafficLights.hide` must `isHidden = true` on the theme-frame button container (alpha-only still steals hits).

## Deliberate exceptions

`PRODUCT_NAME` / `Mutter.app`, bundle ID, storage paths, and `MutterBoundary` stay as-is until a dedicated rename cut.
