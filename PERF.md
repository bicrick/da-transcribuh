# Capture path performance (recording)

Audit of the Shift-drag screenshot loop while a session is recording. Behavior is unchanged: same PNG frames, island chip count, annotate handoff, and contact sheet at stop.

## How to profile

1. Build & run the Mac app from Xcode.
2. Instruments → **os_signpost** (or Time Profiler + Points of Interest).
3. Filter subsystem `com.bicrick.PromptAnnotator`, category `CapturePerf`.
4. Start a session, Shift-drag several region snips, Shift-annotate once, Stop.
5. Inspect intervals: `capture`, `shareableContent`, `screenshot`, `composite`, `crop`, `encode`/`write`, `thumbnail`, `uiUpdate`.

Priorities on the hot path: audio stays real-time; capture Task is `.userInitiated`; PNG encode is `.utility`.

## Root causes (before)

| Stage | Thread / cost | Problem |
|-------|----------------|---------|
| Shareable content | Await on every snip | `SCShareableContent.excludingDesktopWindows` re-enumerated windows per shot |
| Screenshot | `SCScreenshotManager` OK | Already on ScreenCaptureKit (not `CGWindowListCreateImage`), but always **full Retina display** |
| Crop | MainActor after await | Full-frame grab then `RegionCrop.crop` — wasted pixels + copy |
| Composite | After screenshot | Empty `shapes: []` still allocated a full-display RGB bitmap and redrew the base |
| PNG encode | **MainActor** | `PNG.write` / ImageIO blocked the island + event tap between snips |
| Selection overlay | Main, every `leftMouseDragged` | `syncOverlay` → full-canvas `needsDisplay` (even-odd shade + marks) |
| Contact sheet | MainActor at Stop | `ContactSheet.render` + `sheet.png` on the UI actor after transcription |
| Cache / QoS | None | No content cache; no utility encode queue; no signposts |

No spin loops, `Thread.sleep`, or `DispatchQueue.main.sync` on this path. Live “thumbnail” during recording is the count chip only (`sheet.png` is stop-time).

## Fixes (after)

1. **`ShareableContentCache`** — actor-cached `SCShareableContent`; warm on session start; invalidate on `didChangeScreenParameters` (and one retry if the display ID vanishes).
2. **Region `sourceRect`** — clean snips set `SCStreamConfiguration.sourceRect` + width/height from `filter.pointPixelScale`; skip full-display grab + `RegionCrop` when there are no marks.
3. **Skip empty composite** — `DisplayCapture` / `ShapeRenderer.composite` return the screenshot when shapes are insignificant (no full-size copy).
4. **`CapturePipeline` + `PNG.writeAsync`** — capture/encode off MainActor (`Task` `.userInitiated` → encode on `.utility`); MainActor only appends `StoredGroup` and refreshes the island chip (`uiUpdate` signpost).
5. **Lightweight selection overlay** — CAShapeLayer shade/border while dragging (no marks); integral-rect coalesce; `updateSelection` skips mark dirty work. If marks exist, selection falls back into `draw(_:)` so strokes stay above the shade.
6. **Stop-time sheet** — `SessionWriter.writeAsync` builds markdown/JSON + contact-sheet thumbnail off MainActor.
7. **`CapturePerf` os_signpost / OSLog** — intervals listed above for Instruments.

## Expected effect

- Dragging a snip should no longer hitch the recording island or pointer (layer path, coalesced).
- Each snip should avoid a multi‑MP full-display bitmap when only a small rect is needed, and should not stall MainActor on PNG.
- Repeated snips in one session should skip repeated `SCShareableContent` enumeration (watch `shareableContent` fire once after start / display change, not per shot).

## Files

- `PromptAnnotator/Capture/DisplayCapture.swift`
- `PromptAnnotator/Capture/ShareableContentCache.swift`
- `PromptAnnotator/Capture/CapturePipeline.swift`
- `PromptAnnotator/Capture/CapturePerf.swift`
- `PromptAnnotator/Overlay/AnnotationOverlay.swift`
- `PromptAnnotator/Overlay/ShapeRenderer.swift`
- `PromptAnnotator/Export/SessionWriter.swift`
- `PromptAnnotator/SessionController.swift`
