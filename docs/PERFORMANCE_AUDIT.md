# Hype Muzik — Mobile Performance Architecture Audit

**Date:** 2026-07-01
**Reviewer lens:** Senior mobile engineer (12 yrs — Android platform, Flutter render pipeline, NDK audio)
**Target:** `/Users/bruno/me/COTE/hype` — Flutter audio player (Android + iOS), 41K LOC Dart over custom C++ DSP + projectM/OpenGL + foreground audio service
**Objective:** Identify modules causing non-responsive UI, glitchy rendering, CPU stalls, and phone overheating
**Method:** Four parallel read-only audits (render path · state/rebuilds · native DSP/GL · timers/lifecycle/leaks). Every finding verified against source with `file:line`. No files were modified.

---

## 1. Executive Verdict

The **steady-state playback architecture is sound**. Playback position and FFT/spectrum data are deliberately kept **out** of the god-object `AppController` `ChangeNotifier` and delivered through scoped leaf `StreamBuilder`s and direct EventChannel callbacks. So, contrary to the usual Flutter anti-pattern, the app does **not** rebuild its whole widget tree at 60fps during normal playback. This is the single most important thing done right, and it means the problems are concentrated, not diffuse.

The heat, jank, and "gets hot and sluggish the longer I use it" behavior trace to **three architectural gaps** plus a **compounding resource leak** — a small, fixable set of high-leverage issues. Two of the four audits independently identified the same #1 root cause (no lifecycle gating), which raises confidence that it is real and dominant.

**If only three things are fixed: F1, F2, F3.** Together they eliminate the dominant background/overheat drain and the compounding leak for the least code.

---

## 2. The Three Architectural Root Causes

| # | Root cause | Mechanism | Symptoms produced |
|---|-----------|-----------|-------------------|
| **A** | **No app-lifecycle gating anywhere** | `grep WidgetsBindingObserver \| didChangeAppLifecycleState \| AppLifecycleState` across `lib/` = **0 matches**; `MainActivity.java` has no `onPause`/`onStop`. | projectM GL thread + native FFT/PCM tap + 60fps visualizer loop **all keep running with the screen off / app backgrounded** → overheating + battery drain in pocket. |
| **B** | **Visualizer render loop is unconditional** | `wave-visualizer.dart` drives a 60fps `AnimationController..repeat()`; time-driven painters return `shouldRepaint => true`; the `if (audioData.isEmpty) return` guard **never fires** because the band buffer is pre-filled `List.filled(256, 0.0)`. | A **paused, silent track still pays full render cost every frame**; heaviest presets do 6k–16k `sin`/`cos` + `pow`/frame → CPU/GPU heat + jank while any visualizer is visible. |
| **C** | **Work on the wrong thread / no bypass** | Disk writes + JSON encode on the UI isolate during gestures; heap allocation inside the real-time audio callback; DSP chain with no denormal (FTZ) protection and no true bypass. | Main-thread stalls → non-responsive UI (EQ drags, track changes). Audio-thread allocation/denormals → xruns/glitchy audio. Always-on DSP → baseline heat for zero benefit. |

Plus one **compounding leak (F3)** that explains the "worse over time" complaint specifically: the visualizer leaks a native FFT subscription on every teardown, and the player subtree is keyed on `songId`, so a new orphan accumulates on **every track change**, each still allocating ~60×/sec forever.

---

## 3. Symptom → Module Map

| User-reported symptom | Primary modules responsible |
|-----------------------|-----------------------------|
| **UI non-responsive / freezes** | EQ/DSP slider drag storm (F4), play-count JSON write on track change (F11), synchronous `existsSync()` sweeps at startup/cloud-open (F9) |
| **Glitchy / stutter / dropped frames** | Visualizer subscription leak compounding per track (F3), per-frame GC churn in painters + FFT path (F6), audio-thread heap allocation + denormals (F7, F8) |
| **CPU stall / a core pegged** | Unconditional 60fps visualizer loop with heavy painters (F2), native DSP with no bypass (F10), redundant per-sample/per-frame transcendentals (F14) |
| **Overheating / battery drain (screen off)** | **No lifecycle gating** — projectM GL + FFT tap + visualizer loop never pause (F1); indefinite wake lock (F12) |

