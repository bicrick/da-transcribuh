# Mutter overnight audit log

Branch: `overnight-audit` (from `main`). Linux VM — no Xcode build. Changes kept compile-safe and small.

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
   - **Decoder:** `suppressBlank: true`, `noSpeechThreshold: 0.5`, explicit compression/log-prob thresholds, shared `decodingOptions` for live + final.  
   - **Post-filter:** `NonSpeechFilter` strips bracketed/parenthesized sound labels and `BLANK_AUDIO`-style tags; keeps real spoken parentheticals like `(yesterday)`; does **not** drop the spoken word “silence”. Applied in `Transcriber.words(from:)` and again in `Aligner.spokenText`.  
   - **Tests:** `NonSpeechFilterTests` (pure logic, no WhisperKit).

### Suspected but not verified on a Mac

- Unbounded `speechSamples` + retained `CGImage`s per tile on very long sessions (mitigated if max-session minutes is set).
- Push-to-talk global monitors stay installed for app lifetime (harmless but never torn down except quit).
- Quit during `.finishing`/transcription leaves a partial session folder on disk.
- Quartz↔AppKit mapping for unusual multi-monitor arrangements (standard primary-height formula; needs real hardware).
- Whether `noSpeechThreshold: 0.5` is aggressive enough on every mic without clipping quiet speech — needs a quiet-room + soft-speech pass tomorrow.

### Test this tomorrow on a Mac

- [ ] Fresh permissions: deny all → Turn On → app appears on Accessibility + Screen Recording lists; grant → session starts.
- [ ] Start session with “raise input volume” on → stop → confirm system mic level restored.
- [ ] Drag-capture, then immediately cancel → no resurrected session folder under `~/Documents/PromptAnnotator/Sessions/`.
- [ ] Plug/unplug a display while recording → marks still draw on the active screen.
- [ ] **Silence P0:** record 10–20s of nobody speaking (fan/keyboard ok) → transcript and clipboard must be empty (no `[BLANK_AUDIO]` / `(silence)` / `[Music]`).
- [ ] Speak normally including the word “silence” and a real aside like “I said (yesterday)” → those stay.
- [ ] Speech-only session (no tiles) → transcript on clipboard, no sheet.
- [ ] Multi-tile session → numbered paste text matches sheet badges.
- [ ] Very short tap start/stop and a long session near max minutes.

### Proposed polish / features (ranked, do not build yet)

1. **Launch-ready silence confidence** — optional UI cue when stop yields empty transcript (“No speech detected”) so demos don’t look broken.
2. **First-run “try a 5-second session”** inside onboarding with a canned success path.
3. **Faster first transcript** — stronger model prewarm after onboarding download; show pill progress more clearly.
4. **One-click “Copy again”** in the menu when clipboard was overwritten.
5. **Session history scrubber** — replay tiles + transcript side by side for the X demo follow-up.
6. **Export share sheet** — save sheet PNG + markdown in one drag to Finder/Desktop.
7. **Per-display chrome placement lock** — keep the island on the recording display instead of following the mouse every tick.
8. **Quiet-room calibration** — one-time noise floor sample to tune `SpeechGate` / silence stop.

### What’s next (later runs)

- Re-check any CI/test feedback; tighten `NonSpeechFilter` label list from real Mac silence captures.
- Pick the highest polish item from the list above once silence P0 is confirmed on hardware.
