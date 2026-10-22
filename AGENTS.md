# Agent notes — da transcribuh

Branch discipline: work on `overnight-audit` only. Never ship or merge `promo-video`.

## Chrome vs overlay

Settings, onboarding, and the menu-bar panel share the **Ink** B/W design system (`PromptAnnotator/Settings/Ink/`).

The **recording island**, **live waveform**, **markup/annotate toolbar**, and **selection overlay** are also B/W-reskinned to match that system (Run 20). Keep layout, sizes, animations, hit targets, and annotation ink colors intact — change visual treatment only (fills, 1px outlines, small radii, hard offset shadows, Departure Mono / SF Mono tokens). Do not add timers or heavy per-frame effects to the waveform/overlay path.

## Typography

- Chrome labels: Departure Mono (`DepartureMono-Regular`, `ATSApplicationFontsPath=Fonts`)
- Long body/caption copy: SF Mono via `.system(design: .monospaced)`
- Retune only through `Ink` type tokens

## Appearance

`AppAppearance` (System / Light / Dark) lives in General settings and cycles from the menu-bar panel (`theme: …`). Applies via `NSApp.appearance`.

## Deliberate exceptions

`PRODUCT_NAME` / `Mutter.app`, bundle ID, storage paths, and `MutterBoundary` stay as-is until a dedicated rename cut.
