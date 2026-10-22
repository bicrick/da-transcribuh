# Agent notes — da transcribuh

Branch discipline: work on `overnight-audit` only. Never ship or merge `promo-video`.

## Chrome vs overlay

Settings, onboarding, and the menu-bar panel share the **Ink** design system (`PromptAnnotator/Settings/Ink/`).

The whole app is an **MS Paint** theme: manila **folder tabs** (not a toolbox sidebar), flat classic swatches where functional, chunky outlines, hard shadows, Departure Mono chrome. Decorative palette strips are gone from the title bar, status bar, onboarding chrome, and menu panel. The **recording island**, **waveform**, **markup toolbar**, and **selection overlay** share that language. Keep hit targets, animations, and annotation ink colors intact; do not add timers or heavy per-frame effects to the waveform/overlay path.

### Brand mark

`InkDtMark` / AppIcon: Departure Mono lowercase **d** + inverted **t** (white on black block) inside a **white** square with a **black** hard-offset bevel. Dark mode keeps the tile white; bevel uses `Ink.bevel` (`#1A1A1C`). Regenerate with `scripts/render_dt_icon.py`.

### Dark graphite tokens

| Token | Light | Dark |
| --- | --- | --- |
| `window` | `#FFFFFF` | `#2C2C2E` |
| `fill` / `card` (raised) | `#F0F0F0` / `#FFFFFF` | `#353538` |
| `front` (selected tab + content) | `#FFFFFF` | `#3A3A3D` |
| `hairline` | `#C0C0C0` | `#4A4A4E` |
| `label` | `#000000` | `#F2F2F2` |
| `secondary` | `#666666` | `#A8A8AD` |
| `bevel` (double-pane offset) | `#000000` | `#1A1A1C` |

Nothing in chrome should paint darker than `#1A1A1C` except the bevel itself. Route surfaces through `Ink.*` — no `Color.black` / system window materials for chrome.

## Typography

- Chrome labels: Departure Mono (`DepartureMono-Regular`, `ATSApplicationFontsPath=Fonts`)
- Long body/caption copy: SF Mono via `.system(design: .monospaced)`
- Retune only through `Ink` type tokens

## Search

⌘K opens a Departure Mono command palette (pages, settings, history transcripts, models). ⌘F on History focuses the inline transcript filter. Hits jump to the tab and pulse-highlight the row; history Enter copies the session.

## Appearance

`AppAppearance` (System / Light / Dark) lives in General settings and cycles from the menu-bar panel (`theme: …`). Applies via `NSApp.appearance`. `Ink.windowNSColor` must stay in sync with `Ink.window`.

## Traffic lights

Custom strip calls `orderOut` / `miniaturize` / `zoom` directly. Never `performClose` while stock buttons are hidden — it no-ops. `DTSystemTrafficLights.hide` must `isHidden = true` on the theme-frame button container (alpha-only still steals hits).

## Deliberate exceptions

`PRODUCT_NAME` / `Mutter.app`, bundle ID, storage paths, and `MutterBoundary` stay as-is until a dedicated rename cut.
