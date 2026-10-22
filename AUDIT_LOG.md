# Mutter overnight audit log

Branch: `overnight-audit` (from `main`). Linux VM — no Xcode build. Changes kept compile-safe and small.

**Fallback if anything breaks on the Mac: use `main`.** Do not ship `promo-video`. This branch never had an Xcode build on the overnight VM.

---

## Final summary (Runs 1–13b)

### What changed overall (kept)

| Area | Change |
| --- | --- |
| Stability | Cancel vs in-flight capture; mic volume restore; Accessibility prompt; overlay rebuild on display change; PTT release-during-begin latch; tap buffer `memcpy`; speech-follow cancel; live decode error advance; empty-transcript menu cue; Shift tap deferral; **FontMetrics nil-font guard** |
| Silence P0 | Whisper `suppressBlank` + `NonSpeechFilter` (no `[BLANK_AUDIO]` / `(silence)` captions) |
| UX | Busy menu icon; plain-language `UserFacingError`; shortcut copy; island a11y; Settings sections + Models page |
| Onboarding | Permissions recovery; model progress; 5 s practice (skips paste) |
| Performance | Whisper `prewarm` (+450 ms defer); live window cap; PCM soft-cap + file merge; integer absolute sample counts; Copy Last Again |
| Live window (Run 9–10) | Cap truncates the **end** (from `confirmedEnd`); holdback uses **window end**, not full buffer duration |
| **BYOM (Run 12)** | Custom WhisperKit Core ML folder + HF repo/variant; optional OpenAI-compatible final engine (Keychain); `RoutingTranscriber`; fallback to default Whisper on failure |
| **Ink restyle (Run 13)** | Settings + onboarding “Ink” theme (warm paper + logo red); shared design system; continuous waveform→pen motif; Advanced copy fix. Recording island/overlay untouched. |
| **Ink polish (Run 13b)** | Fixed stacked top padding (~90pt); custom Ink sidebar selection (no system blue List highlight). |

### Reverted (Run 9, still gone)

- **Quiet-room calibration** — fixed SpeechGate **0.28** (matches `main`). No dangling Swift/pbxproj refs.

### Run 13b (Ink padding + sidebar selection)

- **Cause of ~90pt top gap:** mockup `pageTop` 52pt was designed as clearance from the window top (including title-bar). With `fullSizeContentView` + `NavigationSplitView`, SwiftUI already insets detail content below the title-bar safe area; stacking another 52pt (plus an empty detail toolbar band) produced the empty strip. **Fix:** `Ink.pageTop` / `SettingsMetrics.pageTop` → **22** (breathing room only); hide automatic detail toolbar.
- **Sidebar:** replaced `List(selection:)` / `.sidebar` (forces system accent pill) with `SettingsSidebar` Button rows — Ink selection fill (12%/18%) + accent icon/label.

### Run 13 (Ink visual restyle)

- Design tokens + components under `PromptAnnotator/Settings/Ink/`.
- All Settings pages + sidebar + onboarding chrome restyled; bindings/behavior preserved.
- Welcome/Ready illustration: waveform flows into pen as one continuous L→R ink line (no U-shaped smile).
- Advanced: “Speech models are on the Models page.”
- Tests: `InkThemeTests`.

### Run 12 (BYOM + Settings)

- Implemented Phase A + optional Phase C from `docs/BRING_YOUR_OWN_MODEL.md`.
- Crash sweep on new paths: no force-unwraps into attributes dicts; multipart filename sanitized; bookmark access scoped; Keychain for API key.

### Still risky (no Mac build)

- Full `xcodebuild` + unit tests never run on this VM.
- Prewarm CPU after cold launch; uncapped final decode CPU on very long takes; PCM trim >10 min + AAC merge.
- Soft speech vs `noSpeechThreshold: 0.6` + NonSpeechFilter.
- MenuBarExtra SF Symbol swaps mid-session.
- BYOM: huge custom models; stale security-scoped bookmarks; OpenAI schema drift; network on stop.
- Unused `PushToTalk.isArmed` left from Run 9 (harmless; latch-only stop path).
- (Run 13b) Custom sidebar replaces List selection; confirm keyboard/VoiceOver still feel fine on Mac.

---

## Mac test checklist (do in order)

**If anything fails: fall back to `main` for the launch video.** Do not ship `promo-video`.

### P0 — must pass before recording

- [ ] **Build** `overnight-audit` in Xcode (Debug) + run unit tests (`NonSpeechFilter`, `LiveSampleWindow`, `AudioRecorderTrim`, `SpeechGate`, `SettingsBehavior`, `UserFacingError`, `SpeechModelTests` holdback, **`FontMetricsTests`**, **`BYOMTests`**, **`InkThemeTests`**).
- [ ] **Ink Settings**: Home / Models / History / Recording / Configuration / Sound / Performance in light + dark — accent tint, card chrome, no island restyle.
- [ ] **Ink padding**: ~20–24pt gap below title-bar to first content on every Settings page (not ~90pt).
- [ ] **Ink sidebar**: selected row is Ink tint + accent icon/text (not system blue).
- [ ] **Ink Onboarding**: STEP n OF 6 eyebrow, step dots, Skip / Back / primary order; Welcome+Ready waveform→pen is one continuous line (not a smile); Ready bars inked red.
- [ ] Configuration Advanced reads “Speech models are on the Models page.”
- [ ] **Hotkey toggle** (PTT off): start → speak → stop → transcript on clipboard / paste.
- [ ] **Menu Start / Home Start with Push-to-Talk ON** — session must **stay recording** until Stop (must not auto-stop instantly).
- [ ] **PTT hold**: press chord → speak → release → stops; brief press during mic prompt also stops (not stuck recording).
- [ ] **Silence P0**: 10–20 s quiet → empty transcript; menu **No speech detected** (no `[BLANK_AUDIO]` / `(silence)`).
- [ ] Soft speech ~5 s still transcribes.
- [ ] Cancel mid-session → no resurrected folder; next session still works.
- [ ] Raise-input-volume on → stop → system mic level restored.
- [ ] **Island clock** ticks past `1:00` / `10:00` with no `NSInvalidArgumentException` font crash.
- [ ] **BYOM built-in**: switch tiny ↔ balanced → session still transcribes.
- [ ] **BYOM folder** (optional): add a valid WhisperKit Core ML folder → select → record → stop.
- [ ] **OpenAI-compatible** (optional): set base URL + key → live captions off → stop yields transcript or clear fallback error.

### P1 — launch / first-run

- [ ] Cold launch: menu bar + Settings/welcome paint before prewarm pegs CPU; model shows Loaded.
- [ ] Fresh onboarding: permissions → shortcut → model download → practice 5 s (no paste into welcome) → later real session still pastes when paste-on-stop is on.
- [ ] Menu bar: idle pencil / recording filled / busy ellipsis; plain-language errors.
- [ ] Copy Last Again after another app overwrites the clipboard.

### P2 — long take / edge

- [ ] Live ~2–3 min continuous speech → stop → full words (not only last ~45 s); live island should keep advancing (holdback not freezing mid-take).
- [ ] Optional: >10 min under PCM retain cap → file merge OK.
- [ ] Display plug/unplug while marking; double Paste Image and Text once only.
- [ ] Quit while recording → volume restored; PTT works after relaunch.

---

## Run 13b — Ink top padding + sidebar selection

### Padding root cause

`Ink.pageTop = 52` matched the HTML mockup’s page padding, which cleared the title-bar *and* added air. In the real window (`fullSizeContentView` + `NavigationSplitView`), the detail column is already laid out below the title-bar safe area; the extra 52pt stacked on that inset (and an empty automatic toolbar band), yielding ~90pt of empty space above Home/Models/etc.

