# Prompt Annotator

A macOS 14 menu bar app for marking up the screen while you talk. It appears in the Dock and it is not sandboxed.

The menu bar item opens the Prompt Annotator window: Home, Sessions, Recording, Sound, and Model. The default shortcut is **Control-Option-Space**. Change it on the Recording page. A tap starts a session, and a second tap stops it. Clicks keep working. Hold **Shift** to draw. Release Shift and that group of marks becomes one tile. Option-Space, Command-Space, and Option-Command-Space are left alone, and the shortcut cannot include Shift because Shift draws.

The recording island can be Classic, Mini, or Hidden. Sound effects for start, tile, and stop are on by default and can be turned off.

## Hold Shift

While a session is recording, the pointer behaves normally. Hold Shift and the cursor becomes the selected tool: pen (the default), highlighter, crosshair (arrow and rectangle), or I-beam (text). The draw surface captures the pointer only while Shift is held, so the app underneath does not receive the shift-click. The recording island and the markup bar still receive clicks with or without Shift.

Everything you draw before you release Shift is one group. Releasing Shift screenshots that display with ScreenCaptureKit, leaves the overlay, island, and markup bar out of the capture, and bakes the shapes into the bitmap. The canvas clears and the normal cursor comes back. A Shift tap that does not leave a mark does not create a tile. A tiny click is not a shape.

Escape cancels the shape in progress. Undo and redo apply to the marks in the current hold. After a group is saved, Undo on the bar drops that last tile.

Text is the latch. Shift-click places a single-line label. Releasing Shift leaves the field open so you can type. Return finishes the label and commits the group. Escape cancels the label.

Stop captures any marks still on screen, then ends the session. If you only talked, Stop still saves one clean screenshot and the transcript.

## What a session writes

Files land in `~/Documents/PromptAnnotator/Sessions/<timestamp>/`:

- `sheet.png` — numbered tiles in commit order. Each display is scaled to about 1280px wide, with the marks baked in and the number and timestamp on the tile.
- `frames/01.png`, `frames/02.png`, … — the same frames at capture resolution.
- `session.md` — one section per group: number, timestamp, image, and the words spoken from the previous commit until this one. Speech after the last commit until Stop is a closing note on the last section. The full timed transcript is at the bottom.
- `session.json` — shapes, bounds, display, and word timestamps. Shape points are display points, origin at the top-left, y down.
- `audio.m4a` — the microphone.

When the session finishes, the tile sheet and the transcript are placed on the clipboard together. Pasting into Notes or TextEdit inserts the picture and then the words. The done panel can copy them again, and it can show the session in Finder.

Stills and audio are written before transcription. The first transcription downloads the model into `~/Library/Application Support/PromptAnnotator/Models` and shows progress on the recording island.

## Permissions

Prompt Annotator asks for:

- **Screen Recording**, to capture the display
- **Microphone**, to record the session
- **Accessibility**, to see Shift and the pointer while another app is focused

It does not request Speech Recognition. Transcription is on-device WhisperKit.

Turn the switches on in System Settings, then quit and reopen. If a switch is already on and the app still asks, turn that switch off and on once. This Mac signs the debug app with a stable local certificate, so that grant keeps working after later rebuilds.

## WhisperKit model

The Swift package is [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) version 1.1.1, product `WhisperKit`. `https://github.com/argmaxinc/WhisperKit` redirects there.

The model is `small.en_217MB` from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml). That repo contains the folder `openai_whisper-small.en_217MB` (about 217 MB). WhisperKit's downloader searches for `*small.en_217MB/*`, which matches that folder. If that variant name does not resolve at runtime, the app downloads `small.en` from the same repo instead and records the name it used in `session.md` and `session.json`.

## Build

Open `PromptAnnotator.xcodeproj` on macOS 14 or later, or:

```sh
xcodebuild -project PromptAnnotator.xcodeproj -scheme PromptAnnotator -destination 'platform=macOS' test
```

The first build fetches the WhisperKit package. Debug and Release are signed with the keychain certificate "Prompt Annotator Local". If that certificate is not installed, set the app target's signing identity to Sign to Run Locally. Unit tests cover word alignment, the contact-sheet layout, markdown, and the shape composite. They do not download the model and they do not click through a live session.
