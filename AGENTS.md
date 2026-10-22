# Agent notes — da transcribuh

Branch discipline: work on `overnight-audit` only. Never ship or merge `promo-video`.

## Chrome vs overlay

Settings, onboarding, and the menu-bar panel share the **Ink** B/W design system (`PromptAnnotator/Settings/Ink/`).

The whole app is an **MS Paint** theme (Run 24+): toolbox sidebar, flat classic swatches, chunky outlines, hard shadows, Departure Mono chrome. The **recording island**, **waveform**, **markup toolbar**, and **selection overlay** share that language. Keep hit targets, animations, and annotation ink colors intact; do not add timers or heavy per-frame effects to the waveform/overlay path.

## Typography

- Chrome labels: Departure Mono (`DepartureMono-Regular`, `ATSApplicationFontsPath=Fonts`)
- Long body/caption copy: SF Mono via `.system(design: .monospaced)`
- Retune only through `Ink` type tokens

## Appearance

`AppAppearance` (System / Light / Dark) lives in General settings and cycles from the menu-bar panel (`theme: …`). Applies via `NSApp.appearance`.

## Deliberate exceptions

`PRODUCT_NAME` / `Mutter.app`, bundle ID, storage paths, and `MutterBoundary` stay as-is until a dedicated rename cut.
