# Performance audit (October 22, 2026)

Branch `cursor/clipboard-round2-b379`. Machine: Apple M2 Pro, macOS 15.7.4, Release builds.
The machine was busy during the whole sweep (load average 6 to 11), so absolute numbers are noisy.
Every before/after pair below was taken by alternating the two builds round by round
(`ab.sh`), so both sides saw the same load.

Labels: **measured** (from the harness logs), **inferred** (reasoned from code plus a measurement),
**guess** (not verified).

## How it was measured

- `PromptAnnotator/Support/PerfSuite.swift` (commit `c064015`) is a launch-argument harness.
  It does nothing unless a `-DTPerf*` argument is passed. It uses throwaway session and clipboard
  roots (`-DTSessionsRoot`, `-DTClipboardRoot`), never the real clipboard or history.
- Speech runs play `say` voice files (converted with `afconvert` to 16 kHz WAV, plus a -18 dB
  "quiet" copy) through the real recorder and transcriber, then score WER against the script.
- Each metric is a median over at least 5 runs unless noted. CPU from `getrusage`, wakeups from
  `top` idlew, memory from `phys_footprint`. No `powermetrics` (no sudo).

## Results

| Scenario | Before | After | Change | Label |
|---|---|---|---|---|
| History tab switch, 430 sessions | 2354 ms | 78 ms | 30x faster | measured, 9 runs each |
| Back to Home from History, 430 sessions | 426 ms | 78 ms | 5.5x faster | measured, 9 runs each |
| Repeat session reload, 430 sessions | 122 ms | 16 ms | 7.6x faster | measured |
| First session reload, 430 sessions | 191 ms | 178 ms | unchanged | measured |
| Clipboard image copy, 3456x2234 PNG, main thread | 120 ms | 6.8 ms | 18x faster | measured, 9 runs each |
| Clipboard panel first open, 200 items | 714 ms | 245 ms | 2.9x faster | measured, 3 runs each |
| Clipboard panel reopen | 36 ms | 35 ms | unchanged | measured |
| Stop to clipboard, live decode, all clips | 395 ms | 352 ms | 11% faster | measured, 24 stops each |
| Stop to clipboard, 30 s clip | 380 ms | 289 ms | 24% faster | measured, 6 stops each |
| Live loop drain at stop | about 110 ms | 21 ms | 5x faster | measured, 24 stops each |
| Stop to clipboard, final-only decode, 30 s clip | 2022 ms | not changed | | measured |
| Cold launch to Settings visible | 627 ms | not changed | | measured, 5 runs |
| Warm launch to Settings visible | 370 ms | not changed | | measured, 5 runs |
| Model ready after launch | 1.9 to 2.2 s | not changed | | measured |
| Idle CPU, Settings open or closed | 0.03% | not changed | | measured, 30 s windows |
| Idle wakeups (idlew/s), Settings closed | 2.9 to 5.2 | not changed | | measured |
| Record start to island visible | 85 ms | not changed | | measured, 5 runs |
| CPU while recording, live decode | 19 to 21% | not changed | | measured |
| Level meter frame pacing | p50 16.7 ms, p95 19 to 20 ms | not changed | | measured |
| Clipboard panel typing | 38 ms first key, then 11 to 18 ms | not changed | | measured |
| Clipboard panel scroll | p50 0.8 to 9 ms, p95 about 11 ms | not changed | | measured |

Settings tab switches with no history (medians of 5): appearance 58, history 31, clipboard 76,
model 118, configuration 84, sound 60, performance 40, home 47 ms (measured).

## Root causes and fixes

Principles used: explain the number (each fix names the mechanism behind its millisecond count),
fix root causes (no caching over a problem that should not exist), prove it works (alternating A/B
runs, plus a unit test per behavior change).

1. **History built every row** (`6773d60`). `DTScrollView` hosts its content in an `NSHostingView`
   sized to the content's intrinsic height. A `LazyVStack` inside it is measured in full, so all 430
   rows were built on every switch (inferred from the 30x drop once a native `ScrollView` was used).
   Each row also re-filtered the session list to find the selection, O(n²) per body (measured in code).
   Fix: native `ScrollView` for the log table and one selection lookup per body.
   Tradeoff: that table now shows the system overlay scroller instead of the Ink rail.
2. **Every reload decoded every session.json** (`fe68a3b`). Settings reloads on each show and after
   each take. Fix: cache summaries by folder, keyed on session.json modification date and size.
   Test: `testCachedSummariesFollowRewritesAndRemovals`.
