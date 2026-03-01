# Stem Separation Feature

## Architecture
- Pre-process model: user taps "Separate Stems" → background service decodes + separates → 4 WAV files cached → instant playback via mixer
- StemMixer replaces ExoPlayer audio in C++ DSP pipeline when stem mode active
- ExoPlayer still handles timeline/seek/play-pause, audio content comes from stems

## Signal Chain (Stem Mode)
```
[StemMixer (4 WAVs → per-stem vol/mute → stereo mix)]
  → [Preamp+AutoGain] → [Speaker EQ] → [Graphic EQ] → [Parametric EQ]
  → [Tone Controls] → [MBC] → [Stereo Expander] → [Crossfeed] → [Reverb]
  → [Output Limiter]
```

## Files Created
- `android/app/src/main/cpp/stem_mixer.h` — 4-track WAV mixer, mmap I/O, atomic controls
- `android/app/src/main/kotlin/x/a/zix/StemSeparationService.java` — Foreground service, MediaCodec decode, WAV writer
- `lib/models/stem_model.dart` — Stem enum, StemState, StemCache (md5 hash dirs)
- `lib/controllers/stem_controller.dart` — ChangeNotifier, presets (karaoke/acapella/instrumental)
- `lib/pages/stem_mixer_view.dart` — 4-channel mixer console UI with vertical faders
- `lib/pages/stem_processing_view.dart` — Separation progress bottom sheet
- `lib/player/widgets/stem_button.dart` — Player action bar button with badge

## Files Modified
- `room_dsp_engine.h/cpp` — Added StemMixer member, stem mode replaces audio at top of process()
- `jni_bridge.cpp` — Added 10 stem JNI functions (load/unload/volume/mute/solo/seek/etc.)
- `RoomEffectsProcessor.java` — Cached stem state + broadcast methods + native declarations
- `MainActivity.java` — MethodChannel cases for stem ops + EventChannel for progress
- `Channel.dart` — All stem methods + stemProgressStream EventChannel
- `AppController.dart` — StemController instance, stem check on song change
- `Global/index.dart` — StemButton added to player action bar
- `AndroidManifest.xml` — StemSeparationService registered

## Key Patterns
- StemMixer uses mmap for low memory footprint (only reads pages as needed)
- WAV format: float32 stereo, standard chunk-walking parser (handles extended headers)
- Solo logic: if any stem soloed, only soloed stems play
- Stem cache: `temp/stems/{md5(songPath)}/` with 4 WAV files
- StemSeparationService: EventChannel `eq_app/stem_progress` for progress updates
- StemController presets: applyKaraoke (mute vocals), applyAcapella (solo vocals), applyInstrumental (mute vocals)

## Separation Algorithm (Current — Frequency + M/S)
- `stem_separator.h`: Butterworth crossovers + Mid/Side spatial decomposition
- Bass: 4th-order zero-phase LPF at 250Hz on full stereo (very clean isolation)
- Vocals: center-channel (Mid signal) bandpassed 250-8000Hz (decent karaoke quality)
- Other: side-channel (panned instruments) + high-frequency center/side content
- Drums: residual (original - bass - vocals - other)
- Zero-phase filtering via forward-backward passes (no phase distortion)
- Quality: ~3-5 dB SDR vocals, excellent bass isolation
- JNI: `StemSeparationService.nativeSeparateStems()` → `StemSeparator::separate()`
- `separateCurrentSong()` clears old cache before re-processing

## TODO (Phase 2 — Demucs ML for Better Quality)
- Would upgrade vocals SDR from ~3-5 dB to ~9 dB
- Requires demucs.cpp + Eigen3 + ggml model (~80MB)
- Model download UI with progress

## Stem Colors
- Vocals: #9C27B0 (purple)
- Drums: #FF9800 (orange)
- Bass: #4CAF50 (green)
- Other: #2196F3 (blue)