---

## 4. Findings — P0 (Fix First)

### F1 — Nothing pauses on background; GL + FFT + visualizer run with screen off  `[CRITICAL — corroborated by 2 independent audits]`
**Files:** `lib/main.dart` (no observer), `ProjectMRenderer.java:415-441` (render loop), `VisualizerTapProcessor.java:131-157` (PCM tap), `wave-visualizer.dart:57-60` (`..repeat()`), `MainActivity.java` (no `onPause`), `lib/pages/visual_ui.dart:254` (start in `initState`, stop only on `dispose`).

**Root cause.** There is no lifecycle handling in Dart *or* the Activity. Lock the phone with the visualizer route mounted and music playing (playback continues via the foreground audio service), and: the `projectm-gl` `HandlerThread` keeps calling `projectm_opengl_render_frame` + `eglSwapBuffers` at ~30fps into an off-screen `SurfaceTexture`; `VisualizerTapProcessor` keeps allocating a `float[]` per audio buffer; the Dart FFT listener keeps deserializing and allocating every frame. Flutter suspends *rendering* when paused, but platform-channel event handlers and native threads keep running.

**Symptom.** Overheating and battery drain during screen-off listening — invisible because the UI isn't shown. This is the single biggest heat culprit.

**Fix.** Add one `WidgetsBindingObserver` (or `AppLifecycleListener`) at app root. On `paused`/`hidden`: `ProjectMController.stop()`, `AudioVisualizer.deactivate()`, stop the visualizer ticker, and gate the native FFT tap. On `resumed`: re-activate. Optionally also stop the GL loop from `MainActivity.onStop`. **Highest ROI change in the codebase.**

---

### F2 — Visualizer render loop is always-on and pays full cost on silence  `[CRITICAL]`
**Files:** `wave-visualizer.dart:41` (`List.filled(256,0.0)` defeats the empty-guard), `:57-60` (`..repeat()` 60fps driver), `:219` (`List<double>.from(_freqBands)` copy/frame). Heaviest painters (all hosted by this driver, all `shouldRepaint => true`):

| Painter | `file:line` | Dominant per-frame cost |
|---|---|---|
| FractalFlame | `3d_visualizers_tier3.dart:310` | 3000-iter IFS loop, **~6,000 `sin`**, ~3,000 `Offset` allocs, `new Random`/frame |
| MorphingOrb | `3d_visualizers_tier2.dart:276` | **~16,300 trig**, 33 `Path`, ~34 `Paint`, radial `ui.Gradient` built inside `paint()` |
| Sphere | `sphere_visualizer.dart:4` | 1,452-iter: ~5,800 trig + **~1,450 `pow`** + `sublist().reduce()` allocs + `MaskFilter.blur` |
| MeshSphere | `3d_visualizers_tier2.dart:170` | ~6,300 trig + **468-elem `sort`/frame** + 468 `drawLine` |
| AudioTerrain | `3d_visualizers_tier2.dart:64` | 1025-pt grid: ~4,100 trig + ~1,025 record allocs + 39 `Path` |
| MetaballBlob | `3d_visualizers_tier3.dart:31` | 841×4 field + 1,568-cell marching squares + **~1,568 closure allocs/frame** + 4 shaders |
| ReactiveGeometry | `3d_visualizers_tier2.dart:399` | **~30 `MaskFilter.blur` glow draws** + ~60 `drawPath` (GPU-bound) |
| Waterfall | `3d_visualizers_tier2.dart:519` | ~1,000 `drawRect` + 1 blur |
| MilkdropWarp | `3d_visualizers_tier3.dart:179` | ~950 trig + 32 `Path` + per-line `HSLColor.fromColor` |
| Heartbeat | `sine_wave_visualizer.dart:4` | ~800 `sin` + ~400 `pow`; full path drawn **5×** for glow |
| Spectrum | `spectrum-visualiser.dart:6` | 64 `sin` + 64 `drawRRect` (cheapest time-driven) |