### Fix

| Change | Detail |
| --- | --- |
| `Ink.pageTop` → 22 | Shared token used by `SettingsPageStack`, Home, History — ~20–24pt below chrome |
| `.toolbar(.hidden, for: .automatic)` on detail | Drops empty toolbar band |
| `SettingsSidebar` | Custom Button rows; Ink `sidebarSelection` + accent label/icon (no `List` system blue) |

### Mac check

1. Home (and other pages): gap under title-bar ≈ 20–24pt.
2. Select each sidebar item — coral/red tint, not blue.
3. Light + dark.

---

## Run 13 — Ink visual restyle (Settings + onboarding)

### Scope

Implement approved “Ink” restyle from mockups (`mutter-mockups/restyle/`, `rs.py` / `screens.py` tokens). Settings window + onboarding only — **do not** restyle recording island/overlay. Compile-safe SwiftUI (macOS 14+), preserve all bindings.

### Delivered

| Piece | Notes |
| --- | --- |
| `InkTheme.swift` | Dynamic light/dark palette via `NSColor(name:dynamicProvider:)`; radii, spacing, type tokens |
| `InkComponents.swift` | InkCard, InkTile, Keycap, SegmentMeter (MeterBar), StepDots, primary/secondary buttons, WavePenMotif, error banner, dashed empty |
| Settings pages | Home hero + stats + checklist; Models engine cards + tile meters + HF side-by-side; History card rows; Recording/Sound 2×2 tiles; Performance memory meters; Configuration Ink chrome |
| Sidebar / window | 220pt sidebar, accent selection tint, `Ink.window` background, app-wide `.tint(Ink.accent)` |
| Onboarding | Eyebrow, StepDots, Skip → Back → primary; Welcome/Ready continuous waveform→pen (Ready inked) |
| Copy | Advanced: “Speech models are on the Models page.” |
| Tests | `InkThemeTests` (hex, tokens, onboarding steps, dynamic window color) |

### Intentionally unchanged

- Recording island / overlay / annotation chrome (still prior FontMetrics fix only).

### Mac checklist (Ink-specific)

1. Build Debug; run `InkThemeTests` + prior suites.
2. Toggle System Settings appearance light/dark — Settings + onboarding track Ink palette.
3. Home: Start/Stop + checklist progress still driven by permissions/model/sessions.
4. Models: switch engines; select built-in tiles; HF Repo|Variant; custom empty dashed state; API-key warning when OpenAI engine lacks key.
5. Onboarding Welcome/Ready: ink stroke is a single L→R path into the pen tip (no smile under the bars).
6. Record a session — island looks as before (not Ink-restyled).

---

## Run 12 — BYOM + Models Settings

### Scope

Implement bring-your-own-model per `docs/BRING_YOUR_OWN_MODEL.md` (WhisperKit custom folder + HF download; optional OpenAI-compatible final engine). Polish Settings sidebar/Models UI. Keep island alone except prior font crash fix. Compile-careful on Linux VM.

### Delivered

| Piece | Notes |
| --- | --- |
| `CustomWhisperCatalog` / `WhisperModelValidator` / `WhisperSourceResolver` | Persist + validate folder/HF entries |
| `WhisperKitTranscriber` | Custom folder (security-scoped), custom repo download, `unload()` |
| `OpenAICompatibleTranscriber` | `/v1/audio/transcriptions`, Keychain key, verbose_json words |
| `RoutingTranscriber` | Engine switch; live no-op for OpenAI; fallback to default Whisper |
| Models Settings page | Engine picker, built-ins, custom list, HF form, OpenAI form, empty/error states |
| Sidebar | Session / Speech / App sections; page titled Models |
| Tests | `BYOMTests` (validator, catalog, resolver, OpenAI parse/URL, settings) |

### Crash sweep (new code)

- No `try!` / `as!` / `fatalError` in new Speech/Settings paths.
- Multipart filename sanitized; Keychain replaces rather than stacking.
- Folder access via security-scoped bookmark start/stop.
- Invalid custom selection falls back to built-in balanced model.

---

## Run 11 — Final regression re-check (no new features)

### Scope

Re-audit Run 10 (`db8b0fc`: live holdback vs capped `windowEnd` + unit test). Brief consistency pass vs `main` (~+2465/−158, 31 files, never Xcode-built). Fix only real bugs; prefer no churn.

### Run 10 re-check

| Item | Verdict |
| --- | --- |
| Holdback uses `decoded.windowEnd` | **OK** — matches actual PCM sent to Whisper after head-cap |
| Short takes (<~45 s) | **OK** — `windowEnd == bufferEnd`; same as pre-Run-10 |
| Exact ~45 s / +1 sample | **OK** — cap equality / first capped frame; edge word held |
| Long take first pass (e.g. 90 s, `confirmedEnd` 0) | **OK** — edge of 45 s window held; old full-buffer holdback would wrongly confirm |
| Mid-session after `confirmedEnd` advances | **OK** — holdback from capped forward window end |
| Empty / sub-second buffers | **OK** — empty stable set; `consume` still requires ≥1 s new samples; final path uncapped |
| Off-by-one (index `rounded(.down)`) | **OK** — `windowEnd` derived from sliced sample count, not conceptual `absEnd` |
| Compile safety | **OK** — private `decode` → `(words, windowEnd)`; live uses both; final uses `.words`; protocol `consume` unchanged |
| Test membership | **OK** — `PBXFileSystemSynchronizedRootGroup`; `testHoldbackUsesCappedWindowEndNotFullBuffer` auto-included |

### Core flows vs `main` (static)

| Flow | Verdict |
| --- | --- |
| Hotkey toggle (PTT off) | **OK** |
| PTT hold / release + release-during-begin latch | **OK** |
| Menu / Home Start with PTT on | **OK** — latch-only stop (never `!isArmed`) |
| Paste / clipboard / Copy Last Again | **OK** |
| Cancel / abandon / capture discard | **OK** |
| Volume restore | **OK** |
| Silence + empty menu cue | **OK** (soft speech still Mac-risk) |
| Quiet-room symbols | **CLEAN** — none left |

### Fixed this round

**None.** No code changes. Run 10 holdback and prior stability fixes stand.

### Suspected but not verified on a Mac

- Full `xcodebuild` Debug + unit tests.
- Soft speech vs `noSpeechThreshold: 0.6` + NonSpeechFilter.
- Prewarm / long-take CPU / PCM trim merge.

### What’s next

- Hardware-confirm **P0** on a real Mac before the launch video.
- **Fallback: `main`.** Do not touch `promo-video`. No new features on this branch.

---

## Run 10 — Consistency / regression review (no new features)

### Scope

Re-audit Run 9 (`e0a14af`) and branch vs `main` (~+2400 lines, never Xcode-built). Look for dangling calibration symbols, latch/live-window/speech-follow regressions, and anything that broke main behavior. Prefer minimal compile-safe fixes.

### Run 9 re-check

| Item | Verdict |
| --- | --- |
| Quiet-room deletion | **CLEAN** — no Swift/pbxproj refs; `SpeechGate` matches `main`; Configuration/AppSettings/tests restored |
| PTT latch-only stop | **OK** — menu/Home/practice clear stale latch; `releasePushToTalk` only from armed monitors |
| Live head-cap | **KEPT** — hole fix correct; **holdback pairing was wrong** (fixed below) |
| Speech-follow `@MainActor` Task | **OK** — matches controller isolation; cancel + throwing sleep retained |
| `skipNextPaste` clear paths (Run 8) | **OK** — still cleared on abandon / begin failures / missing folder / write failure |

### Fixed this round

