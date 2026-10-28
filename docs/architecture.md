# architecture

how da transcribuh is put together. file and type names are real, so you can grep for them. the code
still uses the old internal name, PromptAnnotator, for the project, target and folders.

## the short version

```
hotkey (⌥Space by default)
  -> SessionController.begin()
     -> AudioRecorder: mic -> 16 kHz mono PCM buffer (+ AAC file on disk)
     -> Transcribing.consume(): live WhisperKit decode while you talk (captions in the island)
     -> SessionKeyMonitor: hold Shift to grab part of the screen, Control to draw on it
        -> CapturePipeline / DisplayCapture: ScreenCaptureKit grab, crop, PNG encode
hotkey again (or key-up in push to talk)
  -> SessionController.finish()
     -> Transcribing.transcribe(): final pass on the tail of the audio
     -> Aligner: assign timed words to each screen grab
     -> SessionWriter: session folder (session.md, session.json, PNGs) + ContactSheet collage
     -> SessionClipboard: stage collage + words as one linked clipboard entry
     -> PasteFollowUp: paste the picture, then the words, into the focused text field
```

everything above runs on the Mac. the only network calls are the one-time model download, Sparkle update
checks, and the optional OpenAI-compatible server if you set one up.

## folders

all app code is under `PromptAnnotator/`.

| path | what's in it |
|---|---|
| `PromptAnnotatorApp.swift` | app entry point and `AppDelegate`. `Runtime` knows when it's running under tests |
| `SessionController.swift` | the session state machine (`SessionPhase`). owns begin, capture, finish, paste. the biggest file and the place to start reading |
| `Hotkey.swift` | `HotkeyCenter`, global Start/Stop hotkey through Carbon `RegisterEventHotKey` |
| `PushToTalk.swift` | when push to talk is on, releasing the shortcut ends the session |
| `SessionKeyMonitor.swift` | watches keys and the pointer during a session. Shift arms the screenshot crosshair, Control draws with the armed tool. plain clicks still reach the app underneath |
| `Capture/` | `AudioRecorder` (mic and PCM ring), `DisplayCapture` (ScreenCaptureKit), `CapturePipeline` (capture, crop, encode off the main actor), `RegionCrop`, markup mode, waveform bands |
| `Speech/` | the `Transcribing` protocol and its engines: `WhisperKitTranscriber`, `OpenAICompatibleTranscriber`, and `RoutingTranscriber` that picks between them. also model choice, custom model validation and the live word buffer |
| `Export/` | `Aligner`, `ContactSheet`, `SessionWriter`, `SessionClipboard`, `PasteFollowUp`, `PasteModifierGate`, `FocusedEditableProbe` |
| `Overlay/` | the click-through annotation overlay and shape drawing (`AnnotationShape`, `ShapeRenderer`) |
| `Chrome/` | the recording island (the pill), waveform, markup toolbar, menu bar panel |
| `Clipboard/` | optional clipboard history: watcher, disk-backed store, history panel and preview |
| `Settings/` | the settings window, one file per page (`HomePage`, `ModelPage`, `ClipboardPage`, ...). `Settings/Ink/` holds the shared look |
| `Onboarding/` | first-run flow and permission prompts |
| `Support/` | everything else: `AppSettings`, `Permissions`, `KeychainStore`, `UpdateController` (Sparkle), `SessionStore`, logging, perf harnesses |

tests are in `PromptAnnotatorTests/`. build config and entitlements are in `Config/`. release scripts are
in `scripts/`.

## a take, step by step

### 1. start

`HotkeyCenter` registers the Start/Stop chord (⌥Space unless you change it) and calls
`SessionController.toggle()`. `begin()` checks permissions (`Permissions`: microphone, screen recording,
accessibility), starts `AudioRecorder`, shows the recording island, and turns on `SessionKeyMonitor`.

### 2. recording and live transcription

`AudioRecorder` converts the mic to 16 kHz mono PCM. it keeps an in-memory buffer (soft cap around 10
minutes) and also writes an AAC file, so long takes still have their audio.

while you talk, the controller hands new samples to `Transcribing.consume(...)`. with WhisperKit that runs
a live decode, so captions show up in the island and stop only has to finish the last bit of audio.
`LiveWordBuffer` keeps the newest words unconfirmed so the next pass can revise them.

