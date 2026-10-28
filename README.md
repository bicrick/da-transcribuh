<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/header-dark.png">
    <img src="docs/readme/header-light.png" alt="da transcribuh" width="440">
  </picture>
</p>

<p align="center">
  point at stuff and yap.<br>
  free, on-device dictation in ur mac menu bar.
</p>

<p align="center">
  <a href="https://da-transcribuh-site.vercel.app/download"><b>download</b></a>
  &nbsp;·&nbsp;
  <a href="https://da-transcribuh-site.vercel.app">site</a>
  &nbsp;·&nbsp;
  macOS 14+
  &nbsp;·&nbsp;
  <a href="LICENSE">MIT</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/demo-dark.gif">
    <img src="docs/readme/demo-light.gif" alt="hit the key, a lil island pops up, say stuff, hit it again and it pastes where ur cursor is" width="720">
  </picture>
</p>

1. hit the key. a lil island pops up
2. say stuff. words show up live
3. hit it again. it pastes where ur cursor is

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/features-dark.png">
    <img src="docs/readme/features-light.png" alt="on device, grab the screen, clipboard history" width="880">
  </picture>
</p>

## what it does

- **live captions.** words show up in the island while u talk, so stop only has to finish the last second
- **paste where ur cursor is.** on by default when u stop. hold shift as u stop and it hits return too
- **push to talk.** optional. let go of the key and it stops
- **grab the screen while u talk.** hold the screenshot key and drag over what u wanna show. each grab gets a numbered tile
- **draw on it.** hold the annotate key for pen, highlighter, arrow, box, and text
- **collage paste.** grabs + words go out as one linked paste: the picture, then the words. made for pasting into an ai agent
- **clipboard history.** searchable, with its own shortcut
- **every take saved.** a folder per session with `session.md`, `session.json`, and a contact sheet
- **pick ur model.** `tiny.en`, `small.en` (default), `large-v3 turbo`, or ur own WhisperKit model from a folder or hugging face
- **or ur own server.** point it at any OpenAI-compatible `/v1/audio/transcriptions` endpoint (live captions are off in that mode)
- **rebind everything.** start/stop, cancel, screenshot, annotate, and history keys. plus stop-after-silence, a max session length, and launch at login
- **filler tags stripped.** whisper's `[BLANK_AUDIO]`, `(silence)`, `[Music]` and friends get dropped

## vs the paid ones

free, MIT, on-device by default, and it can paste a screen-grab collage with ur words.

## install

grab the dmg from the [download page](https://da-transcribuh-site.vercel.app/download), drag it into applications, open it.
needs macOS 14 or newer.

it'll ask for a few permissions:

- **microphone**: to hear u
- **accessibility**: to paste where ur cursor is
- **screen recording**: only for screen grabs

default model is `small.en`. u can swap to `tiny.en`, `large-v3 turbo`, or [bring ur own](docs/BRING_YOUR_OWN_MODEL.md).

## build from source

needs Xcode 16+. the first build pulls WhisperKit and Sparkle through swift package manager.

```sh
git clone https://github.com/bicrick/da-transcribuh.git
cd da-transcribuh
xcodebuild -project PromptAnnotator.xcodeproj -scheme PromptAnnotator \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_IDENTITY=- build
open "build/Build/Products/Debug/da transcribuh.app"
```

`CODE_SIGN_IDENTITY=-` ad-hoc signs it so u don't need my cert. in Xcode, set signing to "sign to run locally".
heads up: macOS may ask for permissions again after each rebuild.

## contributing

help is very welcome: bug fixes, models, docs, whatever u find annoying.
start with [CONTRIBUTING.md](CONTRIBUTING.md), then [docs/architecture.md](docs/architecture.md) for a map of the code.

## privacy

by default, transcription runs on ur mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). ur audio and screen grabs stay local.

it only touches the network to download a model, check for updates (Sparkle), or send audio to ur own OpenAI-compatible server if u [set one up](docs/BRING_YOUR_OWN_MODEL.md). that server's API key lives in ur keychain.

## license

[MIT](LICENSE). the font is [Departure Mono](https://departuremono.com) (SIL OFL).