1. **Live holdback used full buffer duration after head-cap** (`WhisperKitTranscriber.consume`)  
   Run 9 capped the decode window from `confirmedEnd` forward, but stability still filtered with `bufferStart + samples/rate`. When the buffer was longer than ~45 s, every word in the window looked “stable,” including the trailing holdback second — locking tentative edge words before the next pass could revise them. `decode` now returns `windowEnd`; holdback is `windowEnd - 1 s`. Added `testHoldbackUsesCappedWindowEndNotFullBuffer`.

### Confirmed still OK vs main (static)

- Hotkey toggle / PTT arm-release / menu Start stop titles / paste-on-stop + Copy Last Again wiring / onboarding practice skip-paste / settings persistence keys (minus removed speech-gate key) / volume restore / capture cancel / Accessibility prompt / overlay rebuild.
- No new features. No `promo-video` touches.

### Suspected but not verified on a Mac

- Full `xcodebuild` Debug + unit tests.
- Live follow still advances `lastSpeechCount` before `consume` returns (pre-existing); nil pipe skips until next +1 s — final path covers stop.
- Long-take CPU (uncapped final), prewarm, soft speech vs NonSpeechFilter.

### What’s next

- Hardware-confirm P0 on a real Mac before the launch video.
- Do not touch `promo-video`. No new features on this branch.

---

## Run 9 — Consistency / regression review (no new features)

### Scope

Diff `overnight-audit` vs `main` (~+2600 lines, never Xcode-built). Re-audit recent quiet-room / live-window / PTT changes. Prefer revert to `main` behavior over clever unverified fixes.

### Actions

| Item | Verdict |
| --- | --- |
| Quiet-room calibration | **REVERTED** to fixed SpeechGate 0.28 |
| PTT + menu/Home Start | **FIXED** (latch only; clear stale latch on toggle/practice) |
| Live window cap | **FIXED** (head-cap from confirmedEnd, not tail-jump) |
| Speech-follow off-main claim | **SIMPLIFIED** back to `@MainActor` Task |
| Prewarm / PCM soft-cap / Copy Last Again / NonSpeechFilter / onboarding / UX | **KEPT** |
| Volume restore / capture cancel / Accessibility prompt / overlay rebuild | **KEPT** (strictly safer than main) |

### Compile-safety notes

- Deleted `QuietRoomCalibration.swift`; synchronized root groups auto-drop it.
- Restored `SpeechGate` / `AppSettings` / Configuration / tests to symbols that match the revert.
- No new files; no pbxproj membership edits required.

### What’s next

- Hardware-confirm P0 on a real Mac before the launch video.
- Do not touch `promo-video`. No new features on this branch.

---

## Run 8 — Second compile-safety review (no new features)

### Scope

Re-audit of the full branch vs `main` (~+2500 lines), including Run 7 quiet-room hardening. Focus: symbol/signature matches, optionals, `@MainActor` / actor isolation under `SWIFT_STRICT_CONCURRENCY = minimal`, imports, UserDefaults/menu/settings wiring, duplicate declarations, synchronized-root file membership. No new features.

### Checked

| Area | Result |
| --- | --- |
| File membership | `PBXFileSystemSynchronizedRootGroup` for app + tests — new Swift files auto-included. |
| Quiet-room / SpeechGate / `session.speechGateThreshold` / Configuration Calibrate+Reset | Wired; clamp on load/write; SilenceWatch reads `SpeechGate.threshold`. |
| Live window / PCM trim / `absoluteEndCount` / `decode(capWindow:)` / `decodeFileMergingLive` | Call sites match protocol + actor witness; final uncapped. |
| WhisperKit 1.1.1 | Unchanged pin; `prewarm`, `DecodingOptions`, `transcribe` overloads match. |
| Copy Last Again / `PasteFollowUp.restoreClipboard` / menu | Wired. |
| Onboarding practice / `UserFacingError` / menu icons / Performance cache | Symbols resolve; tests match APIs. |
| Imports / duplicates | No missing imports for new symbols; no duplicate type declarations. |

### Fixed this round

1. **`isStarting` did not refresh SwiftUI** (`SessionController`)  
   Configuration disabled Calibrate on `session.isStartingSession`, but `isStarting` was a plain `private var`, so the button stayed enabled during the mic/setup await. Now `@Published private(set)`.

2. **Calibration `isInProgress` armed too late** (`QuietRoomCalibration.sampleAmbient`)  
   `sampling` was set only after `requestMicrophone()`, so `begin()` could pass the guard during the permission dialog and start a second capture stack. Now arms before any await; also refuses if a session is already starting/recording/busy; drops unused `import AVFoundation`.

3. **`skipNextPaste` could stick** (`SessionController`)  
   Onboarding practice sets the flag; it cleared mainly via `deliverIfRequested` on a successful write. Missing-folder early return, write failure, and `abandonIfRecording` (quit mid-practice) left it set so the *next* real session could skip paste. Cleared on those paths.

4. **Reset during Listening** (`ConfigurationPage`)  
   Reset disabled while `calibratingQuietRoom` so a mid-sample Reset cannot fight the finishing Calibrate write.

### Suspected but not verified on a Mac

- Full `xcodebuild` Debug + unit tests (Linux cannot compile).
- Live follow still advances `lastSpeechCount` before `consume` (pre-existing pattern); if the pipe is still nil, live skips until the next +1 s window — final/file path still covers stop.
- Quiet-room + exclusive mic holders / non-default input UID.
- Carry-over: uncapped final decode CPU, prewarm, Copy Last Again, long-take memory.

### Test this tomorrow on a Mac

**P0 — compile & smoke (do these first)**

- [ ] **Build:** Xcode Debug build of `overnight-audit` + run unit tests (`NonSpeechFilter`, `LiveSampleWindow`, `AudioRecorderTrim`, `SpeechGate` / quiet-room, `SettingsBehavior`, `UserFacingError`).
- [ ] **Cold launch:** menu bar appears; Settings/welcome paints before model prewarm pegs CPU.
- [ ] **Silence P0:** 10–20 s quiet → empty transcript; menu **No speech detected**.
- [ ] Soft speech ~5 s still transcribes (default gate, no calibration).

**P1 — quiet-room (Runs 6–8)**

- [ ] Configuration → Calibrate quiet room (stay silent) → note shows room/gate; soft speech still marks heard / transcribes; Reset restores default; relaunch keeps calibration until Reset.
- [ ] Calibrate with silence-stop 1.25 s → speech then quiet still auto-stops.
- [ ] Calibrate button disabled while recording **and** while a session is still starting (permissions) — button should grey as soon as Start begins awaiting mic.
- [ ] Reset disabled while Listening…; after calibrate finishes, Reset works.
- [ ] Hotkey start during “Listening…” → refused with calm cue; after calibrate finishes, start works.
- [ ] If a non-default mic is selected in Configuration, calibrate then speak on that mic → gate still sensible.

**P2 — practice paste + prior runs (abbreviated)**

- [ ] Onboarding practice → success path does **not** paste into the welcome window; a later real session with paste-on-stop still pastes.
- [ ] Quit mid-practice (or force missing session folder) → next normal session still pastes when paste-on-stop is on.
- [ ] Final decode after live lag / long take under retain cap / Copy Last Again (Run 5–6 lists).
- [ ] PTT release-during-begin; cancel mid-capture; volume restore; onboarding practice 5 s.
- [ ] Menu bar busy icon + plain-language errors.

### Proposed polish / features (ranked)

1–7. ~~Done through Run 6~~ (icons, settings copy, practice, prewarm, live cap, Copy Last Again, quiet-room).
8. **Processing island status label** — optional “Transcribing” text. *(UX — later)*
9. **Per-display chrome placement lock** — *(UX — later)*
10. **Session history scrubber** / **export share sheet** — *(features — later)*