**Root cause.** The controller repeats at 60fps whether or not audio is playing or the visualizer is even the visible tab, and the "nothing to draw" early-out is dead code because the buffer is never empty. So every listed painter runs its full fixed-size compute on a paused, silent, or backgrounded track.

**Symptom.** Sustained CPU/GPU heat + frame drops whenever a visualizer is on screen; wasted cycles when paused/off-screen.

**Fix.** Gate the driver on `isPlaying && isVisualizerVisible`; stop the controller when paused/off-screen. Make the `isEmpty` guard reachable (don't pre-fill with a non-empty fixed buffer). Hoist per-frame `Random`/`Paint`/`Gradient` to fields. **Model the discipline on the legacy `Bar`/`Line`/`CircularBar`/`MultiWave` painters, which already use reference-comparing `shouldRepaint` and are cheap.**

---

### F3 — `VisualizerWidget` leaks its EventChannel subs; compounded per-track by a `songId`-keyed subtree  `[CRITICAL]`
**Files:** `VisualizerWidget.dart:52-59` (dispose), `VisualizerWidget.dart:29` (activate), `AudioVisualizer.dart:90,113` (subscriptions), `AudioVisualizer.dart:137-153` (deactivate — never called), `player_ui.dart:149-171` (keyed subtree), `Body.dart:74` (a second, unkeyed instance with the same dispose bug).

**Root cause.** `initState` creates a new `AudioVisualizer` and calls `activate()`, which does `_fftBandsChannel.receiveBroadcastStream().listen(...)` and `_waveformChannel...listen(...)`. But `dispose()` only calls `_visualizer?.removeListener(...)` — it never calls `deactivate()` (which cancels `_bandsSub`/`_waveSub`) or `dispose()`. The live subscription's closure retains the object, so it is never GC'd and its native FFT sink stays registered. Then it is *multiplied per track*: `player_ui.dart:149-155` sets `key = Object.hash(controller.songId, identityHashCode(player))`, so every `songId` change tears down the whole subtree (leaking that instance's subs) and inflates a fresh one. Over a 40-song session, ~40 orphaned native FFT subscriptions accumulate.

**Symptom.** Gradual slowdown, rising memory, and rising CPU the longer a session runs — the app gets warmer and less responsive the more tracks have played, and never recovers until process death. Each orphan still runs `Float32List.fromList(...)` + `List<int>.generate(128,…)` ~60×/sec against an empty callback set.

**Fix.** In `VisualizerWidget.dispose()` call `_visualizer?.dispose()` (or `deactivate()`) and null the field. Give the persistent visualizer a **stable key** (or hoist it out of the `songId`-keyed `StreamBuilder`) so it isn't rebuilt every track. Early-return the FFT listener when all callback sets are empty (see F6).

---

### F4 — EQ/DSP slider drag = 2 disk writes + JSON encode + triple-nested `watch` + double full-screen blur, per pointer delta  `[CRITICAL]`
**Files:** `graphic_eq_view.dart:28` (`context.watch`), `:333-334`, `:357-358` (`onChanged`), `AppController.dart:208-218` (`setDisplayBandGain` → channel + `_persistGraphicGains` + notify), `:364-372` (`activePresetName` setter → second `setString` + platform call + second notify). Blur hosts: `Equalizer.dart:72` and `Body.dart:15` (`context.watch` + `BackdropFilter` sigma up to 200).

**Root cause.** `_BandSlider.onChanged` fires on every pointer move during a drag (~60–90 Hz). Each delta triggers **two** notifying mutations: `setDisplayBandGain(i, value)` (32-double MethodChannel payload + `json.encode(_graphicBandGains)` + `_prefs.setString(...)` disk write + `notifyListeners()`) **and** `activePresetName='Custom'` (a second `setString` + an `updateEqModePreset` platform call + a second `notifyListeners()`). The host page reads `context.watch<AppController>()`, nested inside `Equalizer`'s `watch`, inside `Body`'s `Consumer` — three full-controller subscriptions wrapping two `BackdropFilter` blurs.

**Symptom.** Choppy/laggy EQ sliders, dropped frames while dragging, device heat, and occasional main-thread stalls from synchronous JSON encode + disk I/O at 60 Hz.

**Fix.** Persist on `onChangeEnd` (or throttle to ~5 Hz), not per delta. Throttle `notifyListeners` to ~15–20 Hz during continuous gestures, or split band-gain into a tiny `ValueNotifier` consumed by a `ValueListenableBuilder`/`Selector` around just the sliders + curve. Set `activePresetName='Custom'` once at drag-start. **The same setter pattern (`prefs.setX` + `Channel.x` + `notifyListeners`) applies to preamp (`:231-236`), reverb/room (`:1375-1420`), tone (`:255-295`), crossfeed/stereo (`:1444-1478`), and `dvcGain` (`:590-595`) — fix generically.**

---

## 5. Findings — P1 (High Impact)

### F5 — `Body` background wraps a double full-screen `BackdropFilter` (sigma 200) in a whole-controller `Consumer`  `[HIGH]`
**Files:** `widgets/Body.dart:15-104` (blur at `:33-37`, second blur at `:56-57` sigma 200); nested via `Home.dart:242` and `Equalizer.dart:73`.
**Root cause.** `Body` is a single `Consumer<AppController>` whose builder constructs `ArtworkWidget` + two `BackdropFilter`s + the child screen. Any `notifyListeners()` (play-count, lyrics flag, shuffle, EQ change) re-runs this builder and reconfigures the blur layers over the full viewport. `BackdropFilter` is one of the most expensive raster-thread ops; nested `Body` paths can stack up to four.
**Symptom.** Frame drops on track change and on any settings toggle while Home/EQ is visible; sustained GPU load from the sigma-200 blur.
**Fix.** Hoist artwork + blur into a `RepaintBoundary`-wrapped subtree passed via the `child:` escape hatch (not rebuilt by the Consumer); drive only `blur`/`songId` via a narrow `Selector`. Reconsider sigma 200 (downsample the source and blur less).

### F6 — Per-frame heap churn (Dart painters + FFT path)  `[HIGH]`
**Files:** FractalFlame `new Random`/frame + ~3,000 `Offset`s (`tier3:366,391`); Metaball 1,568 closures/frame (`tier3:134-137`); Sphere/Heartbeat `sublist().reduce()` copies (`sphere_visualizer.dart:28-41`, `sine_wave_visualizer.dart:26-35`); Terrain 1,025-record grid (`tier2:90`); host `List.from(_freqBands)`/frame (`wave-visualizer.dart:219`); `Float32List.fromList(...)` + 128-elem `List.generate` per FFT frame (`AudioVisualizer.dart:90-112`).
**Root cause.** Allocations inside `paint()`/stream callbacks at 60fps create young-gen GC pressure. The FFT `legacyFft` generation runs even when `_fftCallbacks` is empty (true for every leaked instance from F3).
**Symptom.** Periodic frame drops / stutter from GC pauses; scales with the number of leaked instances.
**Fix.** Preallocate and reuse buffers; hoist `Random`/`Paint`/`Gradient` to fields; skip `legacyFft` when no consumer; drive painters via a `repaint:` `Listenable` instead of widget rebuilds.

### F7 — Heap allocation inside the real-time audio callback  `[HIGH]`
**Files:** `multiband_compressor.h:157-167` (`heapBuf = new float[numFrames*2*11]` per buffer; `STACK_LIMIT` only 512 frames but AAC decode buffers are 1024, so MBC-enabled playback heap-allocates ~88KB every callback), `VisualizerTapProcessor.java:131-157` (`new float[]` per buffer + per-sample `getShort()`).
**Root cause.** Allocation on the audio thread causes allocator contention / priority inversion.
**Symptom.** Periodic dropouts / xruns when the multiband compressor or a visualizer is active; worst during crossfade (two tap instances).
**Fix.** Allocate band scratch once in `init()`/`reinit()` sized to Media3's max block; reuse a double-buffered `float[]` in the tap; bulk-convert 16-bit via `asShortBuffer().get(...)`.

### F8 — No flush-to-zero (FTZ) denormal protection on the main DSP chain  `[HIGH]`
**Files:** FTZ set only in `fdn_reverb.cpp:137-145` (and restored at `:200-204`); the biquad EQs, tone shelves, 10-band MBC, crossfeed, and limiter in `room_dsp_engine.cpp:124-234` run with FTZ off. Biquad states at `biquad.h:228-229`.
**Root cause.** DF2T biquad states and the compressor's dB-domain envelope decay into denormals during fade-outs, quiet passages, and silent-but-processing buffers → up to ~100× scalar-FPU slowdown. The reverb's own manual FTZ proves `-ffast-math` doesn't enable runtime FTZ globally on ARM.
**Symptom.** Sudden CPU spikes / xruns / crackle on fade-outs and quiet sections; intermittent, worse on older SoCs.
**Fix.** Set the ARM FPCR FTZ bit (bit 24, aarch64) **once** at the top of `RoomDSPEngine::process()` for the whole chain; drop the reverb's local save/restore.

### F9 — Synchronous `existsSync()` sweeps over the whole cloud file list on the UI isolate  `[MEDIUM–HIGH]`
**Files:** `cloud_metadata_service.dart:56-64, 68-74` (two full synchronous passes, per-file `File(marker).existsSync()` + some `deleteSync()`), triggered at startup (`AppController.dart:1852`) and every Cloud-view open (`cloud_view.dart:104,115`).
**Root cause.** Thousands of blocking `stat()` syscalls on the UI isolate before any async work, for large cloud libraries.
**Symptom.** Frame drops / brief non-responsiveness at launch and on entering the cloud library, proportional to library size.
**Fix.** Replace per-file `.done` markers with a single persisted JSON set of completed `fileId`s (one read vs N stats), or move the scan to a `compute` isolate.

---

## 6. Findings — P2 (Real, Lower Leverage)

- **F10 — No true DSP bypass; limiter force-enabled by default.**  `[MEDIUM]`  `RoomEffectsProcessor.java:82` overrides the C++ `enabled_=false` (`limiter.h:125`), so `doLimiter` is always true, the early-out at `room_dsp_engine.cpp:147` never fires, and every buffer runs deinterleave → per-sample `log10`+`pow` (`limiter.h:62-64`) → reinterleave even with all effects off and no boost (~96k `log10`+`pow`/s at 48kHz). *Fix:* engage the limiter only when upstream boost is active; use an `exp2`-based approximation.

- **F11 — Track change fires a 3–4× notify cascade + synchronous play-count write.**  `[MEDIUM]`  `AppController.dart:1674-1705` (`songId` → lyrics-load start/end → play-count) rebuilds artwork+blur+song-lists across separate frames; `:1193-1200` does `json.encode(_playCounts)` + `setString` on the UI isolate at the exact moment of the transition, growing unbounded. *Fix:* batch to a single notify; debounce/offload the write (`compute` or write on pause/background).

- **F12 — `GlobalEqService` holds a `PARTIAL_WAKE_LOCK` indefinitely.**  `[MEDIUM]`  `GlobalEqService.java:74-79` acquires, `:119-122` releases only in `onDestroy`, `:128-131` `onTaskRemoved` keeps running — prevents CPU deep-sleep once global EQ was ever enabled, surviving task removal. *Fix:* drop the wake lock or tie it to actual playback (`AudioPlaybackCallback` already registered at `:271-277`).

- **F13 — Zero `Selector`/`buildWhen` in the entire codebase.**  `[MEDIUM]`  A 1918-line god-object `ChangeNotifier` (`AppController.dart`) with ~141 `notifyListeners()` sites is consumed by 31 `Consumer<AppController>` + 10 `context.watch<AppController>()`, most wrapping whole `Scaffold`/page bodies. Every consumer rebuilds on every unrelated mutation. *Fix:* split into `EqState`/`PlaybackState`/`LibraryState`/`VisualizerSettings`, or adopt `Selector`/`context.select` on hot pages.

- **F14 — Redundant per-frame/per-sample transcendentals in native viz/DSP.**  `[MEDIUM]`  FFT recomputes ~2×1023 `cos`/`sin` per frame for a fixed-size (2048) transform (`fft_visualizer.h:221-228` → precompute a twiddle table); MBC does ~20 `log`/`exp` per sample across 10 bands with no per-band unity skip and 36 biquad passes (`compressor.h:108-114`, `multiband_compressor.h:190-210`). *Fix:* twiddle table; skip bands at unity; `log2`/`exp2` approximations.

- **F15 — Double `setState`/frame in visualizer; lyrics karaoke `setState` ~30×/s.**  `[MEDIUM]`  `VisualizerWidget.dart:36-50` calls `setState` separately for FFT and waveform (two streams → up to 2 full rebuilds/frame); `lyrics_view.dart:61-109` `setState`s the whole `LyricsView` on line-progress moves >0.01. *Fix:* coalesce into one `setState`/frame; drive via `ValueNotifier` + `ValueListenableBuilder` scoped to the active line.

- **F16 — Two PCM-capture paths can be simultaneously active.**  `[LOW]`  Legacy Android `Visualizer` (`AudioVisualizer.java`, activated via `MainActivity.java:155-181`) coexists with the custom in-pipeline tap (`VisualizerTapProcessor`). *Fix:* ensure exactly one capture path per visualizer style; retire the legacy path if the FFT tap supersedes it.

- **F17 — `loader.dart` splash runs 11 `..repeat()` controllers + a 50ms `Timer.periodic` `setState` at 60fps.**  `[LOW]`  `loader.dart:69` (ripple `addListener → setState` rebuilds whole subtree), `:108` (50ms timer), `:502` (painter). Self-terminates on navigation but wasteful during launch. *Fix:* use `AnimatedBuilder`; gate `shouldRepaint`.

---

## 7. Verified Clean — Do Not "Fix" These

- **Position & FFT bypass `notifyListeners()`** — the position listener (`AppController.dart:884-897`) never notifies; the seek bar uses a leaf `StreamBuilder<PositionData>` (`player_ui.dart:674`); FFT is a callback fan-out (`AudioVisualizer.dart:87-135`). No 60fps tree storm in steady playback. *Add a code-review guard against ever routing position/FFT through `notifyListeners`.*
- **projectM GL loop is frame-rate-capped** (~30fps, `ProjectMRenderer.java:437-440`), render target a modest 512×512 / mesh 48×36 — the problem is *when* it runs (F1), not *how fast*.
- **Crossfade stream-rebind cancels-before-reassign** — `AppController.dart:817,853,885` and `HypeAudioHandler._bindPlaybackState` (`AudioHandler.dart:71-76`). No subscription leak there. The inactive crossfade player is paused, so its DSP doesn't run outside the crossfade window.
- **Biquad coefficients** are computed at control-rate in double precision (not per-sample); DSP parameter updates are lock-free atomics.
- **Stem separation & fingerprinting** run on background worker threads with bounded MediaCodec drains (`FingerprintEngine.java:144` is bounded backoff, not busy-spin).
- **Cloud metadata extraction** is concurrency-bounded to 3 with run-ID cancellation on disconnect (`cloud_metadata_service.dart:23,32-39`).
- **`remote_link.dart:108`** correctly offloads heavy work via `Isolate.run`.
- **Legacy `Bar`/`Line`/`CircularBar`/`MultiWave` painters** use reference-comparing `shouldRepaint` — the correct pattern to replicate for the tier-2/tier-3 and Spectrum painters.

---

## 8. Remediation Roadmap (Sequenced by ROI)

**Sprint 1 — Kill the sustained heat (highest felt impact, low effort):**
1. **F1** — Add the app-lifecycle observer → pause projectM + FFT tap + visualizer loop on background.
2. **F2** — Gate the visualizer render loop on `playing && visible`; fix the never-firing empty-guard.
3. **F3** — Fix `VisualizerWidget.dispose()` + stop re-keying the player on `songId`.

**Sprint 2 — Kill the interaction jank:**
4. **F4** — Debounce EQ/DSP persistence + throttle notify during drags; generalize to all DSP setters.
5. **F5 / F11** — Hoist artwork+blur out of the `Body`/`PlayerBody` Consumers via `child:` + `RepaintBoundary`; batch/offload the play-count write.
6. **F9** — Move the cloud marker scan off the UI isolate.

**Sprint 3 — Native audio hygiene:**
7. **F8** — FTZ once at top of `process()`.
8. **F7** — Preallocate MBC/tap buffers off the RT path.
9. **F10** — Real DSP bypass + limiter gating.
10. **F14** — FFT twiddle table + MBC unity skip.

**Sprint 4 — Structural:**
11. **F13** — Split `AppController` / introduce `Selector`.
12. **F15** — Coalesce visualizer/lyrics `setState` via `ValueNotifier`.
13. **F12** — Wake-lock scoping.

---

## 9. Appendix — Key File References

| Concern | Location |
|---|---|
| Lifecycle gap (Dart) | `lib/main.dart`, `lib/pages/visual_ui.dart:254`, `lib/Helpers/ProjectMController.dart:42` |
| Lifecycle gap (native) | `MainActivity.java` (no `onPause`), `ProjectMRenderer.java:415` |
| Visualizer driver + empty-guard | `lib/Visualizers/wave-visualizer.dart:41,57,219` |
| Heaviest painters | `3d_visualizers_tier3.dart:310`, `3d_visualizers_tier2.dart:276`, `sphere_visualizer.dart:4` |
| Visualizer sub leak | `lib/Helpers/VisualizerWidget.dart:52-59,29`, `lib/Helpers/AudioVisualizer.dart:90,113,137-153` |
| Player keyed on songId | `lib/player/player_ui.dart:149-171` |
| EQ drag storm | `lib/pages/graphic_eq_view.dart:28,333`, `lib/controllers/app_controller.dart:208-218,364-372` |
| Double blur Consumer | `lib/widgets/Body.dart:15-104` |
| RT heap alloc (MBC / tap) | `multiband_compressor.h:157-167`, `VisualizerTapProcessor.java:131-157` |
| FTZ (only in reverb) | `fdn_reverb.cpp:137`; chain in `room_dsp_engine.cpp:124-234` |
| Per-sample log/exp | `compressor.h:108-114`, `limiter.h:62-64` |
| FFT twiddle recompute | `fft_visualizer.h:221-228` |
| Limiter forced-on | `RoomEffectsProcessor.java:82` |
| Indefinite wake lock | `GlobalEqService.java:74-79` |
| Play-count UI-isolate write | `lib/controllers/app_controller.dart:1193-1200` |
| Cloud existsSync sweep | `lib/services/cloud_metadata_service.dart:56-74` |

---

*Audit produced by four parallel read-only reviews; every cited line was read directly. No source files were modified.*
