# design note: text replacements & custom vocabulary

status: proposal, not built. nothing in this doc ships yet.

## why

whisper gets names and jargon wrong ("curser" for cursor, "web socket" for websocket, ur coworker's name). the paid dictation apps let u fix that once and forget it. da transcribuh has no way to do that today. this is the most likely thing a switcher misses.

## where it plugs in today

- `Export/Aligner.swift` `spokenText(_:)` joins timed words, then runs `NonSpeechFilter.scrub`. this is the text that gets grouped with screen grabs.
- `SessionController.copyToClipboard()` applies `TranscriptText.leadingCapital` (when `capitalizeTranscript` is on) right before `SessionClipboard.copy`.
- `Speech/Transcriber.swift` `decodingOptions(...)` builds WhisperKit `DecodingOptions` (no prompt tokens today).
- `Speech/OpenAICompatibleTranscriber.swift` handles the BYO server path; it also returns words through `NonSpeechFilter.filterWords`.

## v1: plain replacements (small)

- a list of rules: `{ find, replace, wholeWord: true, matchCase: false }`.
- stored as json in application support (`replacements.json`), so it's easy to back up and diff.
- applied once to the final joined transcript, right after `NonSpeechFilter.scrub` in `Aligner.spokenText`, so the session files, the clipboard, and history all agree.
- applied in a new `TranscriptReplacements` enum next to `NonSpeechFilter`, pure string code, easy to unit test (case folding, word boundaries, multi-word finds, punctuation next to the match).
- live captions: leave raw in v1. the island is a preview; final paste is what matters.
- settings: a "words" page with add / remove rows and a test box ("type a sentence, see the result").

## v2: bias the model (medium)

- feed the `replace` side (the correct spellings) into WhisperKit as prompt tokens in `decodingOptions`, so whisper spells them right in the first place.
- needs a token budget cap (whisper prompts are short) and a check that live decode latency doesn't regress.
- for the BYO server path, pass the same words as the `prompt` field of `/v1/audio/transcriptions`.

## v3: snippets (small, after v1)

- a rule flagged `wholeUtterance: true` only fires when the whole take matches the cue ("my calendar link" -> the full url).

## out of scope

- learning from edits automatically.
- ai rewrite. that's a separate opt-in idea.

## open questions for the maintainer

- one global list, or per-app lists later?
- should replacements also apply to clipboard-history re-pastes of old takes, or only new takes?