### What’s next

- Hardware-confirm P0–P2 on a real Mac before the launch video.
- Do not touch `promo-video`. No new features on this branch until build is green.

---

## Run 7 — Compile-safety review (no new features)

### Scope

Static re-audit of Runs 5–6 (~+2300 lines vs `main`) that have never been Xcode-built on this VM. Focus: launch-features (quiet-room) first, then symbol/signature/concurrency/import/wiring checks across the branch. Project uses `PBXFileSystemSynchronizedRootGroup` — new Swift files under `PromptAnnotator/` and `PromptAnnotatorTests/` are auto-included (no pbxproj membership edits needed).

### Checked

| Area | Result |
| --- | --- |
| Quiet-room symbols (`QuietRoomCalibration`, `SpeechGate`, `AppSettings.speechGateThreshold`, Configuration wiring) | Present; labels match; settings ↔ gate ↔ silence-stop consistent. |
| Live window / PCM trim / `absoluteEndCount` / `decode(capWindow:)` / `decodeFileMergingLive` | Call sites match; final path still uncapped. |
| Copy Last Again / `PasteFollowUp.restoreClipboard` / menu | Wired. |
| WhisperKit 1.1.1 (`Package.resolved`) | `WhisperKitConfig(prewarm:)`, `DecodingOptions` fields, `transcribe` overloads match. |
| `@MainActor` / actors / `SWIFT_STRICT_CONCURRENCY = minimal` | No definite isolation compile breaks under current setting. |
| Imports / new file membership | Synchronized groups OK. Added explicit `CoreGraphics` on calibration (was transitive-only). |
| Onboarding practice / menu icons / UserFacingError | Symbols resolve; no stale renames. |

### Fixed this round

1. **Quiet-room levels used a different meter than live SpeechGate** (`QuietRoomCalibration.sampleAmbient`)  
   Calibration sampled `AVAudioRecorder.averagePower` only. Sessions with a working engine tap feed SpeechGate from PCM RMS via `AudioRecorder`. Those scales can diverge, so a calibrated floor might not match soft speech or silence-stop. Now samples through a short-lived `AudioRecorder` (same `latestLevel` / `sampleLevels` path), on the configured input device (`AudioInputs.beginSession` without raising volume).

2. **Mic contention with session start**  
   - `QuietRoomCalibration.isInProgress` while sampling.  
   - `SessionController.begin` refuses to start (calm `lastError`) until calibration finishes.  
   - Configuration Calibrate disabled while `isStartingSession` (permissions/setup), not only recording/busy.

3. **Calibration cancel / cleanup**  
   Throwing `Task.sleep` aborts cleanly; temp AAC removed if `start` fails; `import CoreGraphics` for `CGFloat`.

4. **Out-of-range persisted gate on load** (`AppSettings` init)  
   Clamps `session.speechGateThreshold` to the calibration min/max when reading UserDefaults (write path already clamped).

5. **Onboarding practice cancel hygiene** (`OnboardingFlow`)  
   Cancel during the post-stop wait now clears `practiceRunning` (and cancels a still-recording session) instead of leaving the flag stuck.

### Suspected but not verified on a Mac

- Full `xcodebuild` Debug + tests (Linux cannot compile).
- Quiet-room sample with non-default input UID / exclusive mic holders.
- Calibrated soft-speech demos after the AudioRecorder-path change.
- Carry-over: final uncapped decode CPU, prewarm, Copy Last Again, long-take memory.

### Test this tomorrow on a Mac

**P0 — compile & smoke (do these first)**

- [ ] **Build:** Xcode Debug build of `overnight-audit` + run unit tests (`NonSpeechFilter`, `LiveSampleWindow`, `AudioRecorderTrim`, `SpeechGate` / quiet-room, `SettingsBehavior`, `UserFacingError`).
- [ ] **Cold launch:** menu bar appears; Settings/welcome paints before model prewarm pegs CPU.
- [ ] **Silence P0:** 10–20 s quiet → empty transcript; menu **No speech detected**.
- [ ] Soft speech ~5 s still transcribes (default gate, no calibration).

**P1 — quiet-room (Run 6–7)**

- [ ] Configuration → Calibrate quiet room (stay silent) → note shows room/gate; soft speech still marks heard / transcribes; Reset restores default; relaunch keeps calibration until Reset.
- [ ] Calibrate with silence-stop 1.25 s → speech then quiet still auto-stops.
- [ ] Calibrate button disabled while recording **and** while a session is still starting (permissions).
- [ ] Hotkey start during “Listening…” → refused with calm cue; after calibrate finishes, start works.
- [ ] If a non-default mic is selected in Configuration, calibrate then speak on that mic → gate still sensible.

**P2 — performance / prior runs (abbreviated)**

- [ ] Final decode after live lag / long take under retain cap / Copy Last Again (Run 5–6 lists).
- [ ] PTT release-during-begin; cancel mid-capture; volume restore; onboarding practice 5 s.
- [ ] Menu bar busy icon + plain-language errors.

### Proposed polish / features (ranked)

1–7. ~~Done through Run 6~~ (icons, settings copy, practice, prewarm, live cap, Copy Last Again, quiet-room).
8. **Processing island status label** — optional “Transcribing” text. *(UX — later)*
9. **Per-display chrome placement lock** — *(UX — later)*
10. **Session history scrubber** / **export share sheet** — *(features — later)*

### What’s next

- Hardware-confirm P0–P1 on a real Mac before the launch video.
- Do not touch `promo-video`. No new features on this branch until build is green.

---

## Run 6 — Re-audit performance + quiet-room calibration

### Re-audit of Run 5 (performance)

| Change | Verdict |
| --- | --- |
| Whisper `prewarm: true` + 450 ms deferred launch prepare | Sound; kept. |
| Live `LiveSampleWindow` ~45 s cap | **Bug:** same cap was applied on the **final** sample decode. If live lagged (`confirmedEnd` stale), stop could drop the middle of a multi-minute take. Fixed: final/tail passes `maxSeconds: nil`. |
| PCM retain cap + file merge | Sound; kept. |
| Speech-follow off MainActor | Sound; kept. |
| `absoluteCount` via `timeOffset * 16_000` | **Bug:** float round-trip can drift by a sample after trim. Fixed: `SpeechBufferSnapshot.absoluteCount` is integer `dropped + retained`; `consume` takes `absoluteEndCount`. |
| `decodeFileMergingLive` | Sound; kept. |
| Performance disk-walk cache | Sound; kept. |
| Copy Last Again | Sound; kept. Menu still refreshes via `lastSessionURL` / session publishes. |

### Fixed this round

1. **Final decode must not use the live window cap** (`LiveSampleWindow.slice(maxSeconds:)`, `Transcriber.decode(capWindow:)`)  
   Live consume still caps ~45 s. Final/tail sample decode only clips from `confirmedEnd` (with overlap) and keeps the full remainder.

2. **Trimmed-buffer sample index drift** (`SpeechBufferSnapshot.absoluteCount`, `consume(…absoluteEndCount:)`)  
   Live follow no longer reconstructs the absolute end index from a floating `timeOffset`.

### Added this round