### 3. screen grabs and markup

`SessionKeyMonitor` decides what a key or click means. holding Shift alone arms a crosshair and a drag
grabs that region. holding Control alone draws with the armed tool. typing anything else cancels the hold,
so a capital letter never leaves the crosshair on.

a grab goes through `CapturePipeline.captureAndEncode`. `DisplayCapture` uses `SCScreenshotManager`. with
no marks it captures just the selected rect, with marks it grabs the full display so strokes outside the
selection still bake in. PNG encoding runs on a utility queue, never on the audio path. each grab or
committed drawing becomes a tile with a timestamp.

### 4. stop and the final pass

`finish()` waits for any in-flight capture, ends recording, and calls `Transcribing.transcribe(...)` for
the final transcript with word timings. if a live decode is still running, `abandonLiveDecode()` drops it
so the tail decode can start right away.

### 5. aligning words to grabs

`Aligner` assigns each timed word to the tile whose commit interval contains the word's start. words after
the last grab become the closing note on the last tile. that's how each screenshot ends up next to what you
said about it.

### 6. writing the session

`SessionWriter.writeAsync` writes a session folder (default `Documents/PromptAnnotator/Sessions`, or a
folder you pick, see `SessionStore`) with `session.md`, `session.json` and the PNGs. `ContactSheet` lays
the tiles out into one collage image with numbers and timestamps. this runs off the main actor.

if writing fails, `SessionWriter.rescuedPasteText` still gets the words to the clipboard so nothing you
said is lost.

### 7. clipboard and paste

`SessionClipboard` stages the take. a collage with words goes up as one linked entry: two pasteboard items,
the picture then the words. a manual ⌘V into an app that reads every item gets both.

when the app pastes for you (auto-paste on stop, a history pick, ⌃⌥V), `PasteFollowUp` pastes the picture,
waits a beat, pastes the words, then puts the linked entry back on the clipboard. before posting ⌘V,
`PasteModifierGate` waits until the stop chord's modifiers are physically up, so a held ⌥ doesn't turn the
paste into something else. `FocusedEditableProbe` uses Accessibility to check that a text field has focus.
if nothing does, the paste is held and the menu shows a hint instead.

## speech engines

every engine implements `Transcribing` (`prepare`, `consume`, `transcribe`, plus `resetLive` and `abandonLiveDecode`).
`RoutingTranscriber` sends calls to the engine picked in Settings.

- **WhisperKit (default).** `WhisperKitTranscriber` keeps the model loaded for the life of the process.
  built-in choices are in `SpeechModelChoice` (`tiny.en`, `small.en_217MB` as the default,
  `large-v3_turbo`). models download once from `argmaxinc/whisperkit-coreml` into Application Support.
  you can also point it at your own WhisperKit Core ML folder (`CustomWhisperModel`,
  `WhisperModelValidator`).
- **OpenAI-compatible server (optional).** `OpenAICompatibleTranscriber` posts the audio to
  `POST /v1/audio/transcriptions` on a server you configure and reads `verbose_json` word timings, falling
  back to a single span from `text`. the API key is stored in the Keychain (`KeychainStore`). live captions
  are off with this engine, since it only does the final pass.

design notes and tradeoffs are in [BRING_YOUR_OWN_MODEL.md](BRING_YOUR_OWN_MODEL.md).

## threading

- UI state and the session controller are `@MainActor`
- transcribers are actors
- audio capture runs on its own queue and is never blocked by encode or disk work
- capture, PNG encode and session writes run off the main actor at lower QoS

## updates

`UpdateController` wraps Sparkle 2's `SPUStandardUpdaterController`. it never starts under unit tests.
`Config/Info.plist` turns off background checks (`SUEnableAutomaticChecks` is false), so updates are checked from the menu or Settings. the feed setup and release steps are in [releasing.md](releasing.md).

## other docs

- [clipboard-linked-takes.md](clipboard-linked-takes.md): why a take is one linked clipboard entry
- [perf-audit.md](perf-audit.md), [perf-capture.md](perf-capture.md): performance notes and harnesses
