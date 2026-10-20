<p align="center">
  <img src="assets/mark.png" width="128" alt="Prompt Annotator">
</p>

# Prompt Annotator

<p>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white" alt="Swift 5">
</p>

A macOS menu bar app that records your voice and on-screen marks, then puts a tile sheet and transcript on the clipboard. It appears in the Dock and it is not sandboxed. This repository is in beta. The app shows its version and build number.

The menu bar item opens the Prompt Annotator window: Home, History, Recording, Configuration, Sound, Model, and Performance. History searches past transcripts. Configuration rebinds the shortcuts and holds the advanced session settings. Performance shows the app's memory, the model size on disk, and how much of the Mac that is. The recording bar can be Default, Compact, Minimal, or Hidden. Tones for start, capture, and stop are on by default and can be turned off. Sound offers Classic, Soft, Click, and Deep. A spoken stop and a silent stop use different tones. The first launch walks through permissions, the shortcut, how a session works, and which speech model to download.

## How a session works

A tap of the shortcut starts a session. You can just talk. Drag when you want a rectangular snippet of the screen, including the window or modal in front. A click that does not turn into a drag still reaches the page, and scrolling is left alone. Hold **Shift** to annotate: the tool bar appears, and release Shift to save that group of marks as one tile. A second tap stops the session.

The capture is the stacked screen. Sheets, popovers, and the front window stay in the picture. The recording island, the tool bar, and the draw overlay stay out of it. A drag that is only a few points across does not create a tile. Escape cancels a selection in progress.

While Shift is held, the cursor becomes the selected tool: pen (the default), highlighter, crosshair (arrow and rectangle), or I-beam (text). The viewfinder on that bar snippets the screen without leaving the hold; a click that never becomes a drag still reaches the page. The draw surface captures the pointer only while Shift is held, so the app underneath does not receive the shift-click. Releasing Shift screenshots that display, bakes the shapes into the bitmap, and hides the tool bar. A Shift tap that does not leave a mark does not create a tile. A tiny click is not a shape.

Escape cancels the shape in progress. Undo and redo apply to the marks in the current hold. After a group is saved, Undo on the bar drops that last tile.

Text is the latch. Shift-click places a single-line label. Releasing Shift leaves the field open so you can type. Return finishes the label and commits the group. Escape cancels the label.

Stop saves any marks still on screen, then ends the session. Paste into the front app is on by default, and Configuration can turn it off. If you never captured, Stop copies the transcript and does not take a screenshot. Each capture is paired with what you said up to that moment. A capture you take without speaking stays a picture, and nothing is pasted after it. Several captures become one numbered tile sheet, and the pasted words use those same numbers when you did speak. While those words are prepared, the recording bar keeps the waveform moving, then closes.

## Shortcuts

| Action | How |
| --- | --- |
| Start and stop a session | Control-Option-Space |
| Capture a snippet | Drag |
| Draw | Hold Shift |
| Save one marked tile | Release Shift |
| Copy the transcript, or the tile sheet and the numbered words | Stop |
| Paste the picture; the words follow | Command-V |
| Paste the picture and the words | Control-Option-V |

The default shortcut is **Control-Option-Space**. Change it on the Recording page. Option-Space, Command-Space, and Option-Command-Space are left alone, and the shortcut cannot include Shift because Shift draws.

When a session ends, the picture and the words paste into the front app. Turn that off under Configuration, Paste when the session ends. Command-V still pastes the picture, and the words follow in a second paste when you spoke. Each block is numbered to match the tile you commented on. A picture with no words is left out of the text, and a session where nothing was said pastes the picture alone. If the words do not appear, press Paste once more. Control-Option-V pastes the picture and then the words in one step. A session with no capture puts the transcript on the clipboard by itself. The menu can show the last session in Finder.

## Requirements

- macOS 14 or later
- Xcode, with the app built as Swift 5
- Screen Recording, Microphone, and Accessibility

## Permissions

Prompt Annotator asks for:

- **Screen Recording**, to capture the display
- **Microphone**, to record the session
- **Accessibility**, to see the pointer and Shift while another app is focused

It does not request Speech Recognition. Transcription is on-device WhisperKit.

Turn the switches on in System Settings, then quit and reopen. If a switch is already on and the app still asks, turn that switch off and on once. macOS remembers that grant for this signature. Debug and Release are signed with the keychain certificate "Prompt Annotator Local", so a later rebuild stays the same app. If that certificate is not installed, create a code-signing certificate with that exact name, or set the app target's signing identity to Sign to Run Locally.

## Session folder

Files land in `~/Documents/PromptAnnotator/Sessions/<timestamp>/`:

- `sheet.png` — tiles in commit order. A frame wider than about 1280px is scaled down. A smaller snippet stays at its capture size. Marks are baked in. When you spoke, each tile shows its number and timestamp so the words line up with that picture. A silent session is the pictures alone.
- `frames/01.png`, `frames/02.png`, … — the same frames at capture resolution.
- `session.md` — one image per group. A group you spoke about also has its number, timestamp, and the words from the previous commit until this one, so a comment stays matched to that picture. Speech after the last commit until Stop is a closing note on that section. A session with no speech lists the images and does not add a transcript.
- `session.json` — shapes, bounds, display, and word timestamps. Shape points are display points, origin at the top-left, y down.
- `audio.m4a` — the microphone.

## WhisperKit

The model is `small.en_217MB`. The Swift package is [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) version 1.1.1, product `WhisperKit`. `https://github.com/argmaxinc/WhisperKit` redirects there.

The weights come from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml). Setup and the Model page offer three English models from that repo. `small.en_217MB` (about 217 MB, folder `openai_whisper-small.en_217MB`) is the default. `tiny.en` (about 153 MB) is the fast one. `large-v3_turbo` (about 954 MB) is the higher-quality one. Each row has bars for download size, speed, and quality, compared with the other two. WhisperKit's downloader searches for `*<variant>/*`. If the default name does not resolve, the app downloads `small.en` from the same repo instead and records the name it used in `session.md` and `session.json`.

Stills and audio are written before the transcript is finished. The chosen model downloads once into `~/Library/Application Support/PromptAnnotator/Models`. After that the app loads it at launch and keeps it in memory. Speech is transcribed while the session is still recording, so stopping only finishes the last moment. A session with no speech skips that step. The recording bar shows a percent only while the model is downloading.

## Build

Open `PromptAnnotator.xcodeproj` on macOS 14 or later, or:

```sh
xcodebuild -project PromptAnnotator.xcodeproj -scheme PromptAnnotator -destination 'platform=macOS' test
```

The first build fetches the WhisperKit package. The Dock icon is the continuous rounded square drawn by `Config/render-icon.swift` (about 80% of the canvas, the same footprint as the system icons). Regenerate the asset catalog with:

```sh
swift Config/render-icon.swift PromptAnnotator/Assets.xcassets
cp PromptAnnotator/Assets.xcassets/AppIcon.appiconset/icon_512.png assets/mark.png
```

Unit tests cover word alignment, the contact-sheet layout, snippet cropping, markdown, and the shape composite. They do not download the model and they do not click through a live session.