3. **Quiet-room calibration** (ranked #7)  
   - `QuietRoomCalibration` — ~1.6 s ambient meter sample → threshold = ambient + 0.08, clamped to 0.18…0.55.  
   - `SpeechGate` stores an optional calibrated floor (default **0.28** when unset — unchanged behavior).  
   - `AppSettings.speechGateThreshold` persists under `session.speechGateThreshold`.  
   - Configuration → Advanced: **Calibrate quiet room** / **Reset**. Disabled while recording/busy.  
   - **Revert:** remove `QuietRoomCalibration.swift`, the Configuration quiet-room row, `speechGateThreshold` on `AppSettings`, and restore `SpeechGate` to a fixed `threshold = 0.28` (or `git revert` the calibration commit).

### Suspected but not verified on a Mac

- Quiet-room sample while another app holds the mic exclusively.
- Calibrated lower gate in a truly silent room vs soft-speech demos.
- Final uncapped sample decode on a ~10 min complete buffer (CPU time at stop).
- Prewarm / Copy Last Again / long-take memory (carry-over from Run 5).

### Test this tomorrow on a Mac

**Carry over from Runs 1–5** (abbreviated)

- [ ] Silence P0 + soft speech + menu bar busy icon + plain-language errors.
- [ ] PTT / cancel / volume restore / paste-once / onboarding practice.
- [ ] Cold launch prewarm + live long take + Copy Last Again (Run 5 list).

**New for Run 6**

- [ ] **Final decode after live lag:** start a ~2 min take; if possible throttle CPU so live falls behind; stop → full transcript (not only the last ~45 s).
- [ ] **Long take under retain cap:** ~3–5 min spoken session (buffer still complete) → full words on clipboard.
- [ ] **Quiet-room calibrate:** Configuration → Calibrate quiet room (stay silent) → note shows room/gate values; soft speech still marks heard / transcribes; Reset restores default; relaunch keeps calibration until Reset.
- [ ] Calibrate with silence-stop set to 1.25 s → speech then quiet still auto-stops.
- [ ] Calibrate button disabled while a session is recording.

### Proposed polish / features (ranked)

1. ~~Menu bar phase icon + status / error cues~~ — **done** (Run 3).
2. ~~Clearer settings / shortcut copy + a11y labels~~ — **done** (Run 3).
3. ~~First-run “try a 5-second session”~~ — **done** (Run 4).
4. ~~Faster first transcript (prewarm + deferred prepare)~~ — **done** (Run 5).
5. ~~Cap / slice live `speechSamples`~~ — **done** (Run 5).
6. ~~One-click “Copy again” in the menu~~ — **done** (Run 5).
7. ~~Quiet-room calibration~~ — **done** (Run 6).
8. **Processing island status label** — optional “Transcribing” text in the capsule (today: wave-only by design; menu bar carries the cue). *(UX — later if demos still confuse)*
9. **Per-display chrome placement lock** — keep the island on the recording display. *(UX — later)*
10. **Session history scrubber** / **export share sheet** — *(features — later)*

### What’s next (later runs)

- Hardware-confirm Run 5–6 items on a real Mac before the launch video.
- Do not touch `promo-video`.

---

## Run 5 — Performance

### Re-audit of Run 4 (onboarding)

| Change | Verdict |
| --- | --- |
| Model download → `UserFacingError.modelDownload` | Sound; kept. |
| Permissions recovery + mic dialog on Home Turn On | Sound; kept. |
| Onboarding model progress / Continue disabled | Sound; kept. |
| Practice session (`startOnboardingPractice`, skip paste) | Sound; kept. PTT auto-stop still gated by `ignorePushToTalkAutoStop`. |
| Empty Home / History copy | Sound; kept. |
| Live `consume` still re-decoded the full PCM array | Fixed this round (window slice). |
| `speechSamples` unbounded for long sessions | Fixed this round (retain cap + file fallback). |
| `prepare` used `prewarm: false` | Fixed this round. |
| Speech-follow Task was `@MainActor` for PCM copy | Fixed this round (copy off main). |

### Fixed / added this round

1. **Whisper prewarm** (`WhisperKitTranscriber.makePipe`)  
   `prewarm: true` so Core ML special-token prefill runs when the model loads. First transcript after download / launch prepare is warmer. Launch `prepareModel()` waits ~450 ms so the menu bar / welcome window can paint first.

2. **Live decode window** (`LiveSampleWindow`, `Transcriber.decode`)  
   Live (and tail) decode now slices to ~45 s with a short overlap before `clipStart`, instead of shipping the entire growing buffer into Whisper every second. Timestamps are shifted back to session-absolute time. Live path uses 2 concurrent workers; final uses 4.

3. **PCM retain cap** (`AudioRecorder`)  
   In-memory float samples soft-cap at ~10 minutes (~38 MB) with slack so `removeFirst` is rare on the audio queue. Absolute sample count / `SpeechBufferSnapshot.timeOffset` stay correct after trim. When the buffer was trimmed, stop passes empty samples so the AAC file is decoded and merged with live-confirmed words (`decodeFileMergingLive`).

4. **Speech-follow off the main actor** (`SessionController.startSpeechFollow`)  
   PCM snapshot + `consume` no longer run as a MainActor-bound loop; only `keepTranscribing` / `lastSpeechCount` hop to main. Avoids island hitches when copying multi-minute buffers.

5. **File path keeps live words** (`decodeFileMergingLive`)  
   Final file decode now merges with live-confirmed words (and can clip from `confirmedEnd`), including the capped-buffer fallback and the old tail-failure fallback.

6. **Performance settings energy** (`PerformancePage`, `MachineLoad`)  
   Model-folder byte walk runs at most every ~30 s (or on Refresh); RSS still updates every 2 s while the page is open.

7. **Copy Last Again** (ranked #6) (`PasteFollowUp.restoreClipboard`, menu)  
   Menu item re-stages the last image / transcript on the pasteboard after another app overwrote it, without pasting. Falls back to `SessionController.copyToClipboard` when paste-follow state is empty but the last session payload is still in memory.

### Suspected but not verified on a Mac

- Prewarm adds a bit of CPU/memory right after launch / download; confirm the 450 ms defer keeps the welcome window snappy.
- Live window + clipTimestamps timestamp alignment on a multi-minute take (words near the holdback boundary).
- Trimmed-buffer stop: AAC file merge still matches a short take’s live words.
- MenuBarExtra SF Symbol swaps (carry-over).
- Soft speech vs `noSpeechThreshold: 0.6` (carry-over).

### Test this tomorrow on a Mac

**Carry over from Runs 1–4** (abbreviated)

- [ ] Silence P0 + soft speech + menu bar busy icon + plain-language errors.
- [ ] PTT release-during-begin; cancel mid-capture; volume restore; paste-once.
- [ ] Fresh onboarding + practice 5 s take; model download progress + plain errors.

**New for Run 5**

- [ ] **Cold launch:** quit app, relaunch with model already on disk → welcome/settings appear promptly; within a few seconds Performance shows model Loaded; first spoken session’s stop feels faster than a never-prewarmed build.
- [ ] **After onboarding download:** finish model step → wait for prepare → practice or Home Start → first transcript should not sit long on Preparing.
- [ ] **Live long take:** speak continuously ~2–3 minutes → stop → last words present; Activity Monitor: app memory should not climb without bound during a much longer take (beyond ~10 min PCM retain, RSS growth should flatten while recording).
- [ ] **Very long session (optional):** record >10 minutes with speech → stop → full transcript (file path) still OK; menu shows words / No speech detected as appropriate.
- [ ] **Island during record:** waveform stays smooth (no multi-second freezes) while live transcription runs.
- [ ] **Idle:** sit in menu bar with Settings closed for a minute → CPU near idle (no spin from speech timers).
- [ ] **Copy Last Again:** finish a session → copy something else in another app → menu **Copy Last Again** → Mutter image/transcript restored; Paste Image and Text still works.
- [ ] Performance page: open it, watch Refresh; leaving it open should not peg CPU from folder walks.

### Proposed polish / features (ranked)

1. ~~Menu bar phase icon + status / error cues~~ — **done** (Run 3).
2. ~~Clearer settings / shortcut copy + a11y labels~~ — **done** (Run 3).
3. ~~First-run “try a 5-second session”~~ — **done** (Run 4).
4. ~~Faster first transcript (prewarm + deferred prepare)~~ — **done** (Run 5).
5. ~~Cap / slice live `speechSamples`~~ — **done** (Run 5).
6. ~~One-click “Copy again” in the menu~~ — **done** (Run 5).
7. **Quiet-room calibration** — one-time noise floor sample to tune `SpeechGate` / silence stop. *(stability)*
8. **Processing island status label** — optional “Transcribing” text in the capsule (today: wave-only by design; menu bar carries the cue). *(UX — later if demos still confuse)*
9. **Per-display chrome placement lock** — keep the island on the recording display. *(UX — later)*
10. **Session history scrubber** / **export share sheet** — *(features — later)*

### What’s next (later runs)

- Hardware-confirm silence P0, soft speech, prewarm, long-take memory, Copy Last Again on a real Mac.
- Quiet-room calibration (ranked #7) if demos still need silence tuning.
- Do not touch `promo-video`.

---

## Run 4 — Onboarding / first-run

### Re-audit of Run 3 (UX polish)

| Change | Verdict |
| --- | --- |
| Busy-phase menu icon + a11y label | Sound; kept. |
| Transcription → `lastError` | Sound; kept. |
| `UserFacingError` for session/transcription | Sound; kept. Extended: model picker still dumped raw `localizedDescription` — fixed. |
| Menu / Home / Configuration shortcut copy | Sound; kept. |
| Island / RecordingPage a11y | Sound; kept. |
| Onboarding ready-line only | Incomplete for first-run; this round redesigns onboarding. |

### Fixed / added this round

1. **Model download errors were still technical** (`ModelTransfer` / `UserFacingError.modelDownload`)  
   Picker and onboarding download failures now map through calm copy (network, disk, cancel, `Error Domain=…`).

2. **Permission recovery on first run** (`OnboardingFlow`, `Permissions`, `HomePage`)  
   Each permission row explains why it is needed and how to recover when Off / denied. Entering the permissions step prompts mic, screen, **and** Accessibility (Run 1 only covered Accessibility from Settings reveal). Home “Turn On” also requests the mic dialog before opening Settings. `microphoneNeedsSettings()` detects denied/restricted mic.

3. **Model step clarity** (`OnboardingFlow`)  
   Progress bar + percent while downloading; success line when the selected model is on disk; Continue stays disabled during transfer.

4. **Hotkey discoverability** (`OnboardingFlow` shortcut step)  
   Notes that the menu bar repeats the chord; mentions push-to-talk as a later Configuration option.

5. **First-run empty states** (`HomePage`, `HistoryPage`)  
   Home shows a “No sessions yet” row with permission / model / shortcut guidance. History empty copy points at the live shortcut and Home Start.

6. **Try a 5-second session** (ranked #3) (`OnboardingFlow.practice`, `SessionController.startOnboardingPractice`)  
   Flow is now Welcome → Permissions → Shortcut → Model → **Try a session** → Ready (removed the text-only “A session” step). Practice awaits a real begin, auto-stops after ~5s, skips paste-on-stop so the welcome window is not disrupted, ignores PTT auto-stop (practice does not arm the chord), and always ends on a canned success path (including the quiet-room “No speech detected” explanation). Cancel / Back / Skip / window close tear down cleanly.

### Suspected but not verified on a Mac

- Accessibility prompt + Screen Recording dialog stacking order on first Continue into Permissions.
- Practice take while the welcome window is key — island should still appear; clipboard should update without paste-into-window.
- MenuBarExtra SF Symbol swaps (carry-over).
- Soft speech vs `noSpeechThreshold: 0.6` (carry-over).

### Test this tomorrow on a Mac

**Carry over from Runs 1–3** (abbreviated — full lists remain under those runs)

- [ ] Silence P0 + soft speech + menu bar busy icon + plain-language transcription errors.
- [ ] PTT release-during-begin; cancel mid-capture; volume restore; paste-once.

**New for Run 4**

- [ ] **Fresh install / reset onboarding:** delete `onboarding.finished` (or new user defaults) → welcome window opens instead of Settings.
- [ ] Permissions step: Continue from Welcome → mic dialog and Accessibility prompt appear; Turn On opens the right Settings pane; deny mic → recovery copy; grant all → Reopen → rows show On.
- [ ] Shortcut step: Change chord → menu and Ready copy show the new chord; “Use ⌃⌥Space” resets.
- [ ] Model step: Download Balanced → linear progress + percent on Continue; kill network mid-download → plain-language error (not `Error Domain=…`); after success, Continue advances.
- [ ] **Practice:** with permissions + model ready → “Try a 5-second session” → island appears → auto-stop → canned success (spoken or quiet). Clipboard updated; welcome window not pasted into.
- [ ] Practice Cancel mid-take → session discarded; Continue works afterward.
- [ ] Skip setup from any step → Settings opens; onboarding does not return on relaunch.
- [ ] Home with zero sessions → “No sessions yet” tip; History empty copy mentions the live shortcut.
- [ ] Home Turn On with mic notDetermined → system mic dialog, then Settings.

### Proposed polish / features (ranked)

1. ~~Menu bar phase icon + status / error cues~~ — **done** (Run 3).
2. ~~Clearer settings / shortcut copy + a11y labels~~ — **done** (Run 3).
3. ~~First-run “try a 5-second session”~~ — **done** (Run 4).
4. **Faster first transcript** — stronger model prewarm after onboarding download; show pill progress more clearly. *(performance — next)*
5. **Cap / slice live `speechSamples`** — avoid unbounded memory and full-buffer redecode on long sessions. *(performance / stability)*
6. **One-click “Copy again”** in the menu when clipboard was overwritten. *(launch-worthy)*
7. **Quiet-room calibration** — one-time noise floor sample to tune `SpeechGate` / silence stop. *(stability)*
8. **Processing island status label** — optional “Transcribing” text in the capsule (today: wave-only by design; menu bar carries the cue). *(UX — later if demos still confuse)*
9. **Per-display chrome placement lock** — keep the island on the recording display. *(UX — later)*
10. **Session history scrubber** / **export share sheet** — *(features — later)*

### What’s next (later runs)

- Hardware-confirm silence P0 + soft speech + onboarding practice on a real Mac.
- Performance: model prewarm after onboarding download + live sample capping.
- Do not touch `promo-video`.

---

## Run 3 — UX polish

### Re-audit of Run 2 (stability)

| Change | Verdict |
| --- | --- |
| Tap buffer `memcpy` before async | Sound; kept. |
| Speech-follow cancel + throwing sleep | Sound; kept. |
| PTT release-during-begin latch + `!isArmed` auto-finish | Sound; covers key-up before `isStarting`. |
| Volume restore only when raise returns a prior | Sound; kept. |
| PTT `disarm` removes monitors | Sound; `arm` reinstalls. |
| Cancel / abandon cancel capture + speech + `stopTimer` | Sound; kept. |
| Live decode advances `lastCount` on error | Sound; kept. |
| Tail decode full-file fallback | Sound; kept. |
| Final `windowClipTime: 1.0` / live `0` | Sound; kept. |
| Overlay `onScreensChanged` → `syncOverlay` | Sound; kept. |
| `pasteBoth` early-return while delivering | Sound; kept. |
| Empty-speech menu cue | Sound; kept. Extended: transcription failures now also set `lastError`. |

### Fixed / polished this round

1. **Menu bar icon ignored busy phases** (`SessionController.menuIcon`, `PromptAnnotatorApp`)  
   Idle and saving/transcribing/downloading all showed the pencil tip. Busy phases now use `ellipsis.circle`; recording stays `record.circle.fill`. Accessibility label names the live phase (and last error when idle).

2. **Transcription failures were invisible in the menu** (`SessionController.finish`)  
   `transcriptionError` was written to the session notes but never set `lastError`, so a failed decode looked like a silent no-op. Failures now set a calm `lastError` and still win over “No speech detected”.

3. **Technical `localizedDescription` on start / write / capture / transcription** (`UserFacingError`)  
   Maps network, missing-model, cancel, and `Error Domain=…` blobs into short user copy. Export errors still pass through.

4. **Menu shortcut discoverability** (`SessionMenu`)  
   Replaced bare `Shortcut: …` with “⌃⌥Space starts and stops” (or “Hold … to talk” for push-to-talk). Cancel line kept. Status line uses `menuStatusLine` (live phase or last cue). Paste disabled while recording/busy.

5. **Home page live status + clearer copy** (`HomePage`)  
   Start row tracks phase (icon + title), explains the shortcut, and notes the menu bar icon while busy. Capture blurb tightened for first-time viewers.

6. **Configuration shortcut wording** (`ConfigurationPage`)  
   “Start and stop” instead of “Toggle recording”; details include the live chord; cancel explains optional vs set; notes that the menu bar repeats the shortcut.

7. **Accessibility** (`RecordingIsland`, `RecordingPage`, `HomePage`)  
   Island exposes a combined VoiceOver label (phase, clock, capture count). Default tool/color buttons get labels + selected traits. Permission buttons get hints.

8. **Onboarding ready line** — mentions the menu bar icon state change during save/transcribe (no onboarding flow redesign).

### Suspected but not verified on a Mac

- MenuBarExtra label SF Symbol swaps mid-session (should refresh; confirm on Sonoma/Sequoia).
- Soft speech vs `noSpeechThreshold: 0.6` (carry-over).
- Dual mic path / long-session sample growth (carry-over).

### Test this tomorrow on a Mac

**Carry over from Runs 1–2**

- [ ] Fresh permissions: deny all → Turn On → app appears on Accessibility + Screen Recording lists; grant → session starts.
- [ ] Start session with “raise input volume” on → stop → confirm system mic level restored (also when volume was already ≥ 85%).
- [ ] Drag-capture, then immediately cancel → no resurrected session folder under `~/Documents/PromptAnnotator/Sessions/`.
- [ ] Plug/unplug a display while recording with marks → marks still draw on the active screen.
- [ ] **Silence P0:** record 10–20s of nobody speaking → empty transcript; menu shows **No speech detected**.
- [ ] Speak normally including “silence” and “(yesterday)” → those stay.
- [ ] Speech-only session → transcript on clipboard, no sheet.
- [ ] Multi-tile session → numbered paste text matches sheet badges.
- [ ] **PTT:** brief press/release during mic prompt → session must stop.
- [ ] Cancel mid-drag-capture → next session’s first capture still works.
- [ ] Quit while recording → mic volume restored; PTT chord works after relaunch.
- [ ] Soft speech ~5s still transcribes.
- [ ] Double “Paste Image and Text” → one paste sequence.
- [ ] Live transcription ~30s → last words present.

**New for Run 3**

- [ ] **Menu bar icon:** idle = pencil tip; while recording = filled record; while Saving / Preparing / Transcribing / Downloading = ellipsis circle (not idle).
- [ ] VoiceOver on the menu bar item announces “Mutter, recording” / “Mutter, transcribing” (etc.).
- [ ] Force a transcription failure (e.g. delete model mid-session or offline download) → menu shows a plain-language error, not `Error Domain=…`.
- [ ] Quiet stop → menu still shows **No speech detected** (unchanged).
- [ ] Menu text reads “⌃⌥Space starts and stops” (or Hold… when push-to-talk is on); cancel chord listed when set.
- [ ] Home → Start row title tracks Recording / Saving / Transcribing; shortcut badge matches Configuration.
- [ ] Configuration → “Start and stop” row shows the live chord in the detail line.
- [ ] VoiceOver on the floating island while recording announces phase + clock (+ capture count when > 0).
- [ ] Recording settings: tool/color defaults announce name and selected state.

### Proposed polish / features (ranked)

1. ~~Menu bar phase icon + status / error cues~~ — **done** (Run 3).
2. ~~Clearer settings / shortcut copy + a11y labels~~ — **done** (Run 3).
3. **First-run “try a 5-second session”** inside onboarding with a canned success path. *(onboarding — later)*
4. **Faster first transcript** — stronger model prewarm after onboarding download; show pill progress more clearly. *(performance — later)*
5. **Cap / slice live `speechSamples`** — avoid unbounded memory and full-buffer redecode on long sessions. *(performance / stability — later)*
6. **One-click “Copy again”** in the menu when clipboard was overwritten. *(launch-worthy — later)*
7. **Quiet-room calibration** — one-time noise floor sample to tune `SpeechGate` / silence stop. *(stability — later)*
8. **Processing island status label** — optional “Transcribing” text in the capsule (today: wave-only by design; menu bar carries the cue). *(UX — later if demos still confuse)*
9. **Per-display chrome placement lock** — keep the island on the recording display. *(UX — later)*
10. **Session history scrubber** / **export share sheet** — *(features — later)*

### What’s next (later runs)

- Hardware-confirm silence P0 + soft speech + menu bar icon swaps.
- Onboarding try-session (ranked #3) once checklist is green.
- Performance: model prewarm + live sample capping.
- Do not touch `promo-video`.

---

## Run 2 — stability & correctness

### Re-audit of Run 1 diff

| Change | Verdict |
| --- | --- |
| Cancel vs in-flight capture | Sound; kept. Extended with `captureTail.cancel` + `Task.isCancelled` after await. |
| Mic volume restore | Bug in restore path: `previousVolume = raise…` cleared the saved prior when raise returned `nil` (already ≥ 0.85). Fixed. |
| Accessibility prompt | Compiles; standard `AXIsProcessTrustedWithOptions`. |
| Overlay screen rebuild | Compiles; `queue: .main` + `assumeIsolated` OK. Now also re-syncs session marks via `onScreensChanged`. |
| NonSpeechFilter + decoder options | Compiles against WhisperKit 1.1.1. Tuned: final decode uses `windowClipTime: 1.0`; live stays `0`; `noSpeechThreshold` back to `0.6` (less quiet-speech clipping). |
| Dead hotkey `return` | Fine. |

### Fixed this round

1. **Tap buffer use-after-return** (`AudioRecorder`)  
   AVAudioEngine tap buffers are only valid inside the callback. We now `memcpy` into an owned `AVAudioPCMBuffer` before `captureQueue.async`.

2. **Live speech task could resurrect after cancel** (`SessionController.startSpeechFollow`)  
   Prior task used `try?` sleep (swallows cancel) and was never cancelled before a new follow started. Now cancel the previous task, loop on `!Task.isCancelled`, and use throwing sleep.

3. **Push-to-talk release during `begin()` was dropped**  
   Key-up while awaiting mic permission left the session stuck recording. Latch `pushToTalkReleasedWhileStarting`; auto-`finish()` once recording starts if already released. Disarm on begin failure / finish / cancel / abandon.

4. **Mic volume restore wiped when raise skipped** (`AudioInputs`)  
   Only assign `previousVolume` when `raiseInputVolume` returns a prior value.

5. **PTT monitors leaked for process life** (`PushToTalk.disarm`)  
   `disarm()` now removes global/local keyUp monitors.

6. **Cancel / quit left capture + meters running**  
   `cancel` and `abandonIfRecording` cancel `captureTail`, nil `speechTask`, and `abandon` uses `stopTimer()` (levels + clock).

7. **Live decode error retry storm** (`Transcriber.consume`)  
   On failure, advance `lastCount` so the same failing window is not re-decoded every second.

8. **Tail decode failure dropped holdback second** (`Transcriber.transcribe`)  
   Fall back to full-file VAD decode before giving up on confirmed-only words.

9. **Final decode used live `windowClipTime: 0`**  
   Final/file path now uses `1.0`; live decode keeps `0`. `noSpeechThreshold` restored to `0.6` with `suppressBlank` + filter still on.

10. **Overlay rebuild after display change lost marks on new IDs**  
    `onScreensChanged` → `syncOverlay()`.

11. **Overlapping `pasteBoth`** (`PasteFollowUp`)  
    Early-return when already delivering.

12. **Launch cue: empty transcript after stop** (ranked #1)  
    Menu shows `No speech detected` when paste text is empty and there was no transcription error (quiet-room demos no longer look “broken”).

13. **Meter path wrote `currentLevel` outside the lock** (`AudioRecorder.sampleLevels`).

### Suspected but not verified on a Mac

- Unbounded `speechSamples` + full-array live redecode on very long sessions (mitigated if max-session minutes is set).
- Quartz↔AppKit mapping for unusual multi-monitor arrangements.
- Dual mic path (`AVAudioRecorder` + engine tap) on some devices — tap may be silent; meters fall back.
- Quit mid-`.finishing` can still leave a partial session folder (abandon stops IO; in-flight write may not complete).
- Soft speech vs `noSpeechThreshold: 0.6` — confirm quiet speakers still land on clipboard.

### Test this tomorrow on a Mac

**Carry over from Run 1**

- [ ] Fresh permissions: deny all → Turn On → app appears on Accessibility + Screen Recording lists; grant → session starts.
- [ ] Start session with “raise input volume” on → stop → confirm system mic level restored (also when volume was already ≥ 85%).
- [ ] Drag-capture, then immediately cancel → no resurrected session folder under `~/Documents/PromptAnnotator/Sessions/`.
- [ ] Plug/unplug a display while recording with marks → marks still draw on the active screen.
- [ ] **Silence P0:** record 10–20s of nobody speaking (fan/keyboard ok) → transcript and clipboard text empty (no `[BLANK_AUDIO]` / `(silence)` / `[Music]`); menu shows **No speech detected**.
- [ ] Speak normally including the word “silence” and a real aside like “I said (yesterday)” → those stay.
- [ ] Speech-only session (no tiles) → transcript on clipboard, no sheet.
- [ ] Multi-tile session → numbered paste text matches sheet badges.
- [ ] Very short tap start/stop and a long session near max minutes.

**New for Run 2**

- [ ] **PTT:** enable push-to-talk; press chord briefly (release during any mic prompt or immediately) → session must stop, not stay recording.
- [ ] Cancel mid-drag-capture → next session’s first capture still works (no stuck capture queue).
- [ ] Quit while recording → system mic volume restored; no orphaned PTT monitors (press/release chord after relaunch once).
- [ ] Soft / quiet speech still transcribes after silence filter (speak softly for ~5s).
- [ ] Double-trigger “Paste Image and Text” quickly → only one paste sequence.
- [ ] Live transcription: speak continuously ~30s, stop → last words present (holdback / tail fallback).

### Proposed polish / features (ranked)

1. ~~Launch-ready silence confidence~~ — **done** (menu cue).
2. **First-run “try a 5-second session”** inside onboarding with a canned success path. *(onboarding / UX — later)*
3. **Faster first transcript** — stronger model prewarm after onboarding download; show pill progress more clearly. *(performance — later)*
4. **Cap / slice live `speechSamples`** — avoid unbounded memory and full-buffer redecode on long sessions. *(performance / stability — later)*
5. **One-click “Copy again”** in the menu when clipboard was overwritten. *(launch-worthy — later)*
6. **Quiet-room calibration** — one-time noise floor sample to tune `SpeechGate` / silence stop. *(stability — later)*
7. **Session history scrubber** — replay tiles + transcript side by side. *(feature — later)*
8. **Export share sheet** — save sheet PNG + markdown in one drag. *(feature — later)*
9. **Per-display chrome placement lock** — keep the island on the recording display. *(UX polish — later)*

### What’s next (later runs)

- Hardware-confirm silence P0 + soft speech with `noSpeechThreshold: 0.6`.
- Onboarding / first-run try-session (ranked #2) once stability checklist is green.
- Live sample capping if long-session memory shows up in Instruments.
- Do not touch `promo-video`.

---

## Run 1 — audit + solidify before launch

### Checked

| Area | Notes |
| --- | --- |
| Session lifecycle | `SessionController` begin/finish/cancel, phase machine, debounce, push-to-talk |
| Capture pipeline | `DisplayCapture`, region crop, capture queue (`captureTail`), multi-display overlay |
| Audio | `AudioRecorder` engine tap + file recorder fallback, `AudioInputs` device/volume |
| Speech | WhisperKit live consume + final decode, `LiveWordBuffer`, model download/prepare |
| Clipboard | Image-first copy, `PasteFollowUp` second paste for transcript |
| Permissions | Mic / screen / accessibility gates, onboarding + settings “Turn On” |
| Menu bar | `MenuBarExtra`, hotkey center, cancel chord, quit/`abandonIfRecording` |
| Edge cases (code review) | Empty tiles (intentional transcript-only), short/long session limits, silence stop |
| Promo | Did not touch `promo-video` or promo assets |

### Fixed

1. **Cancel vs in-flight capture race** (`SessionController.performCapture`)  
   After `DisplayCapture` awaits, a cancel could clear `directory` while the capture still wrote frames (and could recreate a deleted session folder). Now the shot is discarded unless `directory` still matches the session that enqueued it.

2. **Mic volume not restored** (`AudioInputs`)  
   “Raise input volume” permanently changed the system input level. `endSession` now restores the prior scalar.

3. **Accessibility never prompted onto the list** (`Permissions`)  
   Opening System Settings alone often leaves the app off the Accessibility list. `revealSettings` now calls `AXIsProcessTrustedWithOptions` with the prompt flag (and still opens Settings).

4. **Permission Settings opened only once per process** (`SessionController.offerPermissions`)  
   After the first denial, a different missing set (e.g. mic fixed, screen still off) never re-opened Settings. Now re-offers when the missing summary changes.

5. **Dead unreachable return in hotkey handler** (`Hotkey.swift`)  
   Removed leftover `return noErr` after `eventNotHandledErr` so cancel/paste hotkeys fall through correctly.

6. **Overlay missed new displays mid-session** (`OverlayController`)  
   Rebuilds and re-shows panels on `didChangeScreenParameters` while recording.

7. **Whisper non-speech captions on silence (owner P0)**  
   Quiet rooms were producing `[BLANK_AUDIO]`, `(silence)`, `[Music]`, `(typing)`, `[keyboard clacking]`, etc. on the clipboard.  
   - **Decoder:** `suppressBlank: true`, shared `decodingOptions` for live + final.  
   - **Post-filter:** `NonSpeechFilter` strips bracketed/parenthesized sound labels and `BLANK_AUDIO`-style tags; keeps real spoken parentheticals like `(yesterday)`; does **not** drop the spoken word “silence”. Applied in `Transcriber.words(from:)` and again in `Aligner.spokenText`.  
   - **Tests:** `NonSpeechFilterTests` (pure logic, no WhisperKit).
