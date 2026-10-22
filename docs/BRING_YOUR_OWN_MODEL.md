# Bring Your Own Model (BYOM)

Design notes for da transcribuh’s speech-engine flexibility. **Implemented on `overnight-audit`:** custom WhisperKit Core ML folders, Hugging Face repo+variant downloads, and an optional OpenAI-compatible `/v1/audio/transcriptions` final engine (Keychain API key, live captions off). whisper.cpp remains deferred.

Original analysis goal: understand how hard it would be to let da transcribuh users plug in their own speech-to-text engine while keeping the current WhisperKit path as the default.

## Current state

da transcribuh’s live and final transcription go through `Transcribing` → `WhisperKitTranscriber`:

- Fixed Hugging Face repo (`argmaxinc/whisperkit-coreml`) and a small set of English Core ML variants.
- Local PCM for live decode; AAC file (or merged PCM) for the final pass.
- Progress callbacks for download / prepare / transcribe.
- Word-level timings consumed by aligner + contact sheet.

Any BYOM design should preserve that session lifecycle: prepare → consume while recording → final transcribe on stop.

## Options

### A. Whisper-family Core ML via WhisperKit (recommended default extension)

**What:** Let the user point at a folder of WhisperKit/Core ML bundles (or pick another variant from a known HF repo), still decoded by WhisperKit.

| | |
| --- | --- |
| Fit | Highest — same API, timings, streaming shape. |
| Hard | Low–medium. UI for folder/variant, validation of required `.mlmodelc` pieces, sandbox bookmarks. |
| Streaming | Already supported. |
| Risks | Broken or incomplete bundles; huge models (memory); non-English models vs our English-oriented paste path; download UX if we still fetch from HF. |

### B. whisper.cpp GGML / GGUF

**What:** Ship or link whisper.cpp (or a Swift wrapper) and load user `.ggml` / `.gguf` files.

| | |
| --- | --- |
| Fit | Medium — good offline story, wide model zoo. |
| Hard | High. New native dependency, build/signing, Metal vs CPU, map tokens → `TimedWord`, parallel live+final pipeline beside WhisperKit. |
| Streaming | Possible (sliding window) but must be built; not free. |
| Risks | Bundle size; App Store / notarization friction; quality/latency tuning; two engines to support. |

### C. OpenAI-compatible `POST /v1/audio/transcriptions`

**What:** Upload clip (or stream, if the server supports it) to a user-configured base URL + API key (local faster-whisper, Whisper.cpp server, Groq, OpenAI, etc.).

| | |
| --- | --- |
| Fit | Medium for final pass; weak for live. |
| Hard | Medium. HTTP client, auth, verbose JSON → words; live path needs either frequent short uploads or “final only” mode. |
| Streaming | Rarely true streaming of partial words over this endpoint; expect final-only or coarse chunks. |
| Risks | Privacy (audio leaves the machine); offline failure; rate limits; schema drift across “compatible” servers; latency on stop. |

## Comparison (stable-release lens)

| Criterion | A Core ML / WhisperKit | B whisper.cpp | C HTTP `/v1/audio/transcriptions` |
| --- | --- | --- | --- |
| Product fit | Best | Good | Good for power users |
| Engineering risk | Lowest | Highest | Medium |
| Live captions | Keeps current behavior | Reimplement | Likely degrade |
| Privacy default | On-device | On-device | User-dependent |
| Model zoo | WhisperKit-converted only | Large GGUF set | Whatever the server loads |

## Recommended approach

**Phase 1 — extend WhisperKit (option A).**  
Expose “Model source”: Built-in variants | Custom Core ML folder. Keep `WhisperKitTranscriber` as the engine. Validate bundle layout before selecting. This unlocks “any Whisper-family model someone has already converted for WhisperKit” without a second decoder.

**Phase 2 (optional) — remote finalization (option C) as an advanced escape hatch.**  
“Final transcript via server” while live decode stays local (or off). Clear privacy copy. Do not block stop on network forever.

**Defer whisper.cpp (option B)** until there is demand that Core ML + HTTP cannot meet; it is a second speech stack, not a setting.

## Abstraction

Keep and widen the existing protocol rather than inventing a parallel one:

```text
Transcribing
  resetLive()
  prepare()
  consume(samples:bufferStart:absoluteEndCount:)   // may be no-op for remote-only
  transcribe(audioURL:samples:onProgress:) -> Transcript
```

Add a small factory / settings surface:

```text
SpeechEngineKind: whisperKitBuiltIn | whisperKitFolder(URL) | openAICompatible(baseURL)
SpeechEngineFactory.make(kind, settings) -> any Transcribing
```

`Transcript` / `TimedWord` remain the currency for aligner and export. Engines that lack token timings return a single span or empty timings; aligner already tolerates sparse words.

## Effort (engineering, not calendar)

| Slice | Scope | Relative effort |
| --- | --- | --- |
| Custom WhisperKit folder + validation + Settings | Option A phase 1 | **S** — roughly a focused feature slice on top of today’s Model page |
| HF repo/variant override beyond the fixed list | Still A | **S–M** — download UX, error paths, disk budget |
| OpenAI-compatible final pass | Option C | **M** — networking, secrets, privacy, fallback when offline |
| whisper.cpp engine | Option B | **L** — native dep, dual pipeline, performance matrix |

For a stable release, only document and design A; implement later behind the existing `Transcribing` boundary.

## Risks checklist

- **Conversion:** Random HF Whisper checkpoints are not WhisperKit Core ML; users must convert (or we only accept known layouts).
- **Size / memory:** Large variants can exceed machine headroom next to screen capture + island Chrome.
- **Streaming:** HTTP and some GGUF setups will not match current live partials; UI must allow “final only.”
- **Sandbox:** User-selected folders need security-scoped bookmarks.
- **Support load:** Every extra engine multiplies “no speech / garbage transcript” failure modes.
- **Security:** API keys in Keychain; never log raw audio URLs with tokens.

## Suggested decision

Ship stability on the current WhisperKit path. Next BYOM feature: **custom WhisperKit Core ML folder** (option A). Treat OpenAI-compatible endpoints as a later advanced option for final transcripts only. Do not take on whisper.cpp until A and C are insufficient.