3. **Image copies were decoded and re-encoded twice on main** (`a65a64e`). The watcher went
   pasteboard PNG to `NSImage` to TIFF to PNG. Fix: pass the pasteboard's PNG bytes through when they
   carry the PNG signature. TIFF-only boards still convert. Tests: `ClipboardImageIngestTests` (3).
4. **Clipboard panel decoded every thumbnail on first open** (`6261cd3`). Same `DTScrollView` cause as
   #1, so all 200 rows and 67 thumbnails were built on main. Fix: draw cached thumbnails at once, else a
   placeholder plus an off-main ImageIO decode. The remaining 245 ms is building 200 rows (inferred).
5. **Stop waited out the live loop's sleep** (`95d72f9`). `finish()` waited for the follow loop, which
   could be in a 250 ms sleep or mid-decode. Fix: cancel the
   task only while it sleeps (the sleep throws and the loop exits) and let an in-flight decode finish.
   A first version cancelled unconditionally. That cut the in-flight decode short, so the final pass
   had more audio to decode and a cut decode leaked filler words. It was replaced before commit.
   WER is unchanged (same failure mode, same rate within noise).

## Accuracy (WER)

Scored with `wer.py` against the `say` scripts. Live decode is the default path.

| Clip | Live, median WER | Final-only, median WER | Label |
|---|---|---|---|
| short (5 s) | 0% to 10.5% ("the right" dropped in 2 to 3 of 6 runs, always run 1 of a launch) | 0% | measured, 18 runs |
| short, -18 dB | 0% | 0% | measured |
| long (30 s) | 8 to 11% (doubled words at seams, about 2 per run) | 0% | measured, 18 runs |
| long, -18 dB | 4 to 7% | 5.2% | measured |

Live mode loses accuracy at chunk seams on long clips. Whisper drops or repeats the word at the
point where each live decode starts (`clipTimestamps` starts exactly at `confirmedEnd`, so the
`LiveSampleWindow` 0.35 s overlap never reaches the decoder; inferred from code).

**Tried and reverted.** Backing the decode start up by 0.8 s and dropping the echoed boundary word
removed the doubled words on long clips (long median 11.3% to 4.1%, 0 doubled seams in 6 runs).
It made short clips worse. The tail decode then hallucinated ("you you you", "[music") and dropped
"use" in every run (short median 0% to 36.8%), and short stop-to-clipboard went from about 380 ms to
about 730 ms. It was not committed. See recommendation 1.

## Recommendations (in priority order)

Not done in this round, for a follow-up run.

1. **Fix the live seam** (accuracy, high). Live long-clip WER is 8 to 11% against 0% final-only.
   Feed the last confirmed words as a decoder prompt instead of re-decoding audio, or run a full final
   pass when the clip is short (final-only costs about 2 s on a 30 s clip, so maybe only under 15 s).
   The overlap-and-echo attempt above is the evidence for what not to do.
2. **Accuracy settings** (accuracy, high). Measure WER for each model size and for the
   normalize-speech toggle on the quiet clips. Long -18 dB final-only stays at 5.2% in every run, so
   gain or model size is the lever there (guess).
3. **Make `DTScrollView` lazy-capable** (responsiveness, high). Any `LazyVStack` inside it builds every
   row. A wrapper that reports the visible rect would fix the clipboard panel's remaining 245 ms first
   open and let History get the Ink rail back.
4. **Recording start latency** (latency, medium). Begin is about 70 ms median (235 ms on the first
   take), mostly `AVAudioEngine` start (inferred). Pre-warm the engine when the hotkey is armed or
   when Settings opens.
5. **Transcription latency** (latency, medium). After the drain fix, stop to clipboard is about 290 to
   360 ms, almost all the final tail decode (measured stop phases). Decoding the tail while the last
   capture is written, or a smaller tail window, are the next levers (guess).
6. **Recording CPU and energy** (energy, medium). 19 to 27% CPU while recording (measured). The 60 Hz
   levels timer plus waveform rendering is the likely share (inferred). Try 30 Hz and measure.
7. **Idle CPU** (energy, low). Idle is already 0.03% CPU, but wakeups are 2.9 to 5.2 per second with
   Settings closed against 0 to 1.7 with it open (measured). Find the timer that runs only while
   Settings is closed (likely the clipboard watcher poll, guess).
8. **Move clipboard persistence off main** (responsiveness, medium). `ClipboardHistoryStore.persist`
   encodes the pretty-printed JSON index and writes image files on main for every copy.
9. **Single reload on Settings open** (minor). Reload runs twice per open (measured).
10. **Tick timer** (minor). The 0.1 s recording tick allocates a `Task` per tick.
