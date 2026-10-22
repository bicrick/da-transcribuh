<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/wordmark-g-dt-block-dark.png">
    <img src="assets/brand/wordmark-g-dt-block.png" alt="da transcribuh" height="40">
  </picture>
</p>

<p align="center">
  <img src="assets/brand/readme-banner.png" alt="talk. it types. drag if u want the picture too." width="920">
</p>

<p align="center">dictation in ur menu bar. grab the screen when u want the picture with the words.</p>

<p align="center">
  <a href="https://github.com/bicrick/da-transcribuh/releases/latest">download</a>
  ·
  <a href="#install">build from source</a>
  ·
  <a href="LICENSE">MIT</a>
  ·
  macOS 14+
</p>

<!-- TODO: drop a short demo gif at assets/demo.gif (talk, drag, paste) and embed it here when ready -->

## install

download the [latest beta dmg](https://github.com/bicrick/da-transcribuh/releases/download/v0.9.0-beta.2/Mutter.dmg), open it, drag it to applications. done.

<!-- TODO: rename the release asset to da-transcribuh.dmg on the next cut; the current file is still Mutter.dmg -->

from source:

```sh
git clone https://github.com/bicrick/da-transcribuh.git
cd da-transcribuh
open PromptAnnotator.xcodeproj
```

macos 14 or later. the first build fetches whisperkit.

## what it does

- lives in the menu bar. press the shortcut, talk, press it again. words land on the clipboard (and paste into the front app when that makes sense).
- hold **shift** and drag to grab a piece of the screen. release shift to keep the tile. stop the session and you get the picture with the words.
- sessions save under `~/Documents/PromptAnnotator/Sessions/` (folder name stays put so your history doesn’t vanish).
- on-device speech via whisperkit. bring your own core ml folder or hugging face variant if you want. optional openai-compatible server for the final transcript only.

## shortcuts

| | |
| --- | --- |
| start / stop | control-option-space (changeable) |
| mark / capture | hold shift, drag, release |
| paste image + text | control-option-v |
| cancel take | optional; set one in configuration |

## permissions

needs three switches. after you flip them, reopen the app so they stick.

- **microphone** — hears you
- **screen recording** — grabs the tiles you drag
- **accessibility** — watches the shortcut and shift

## models

open **models** in the settings window.

- **on this mac (whisperkit)** — built-in english models (fast / balanced / highest). balanced is the default. download once; it stays on disk.
- **your models** — add a local whisperkit core ml folder, or pull another hugging face variant.
- **openai-compatible server** — optional. final transcript only via `/v1/audio/transcriptions`. live captions stay off. api key lives in the keychain.

more detail: [`docs/BRING_YOUR_OWN_MODEL.md`](docs/BRING_YOUR_OWN_MODEL.md).

## paste behavior

when you stop a session, da transcribuh stages the sheet and the transcript. if a text field is focused, it pastes for you. if not, it leaves everything on the pasteboard and the menu bar says it’s ready — hit ⌃⌥V or ⌘V wherever you’re typing.

cancel drops the take. nothing gets staged.

## troubleshooting

- **no speech detected** — quiet rooms do that on purpose. say a sentence next time.
- **permissions look on but nothing works** — turn the switch off and on, then reopen.
- **model missing** — open models and download balanced (or whatever you picked).
- **paste missed the field** — check the menu bar for the ready-to-paste hint, focus a text field, then ⌃⌥V.
- **updates** — configuration → check. releases live at [github.com/bicrick/da-transcribuh/releases](https://github.com/bicrick/da-transcribuh/releases).

## brand bits

final **dt block** art lives in [`assets/brand/`](assets/brand/):

- `wordmark-g-dt-block.png` / `wordmark-g-dt-block-dark.png` — lowercase “da transcribuh” plus a separate block cursor after the h (light / dark)
- `icon-g-dt-block-1024.png` — app mark
- `readme-banner.png`, `social-preview-1280x640.png`, `social-preview-2560x1280@2x.png`
- `menubar-g-dt-block-16.png` / `menubar-g-dt-block-32.png` — template menu-bar glyph

patrick: upload `social-preview-1280x640.png` (and the `@2x` if you want) under the repo’s **settings → general → social preview** — that part isn’t settable from here.

## license

[MIT](LICENSE). free and open source. be kind.
