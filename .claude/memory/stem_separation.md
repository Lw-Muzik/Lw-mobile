# Live Stem Separation (Oct 2026 rewrite)

Vocals / Drums / Instruments levels while a song plays, from the Equalizer's
**Stems** tab. Replaces the March 2026 "tap Separate, wait, 4 WAVs" feature
(StemSeparationService, mmap StemMixer, DSP M/S splitter — all deleted).

## Decisions (user, Oct 10–11 2026)
- Model: **Spleeter 4-stem** (Deezer; weights MIT per the JOSS paper, trained on
  Deezer's own catalogue — NOT MUSDB). Demucs excluded: its author says the
  weights are "provided only for scientific purposes".
- ~~Local files only~~ → **YouTube Music too, streamed and downloaded** (user,
  Oct 11, after the tablet test; told of YouTube Developer Policies III.I.7 "must
  not separate, isolate, or modify the audio" — their call). The exclusion
  ledger, prefixes and `ftypdash` backstop are gone. Cloud streams (Drive /
  Dropbox, uncached) still read `unavailable/stream`; YT *videos* (local DASH
  manifest) read "Can't read this song".
- Model **downloaded on first use** (4 × 19.7 MB fp16 ONNX, SHA-256 pinned),
  primary https://hypemuzik.com/models/stems/spleeter-4stems-fp16-v1/, fallback
  huggingface.co/Best-Practice/spleeter-4stems-onnx.
- UI: faders 0–100% + a pad under each, combo pads Acapella / Karaoke / Drums only.

## Architecture
Shared C++ engine — canonical `android/app/src/main/cpp/stems/`, byte-identical
copy in `ios/HypeDSP/src/stems/` (`tool/sync_stems_native.sh`, `--check`).
- `StemEngine` (singleton, leaked on purpose — ORT aborts in static dtors):
  worker thread decodes each local track itself (`DecodedTrack`, cache file),
  separates ~11.8 s **splits ahead of the playhead** (playhead → +2 splits →
  next track's opening), publishes to `StemStore` (4 seqlock slots per track:
  mix int16 exact, vocals/drums int16 at half scale).
- `StemTap` (one per player audio path, audio thread, lock-free): knows
  track + sample, captures 8192 live frames after every discontinuity, the
  worker cross-correlates (`align.cpp`) to find the decode↔player offset, then
  the tap outputs `gV·V + gD·D + gI·(M − V − D)` with a 50 ms crossfade. All
  levels at 100% → untouched pass-through.
- Splits overlap 4 STFT frames (step 508): each owns its range with a 512-sample
  exact margin (room for the resampler at 48 kHz) and can be computed in any order.
- **No fixed grid** (Oct 11): a split can start anywhere (`chunkOwnedEnd/
  chunkSpanStart`). The next one starts where the separated run ahead ends; when
  the playhead is in a hole (seek, stems just on) or the run ahead is shorter
  than a job, it starts at `playhead + ¾·lead` — lead = moving average of real
  job times ×1.15 + 0.3 s (6 s assumed until one is timed this session). The tap
  only fades stems in on a run ≥ lead (stays in while > the ramp), and status
  "ready" means heard. A running job whose split ends < lead past the playhead
  is dropped between nets. Measured on the Lenovo M10: grid = 6–14 s of original
  after a seek plus a vocal blip at the next boundary; now one job (~5–6 s).
- STFT outside the model (periodic Hann 4096/1024, front pad 3072); soft ratio
  masks over all 4 nets; "average" band extension above bin 1024 (~11 kHz).

### Android
- `RoomDSPEngine` owns a `StemTap`; `process()` calls it before the EQ.
- Patched just_audio wraps the sink in `StemAwareAudioSink` (reports
  `setOutputStreamOffsetUs` = stream change, `handleBuffer` media time) and
  publishes current/next item URIs → `RoomEffectsProcessor` (`StemSinkListener`).
  Media3 here is 1.4.1 — processors get no position info natively.
- Track guess: flush → app's current item; stream change (or stream change then
  flush = sink reconfig at a gapless boundary) → next. A wrong guess fails
  alignment twice → tap tries the other candidate. Alignment window doubles per
  miss up to ±3 s (VBR MP3 seek tables).
- `StemEngineBridge.java` = control surface + track registration (content://
  → fd via ContentResolver). Decoder: NDK MediaExtractor/MediaCodec (reads
  YouTube's fragmented `ftypdash` m4a fine).

### Streams (YouTube Music)
- The engine can't read ahead of a stream, so an http(s) key is
  `unavailable/stream` until `provideSource(key, file)` (channel
  `stemsProvideStream(url, path)`). The key is the exact URI the player got
  (`useProxyForRequestHeaders: false` → the googlevideo URL on both platforms).
- `StemsController` reacts to that status for the playing track (`trackKey`),
  else prefetches the queued one (`nextKey`, Android only — iOS taps have no
  next), one fetch at a time; the tab shows "Preparing…" with the download as
  the first 40% of the bar; a failed fetch reads `fetch`.
- `StemsStreamCache`: googlevideo throttles a plain GET to ~31 KB/s (2× itag 140
  bitrate, 90 s a song) but serves **256 KB range requests** at full speed —
  3 connections, a range slower than 4 s is dropped and re-asked (1 in a few
  dozen stalls; 128 KB ranges stall far more). ~3 s per song on a Mac, ~8 s on
  the tablet's Wi-Fi. Same URL + headers as the player → same bytes. Keeps the
  4 newest copies in `<tmp>/stems_streams`.
- ONNX Runtime 1.31.0 AAR (no prefab) — Gradle `extractOnnxRuntime` copies
  headers + libs to `build/app/onnxruntime` for CMake (`-DORT_DIR`). 16 KB aligned.
  ⚠️ adds ~34 MB uncompressed .so per ABI — a reduced-operator ORT build is a TODO.

### iOS
- All taps share ONE RoomDSPEngine, so StemTap lives per MTAudioProcessingTap
  (`HypeAudioTap.m`, keyed by the item's asset URL, position = `timeRangeOut`).
- `dsp_stems_*` / `dsp_stem_tap_*` in dsp_bridge (keep the two headers identical).
- onnxruntime-c 1.30.0 pod (needs iOS 15.1 → Podfile/Runner bumped). HypeDSP is
  now `static_framework` (CocoaPods forbids dynamic→static deps).
- AVAssetReader decoder (`src/stems_ios/av_pcm_source.mm`); CPU-only inference
  (GPU is forbidden in background; ANE needs an entitlement on iOS 27).
  ⚠️ Unverified on a device: AVAssetReader on fragmented (`ftypdash`) m4a — the
  YouTube downloads and stream copies.

## Tests
`ORT_DIR=<onnxruntime-osx-arm64-1.31.0> native_tests/stems/run.sh` — FFT/STFT
exactness, resampler, alignment, store, full engine path (44.1 and 48 kHz),
gapless/seek track logic, wrong-track recovery. With `STEMS_MODEL_DIR` +
`STEMS_REF_DIR` (`reference.py` output) it checks the C++ separation against
the model card's Python pipeline: 87.9 dB (vocals) / 85.3 dB (drums) SNR.
Mac benchmark: 0.063 RTF (744 ms per 11.8 s split).

## Device results (Lenovo Tab M10 TB328XU, Android 12, debug build, Oct 11)
Benchmark RTF 0.365 (4.3 s per split). Output recorded with scrcpy
(`--no-video --audio-codec=raw`, remote submix) and fitted per STFT bin against
the Mac separation of the same file: local MP3 karaoke vocals −60 dB, drums-only
vocals −62 / instruments −44 dB, reset = unity; YouTube download and stream
karaoke vocals ~30–41 dB under the other stems (Sound Effects chain on/quiet
capture limit the fit). While separating: ~300% CPU (ORT, 4 threads) for ~5 s of
every 11.8 s split over a 45–75% debug-build baseline (~125% average); ~650 MB
RSS in the debug build. Idle/paused: 0%.
