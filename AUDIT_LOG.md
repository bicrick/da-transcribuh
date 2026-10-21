# Mutter overnight audit log

Branch: `overnight-audit` (from `main`). Linux VM — no Xcode build. Changes kept compile-safe and small.

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
