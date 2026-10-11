# Live Stem Separation (Oct 2026 rewrite)

Vocals / Drums / Instruments levels while a song plays, from the Equalizer's
**Stems** tab. Replaces the March 2026 "tap Separate, wait, 4 WAVs" feature
(StemSeparationService, mmap StemMixer, DSP M/S splitter — all deleted).

## Decisions (user, Oct 10–11 2026)
- Model: **Spleeter 4-stem** (Deezer; weights MIT per the JOSS paper, trained on
  Deezer's own catalogue — NOT MUSDB). Demucs excluded: its author says the
  weights are "provided only for scientific purposes".
- **Local files only.** Streams (http/https) → `unavailable/stream`; files under
  the YouTube download folder → `unavailable/youtube` (YouTube Developer
  Policies III.I.7: must not "separate, isolate, or modify the audio").
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
  → fd via ContentResolver). Decoder: NDK MediaExtractor/MediaCodec.
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

## Tests
`ORT_DIR=<onnxruntime-osx-arm64-1.31.0> native_tests/stems/run.sh` — FFT/STFT
exactness, resampler, alignment, store, full engine path (44.1 and 48 kHz),
gapless/seek track logic, wrong-track recovery. With `STEMS_MODEL_DIR` +
`STEMS_REF_DIR` (`reference.py` output) it checks the C++ separation against
the model card's Python pipeline: 87.9 dB (vocals) / 85.3 dB (drums) SNR.
Mac benchmark: 0.063 RTF (744 ms per 11.8 s split).
