/// Live stems: the state behind the Stems tab, and the engine it drives.
///
/// # Who knows what
///
/// The native engine separates vocals and drums ahead of the playhead and
/// follows the player by itself — it decides which track is playing, whether
/// it can be read, and when it is ready. This controller owns everything the
/// person touches: the model download, the one-time speed test, the faders and
/// pads, and whether the engine should be working at all.
///
/// # Armed
///
/// The engine is *armed* while the Stems tab is on screen (so a song is
/// already being prepared by the time someone reaches for a fader) or while
/// the mix is audibly changed. It is only told so once the model is loaded and
/// the phone has passed the speed test — before that there is nothing for it
/// to run. A model nobody has wanted for [unloadAfter] is unloaded to give its
/// memory back.
///
/// # Streams
///
/// The engine separates from its own decode of the song, ahead of the
/// playhead, so a stream gives it nothing to read ahead from: it reports the
/// track unavailable with reason `stream`. For a YouTube Music stream this
/// controller then fetches the same file the player streams and hands the
/// engine the copy (see [StemsStreamCache]); meanwhile the tab reads as
/// preparing, with the download as the first part of the progress.
///
/// # Not remembered
///
/// Fader and pad positions carry from one song to the next while the app is
/// open, and start from the original at every launch. Someone who turned the
/// vocals off last night and opens the app to a silent singer would think the
/// app was broken. Only the speed test's verdict is persisted.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/Channel.dart';
import '../models/stems_engine_status.dart';
import '../models/stems_mix.dart';
import '../services/stems/stems_manifest.dart';
import '../services/stems/stems_model_store.dart';
import '../services/stems/stems_stream_cache.dart';
import '../services/ytmusic/yt_innertube.dart';

/// Fetches a local copy of the stream the player plays from `url` and
/// returns its path, or null for a stream this app can't fetch.
typedef StemsStreamFetcher =
    Future<String?> Function(
      String url, {
      void Function(double fraction)? onProgress,
      StemsCancelToken? cancel,
    });

/// Where the separation model is on this phone.
enum StemsModelPhase { checking, absent, downloading, verifying, ready, failed }

/// Whether this phone is fast enough, as far as anyone knows yet.
enum StemsDeviceSupport { unknown, benchmarking, supported, unsupported }

/// What the Stems tab shows — every combination of the states above,
/// collapsed into the one screen it means.
enum StemsStage {
  checking,
  needsDownload,
  downloading,
  verifying,
  downloadFailed,
  testingDevice,
  unsupported,
  startFailed,
  mixer,
}

class StemsController extends ChangeNotifier {
  StemsController({
    required this._prefs,
    StemsModelStore? store,
    this._fetchStream,
    this.unloadAfter = const Duration(minutes: 2),
    this.levelInterval = const Duration(milliseconds: 33),
    this.nativeTimeout = const Duration(seconds: 90),
  }) : _store = store ?? StemsModelStore();

  /// The app's wiring: the real model store, and YouTube Music streams fetched
  /// with the headers the player streams them with.
  factory StemsController.app(SharedPreferences prefs) {
    final cache = StemsStreamCache();
    return StemsController(
      prefs: prefs,
      fetchStream: (url, {onProgress, cancel}) async {
        if (!YtInnerTube.isStreamUrl(url)) return null;
        return cache.fetch(
          url,
          headers: YtInnerTube.audioPlaybackHeaders,
          onProgress: onProgress,
          cancel: cancel,
        );
      },
    );
  }

  final SharedPreferences _prefs;
  final StemsModelStore _store;
  final StemsStreamFetcher? _fetchStream;

  /// How long a loaded model may sit unwanted before it is unloaded.
  final Duration unloadAfter;

  /// Minimum spacing of level updates during a drag (~30 a second). The last
  /// value of a drag is always sent.
  final Duration levelInterval;

  /// How long a native load or speed test may take before it counts as failed.
  final Duration nativeTimeout;

  StemsModelManifest get manifest => _store.manifest;

  String get _benchmarkKey => 'stems.benchmark.${manifest.key}';

  // --- Model ----------------------------------------------------------------

  StemsModelPhase _modelPhase = StemsModelPhase.checking;
  int _receivedBytes = 0;
  String? _modelError;
  StemsCancelToken? _download;
  int _notifiedPermille = -1;

  // --- Device ---------------------------------------------------------------

  StemsDeviceSupport _support = StemsDeviceSupport.unknown;
  StemsBenchmark? _benchmark;

  // --- Engine ---------------------------------------------------------------

  bool _modelLoaded = false;
  bool _preparing = false;
  String? _engineError;
  bool _nativeArmed = false;
  bool _awaitingStatus = false;
  StemsEngineStatus _status = StemsEngineStatus.idle;
  StreamSubscription<Map<String, dynamic>>? _events;
  int _eventSeq = 0;
  Timer? _unloadTimer;

  // --- Mix ------------------------------------------------------------------

  StemsMix _mix = StemsMix.initial;
  final ValueNotifier<bool> _engaged = ValueNotifier(false);
  bool _tabVisible = false;
  List<double>? _lastSentLevels;
  Timer? _levelsTimer;
  bool _levelsPending = false;

  // --- Streams --------------------------------------------------------------

  /// The stream being fetched right now (the playing one, or the queued one
  /// once the playing one has its copy), its progress and how to stop it.
  String? _streamKey;
  double _streamProgress = 0;
  StemsCancelToken? _streamCancel;
  int _streamPermille = -1;

  /// Streams whose copy the engine has; ones whose fetch failed (not retried
  /// until stems are next switched on); ones this app can't fetch at all.
  final Set<String> _providedStreams = {};
  final Set<String> _failedStreams = {};
  final Set<String> _unfetchableStreams = {};

  // --- Lifecycle ------------------------------------------------------------

  bool _started = false;
  bool _disposed = false;

  // ===========================================================================
  // Reading
  // ===========================================================================

  StemsModelPhase get modelPhase => _modelPhase;

  int get downloadedBytes => _receivedBytes;

  int get totalBytes => manifest.totalBytes;

  double get downloadProgress =>
      totalBytes <= 0 ? 0 : (_receivedBytes / totalBytes).clamp(0.0, 1.0);

  /// Why the last download failed, in words fit for the user.
  String? get modelError => _modelError;

  /// Whether a cancel was asked for and the download is still winding down.
  bool get cancellingDownload => _download?.isCancelled ?? false;

  StemsDeviceSupport get deviceSupport => _support;

  /// The speed test's result, from this session or remembered.
  StemsBenchmark? get benchmark => _benchmark;

  /// Why the engine couldn't be started, in words fit for the user.
  String? get engineError => _engineError;

  bool get modelLoaded => _modelLoaded;

  /// The current mix: fader positions and pad states.
  StemsMix get mix => _mix;

  /// Whether the mix differs audibly from the original.
  bool get engaged => _mix.engaged;

  /// [engaged], for the "Stems on" dot on the player's EQ button — which
  /// shouldn't rebuild on every progress event the tab cares about.
  ValueListenable<bool> get engagedListenable => _engaged;

  bool get tabVisible => _tabVisible;

  /// Whether the engine *should* be working: the tab is on screen or the mix
  /// is changed.
  bool get armed => stemsArmed(tabVisible: _tabVisible, engaged: _mix.engaged);

  /// Whether the engine has actually been told to work — [armed], once the
  /// model is loaded and the phone is known to be fast enough.
  bool get nativeArmed => _nativeArmed;

  /// What the engine last reported. Between asking it to start and its first
  /// answer this reads as preparing, because that is what is happening: the
  /// original plays while the stems get ready. So does a stream whose copy is
  /// downloading: the download is the first [_streamShare] of the progress.
  StemsEngineStatus get status {
    if (armed &&
        stage == StemsStage.mixer &&
        (!_nativeArmed || _awaitingStatus)) {
      return StemsEngineStatus.starting;
    }
    final st = _status;
    final key = st.trackKey;
    if (key == null) return st;
    if (st.state == StemsEngineState.unavailable && st.reason == 'stream') {
      if (_failedStreams.contains(key)) {
        return StemsEngineStatus(
          state: StemsEngineState.unavailable,
          reason: 'fetch',
          trackKey: key,
          nextKey: st.nextKey,
        );
      }
      // Fetching, or about to (a copy just handed over has not been picked
      // up yet): the original plays meanwhile, as it does while preparing.
      if (key == _streamKey || _providedStreams.contains(key)) {
        return StemsEngineStatus(
          state: StemsEngineState.preparing,
          progress: key == _streamKey ? _streamProgress * _streamShare : _streamShare,
          trackKey: key,
          nextKey: st.nextKey,
        );
      }
    }
    if (st.state == StemsEngineState.preparing &&
        _providedStreams.contains(key)) {
      return StemsEngineStatus(
        state: StemsEngineState.preparing,
        progress: _streamShare + st.progress * (1 - _streamShare),
        aheadSeconds: st.aheadSeconds,
        trackKey: key,
        nextKey: st.nextKey,
      );
    }
    return st;
  }

  /// The download's part of a stream's progress bar; separating the first
  /// stretch is the rest.
  static const double _streamShare = 0.4;

  StemsStage get stage {
    if (_support == StemsDeviceSupport.unsupported) {
      return StemsStage.unsupported;
    }
    switch (_modelPhase) {
      case StemsModelPhase.checking:
        return StemsStage.checking;
      case StemsModelPhase.absent:
        return StemsStage.needsDownload;
      case StemsModelPhase.downloading:
        return StemsStage.downloading;
      case StemsModelPhase.verifying:
        return StemsStage.verifying;
      case StemsModelPhase.failed:
        return StemsStage.downloadFailed;
      case StemsModelPhase.ready:
        if (_engineError != null) return StemsStage.startFailed;
        if (_support == StemsDeviceSupport.supported) return StemsStage.mixer;
        return StemsStage.testingDevice;
    }
  }

  // ===========================================================================
  // Lifecycle
  // ===========================================================================

  /// Call once, at app start: recalls the speed-test verdict and looks for a
  /// downloaded model.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _restoreBenchmark();
    unawaited(_checkModel());
  }

  void _restoreBenchmark() {
    final raw = _prefs.getString(_benchmarkKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final result = StemsBenchmark.fromMap(decoded);
      _benchmark = result;
      _support = result.supported
          ? StemsDeviceSupport.supported
          : StemsDeviceSupport.unsupported;
    } catch (_) {
      unawaited(_prefs.remove(_benchmarkKey));
    }
  }

  Future<void> _checkModel() async {
    final ready = await _store.isReady();
    if (_disposed || _modelPhase != StemsModelPhase.checking) return;
    _modelPhase = ready ? StemsModelPhase.ready : StemsModelPhase.absent;
    _notify();
    if (ready) unawaited(_prepareEngine());
  }

  // ===========================================================================
  // Model download
  // ===========================================================================

  /// Downloads and verifies the model (about 79 MB), then — if the tab is
  /// open — loads it and runs the speed test.
  Future<void> downloadModel() async {
    if (_disposed || _download != null) return;
    if (_modelPhase != StemsModelPhase.absent &&
        _modelPhase != StemsModelPhase.failed) {
      return;
    }
    final token = StemsCancelToken();
    _download = token;
    _modelPhase = StemsModelPhase.downloading;
    _receivedBytes = 0;
    _modelError = null;
    _notifiedPermille = -1;
    _notify();

    try {
      await _store.download(
        cancel: token,
        onPhase: (phase) {
          if (token.isCancelled || _disposed) return;
          final next = phase == StemsDownloadPhase.checking
              ? StemsModelPhase.verifying
              : StemsModelPhase.downloading;
          if (next == _modelPhase) return;
          _modelPhase = next;
          _notify();
        },
        onProgress: (progress) {
          if (token.isCancelled || _disposed) return;
          _receivedBytes = progress.receivedBytes;
          // Thousands of chunks arrive; a rebuild per tenth of a percent is
          // already smoother than the bar can show.
          final permille = (progress.fraction * 1000).floor();
          if (permille == _notifiedPermille) return;
          _notifiedPermille = permille;
          _notify();
        },
      );
      if (token.isCancelled) {
        _modelPhase = StemsModelPhase.absent;
        _receivedBytes = 0;
      } else {
        _modelPhase = StemsModelPhase.ready;
        _receivedBytes = totalBytes;
      }
    } on StemsDownloadCancelled {
      _modelPhase = StemsModelPhase.absent;
      _receivedBytes = 0;
    } on StemsDownloadException catch (e) {
      debugPrint('Stems: model download failed: $e');
      _modelPhase = StemsModelPhase.failed;
      _modelError = e.message;
    } catch (e) {
      debugPrint('Stems: model download failed: $e');
      _modelPhase = StemsModelPhase.failed;
      _modelError = "The download didn't finish. Try again.";
    } finally {
      if (identical(_download, token)) _download = null;
    }
    if (_disposed) return;
    _notify();
    if (_modelPhase == StemsModelPhase.ready) unawaited(_prepareEngine());
  }

  /// Stops a download. Files that already verified are kept for next time.
  void cancelDownload() {
    final token = _download;
    if (token == null || token.isCancelled) return;
    token.cancel();
    _notify();
  }

  /// Deletes the downloaded model — offered when the phone turned out to be
  /// too slow to use it. The speed test's verdict is kept.
  Future<void> deleteModel() async {
    _download?.cancel();
    if (_modelLoaded) {
      // Disarm before unloading: the engine must never be asked to work
      // without a model.
      _modelLoaded = false;
      _syncArmed();
      _closeEvents();
      await _guard<void>(Channel.stemsUnloadModel, null);
    }
    _syncArmed();
    try {
      await _store.delete();
    } catch (e) {
      debugPrint('Stems: could not delete the model: $e');
    }
    if (_disposed) return;
    _modelPhase = StemsModelPhase.absent;
    _receivedBytes = 0;
    _notify();
  }

  // ===========================================================================
  // Engine: load, speed test, arming
  // ===========================================================================

  /// Forgets the speed-test verdict and runs it again (once a model is here).
  Future<void> retestDevice() async {
    await _prefs.remove(_benchmarkKey);
    _benchmark = null;
    _support = StemsDeviceSupport.unknown;
    _engineError = null;
    _notify();
    await _prepareEngine();
  }

  /// Tries again after the engine failed to start.
  Future<void> retryEngine() async {
    _engineError = null;
    _notify();
    await _prepareEngine();
  }

  /// The Stems tab came on or off screen.
  void setTabVisible(bool visible) {
    if (_disposed || _tabVisible == visible) return;
    _tabVisible = visible;
    _syncArmed();
    if (visible) unawaited(_prepareEngine());
    _notify();
  }

  /// Loads the model and runs the speed test, as far as each is still needed.
  /// Only while something wants the engine; one run at a time.
  Future<void> _prepareEngine() async {
    if (_preparing || _disposed) return;
    if (_modelPhase != StemsModelPhase.ready ||
        _support == StemsDeviceSupport.unsupported ||
        _engineError != null ||
        !armed) {
      return;
    }
    if (_modelLoaded && _support == StemsDeviceSupport.supported) {
      _syncArmed();
      return;
    }
    _preparing = true;
    try {
      if (!_modelLoaded) {
        final String dir;
        try {
          dir = (await _store.directory()).path;
        } catch (e) {
          debugPrint('Stems: no model directory: $e');
          _engineError = "Stems couldn't start on this phone.";
          return;
        }
        final ok = await _guard(() => Channel.stemsLoadModel(dir), false);
        if (_disposed) return;
        if (!ok) {
          _engineError = "Stems couldn't start on this phone.";
          return;
        }
        _modelLoaded = true;
      }
      // A few seconds of full CPU: not worth spending on someone who has
      // already left the tab. It runs the next time it is opened.
      if (_support == StemsDeviceSupport.unknown && armed) {
        await _runBenchmark();
      }
    } finally {
      _preparing = false;
      if (!_disposed) {
        _syncArmed();
        _notify();
      }
    }
  }

  Future<void> _runBenchmark() async {
    _support = StemsDeviceSupport.benchmarking;
    _notify();
    final raw = await _guard<Map<String, dynamic>?>(
      Channel.stemsBenchmark,
      null,
    );
    if (_disposed) return;
    if (raw == null) {
      // No answer is not a verdict: nothing is remembered, and the tab offers
      // to try again.
      _support = StemsDeviceSupport.unknown;
      _engineError = "Couldn't check this phone's speed.";
      return;
    }
    final result = StemsBenchmark.fromMap(raw);
    _benchmark = result;
    _support = result.supported
        ? StemsDeviceSupport.supported
        : StemsDeviceSupport.unsupported;
    try {
      await _prefs.setString(_benchmarkKey, jsonEncode(result.toJson()));
    } catch (e) {
      debugPrint('Stems: could not remember the speed test: $e');
    }
    if (!result.supported && _modelLoaded) {
      _modelLoaded = false;
      await _guard<void>(Channel.stemsUnloadModel, null);
    }
  }

  /// Tells the engine whether to work, whenever that changes, and schedules
  /// the idle unload.
  void _syncArmed() {
    if (_disposed) return;
    final want =
        armed && _modelLoaded && _support == StemsDeviceSupport.supported;
    if (want != _nativeArmed) {
      _nativeArmed = want;
      if (want) {
        _openEvents();
        _awaitingStatus = true;
        // Levels first: the platform takes calls in order, so the engine
        // starts with the current mix rather than a moment of the default one.
        _flushLevels(force: true);
        _fire(() => Channel.stemsSetArmed(true));
        unawaited(_pullStatus());
      } else {
        _fire(() => Channel.stemsSetArmed(false));
        _dropStreamFetch();
        _failedStreams.clear();
      }
    }
    if (!armed && _modelLoaded) {
      _unloadTimer ??= Timer(unloadAfter, _unloadIdleModel);
    } else {
      _unloadTimer?.cancel();
      _unloadTimer = null;
    }
  }

  void _unloadIdleModel() {
    _unloadTimer = null;
    if (_disposed || armed || !_modelLoaded) return;
    _modelLoaded = false;
    _closeEvents();
    _status = StemsEngineStatus.idle;
    _fire(Channel.stemsUnloadModel);
    _notify();
  }

  void _openEvents() {
    _events ??= Channel.stemsEvents.listen(
      _onEvent,
      onError: (Object e) => debugPrint('Stems: event stream error: $e'),
    );
  }

  void _closeEvents() {
    _events?.cancel();
    _events = null;
    _awaitingStatus = false;
  }

  void _onEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    _eventSeq++;
    final next = StemsEngineStatus.fromMap(event);
    final wasAwaiting = _awaitingStatus;
    _awaitingStatus = false;
    if (next == _status && !wasAwaiting) return;
    _status = next;
    _maybeFetchStream();
    _notify();
  }

  /// Asks for the engine's state right after arming, so the tab isn't blank
  /// until the next change. An event that arrives first wins.
  Future<void> _pullStatus() async {
    final seq = _eventSeq;
    final raw = await _guard<Map<String, dynamic>?>(
      Channel.stemsGetStatus,
      null,
    );
    if (_disposed || raw == null || seq != _eventSeq || !_nativeArmed) return;
    _onEvent(raw);
  }

  // ===========================================================================
  // Streams
  // ===========================================================================

  /// Keeps one stream fetch running for what needs it most: the playing
  /// stream when the engine says it has no copy, otherwise the queued one, so
  /// the next song has stems from its start. A fetch for a stream that is
  /// neither any more is dropped.
  void _maybeFetchStream() {
    final fetch = _fetchStream;
    if (fetch == null || _disposed || !_nativeArmed) return;
    final st = _status;
    bool wants(String? key) =>
        key != null &&
        key.startsWith('http') &&
        !_providedStreams.contains(key) &&
        !_failedStreams.contains(key) &&
        !_unfetchableStreams.contains(key);
    final current =
        st.state == StemsEngineState.unavailable && st.reason == 'stream'
        ? st.trackKey
        : null;
    final next = st.nextKey == st.trackKey ? null : st.nextKey;
    final want = wants(current) ? current : (wants(next) ? next : null);
    final running = _streamKey;
    if (running != null && running != want) {
      // Keep fetching the queued stream while the playing one has its copy and
      // is not asking for anything; drop anything else.
      if (want == null && running == next) return;
      _dropStreamFetch();
    }
    if (want == null || want == _streamKey) return;
    final token = StemsCancelToken();
    _streamKey = want;
    _streamProgress = 0;
    _streamPermille = -1;
    _streamCancel = token;
    unawaited(_fetchStreamCopy(fetch, want, token));
  }

  Future<void> _fetchStreamCopy(
    StemsStreamFetcher fetch,
    String key,
    StemsCancelToken token,
  ) async {
    try {
      final path = await fetch(
        key,
        cancel: token,
        onProgress: (fraction) {
          if (token.isCancelled || _disposed) return;
          _streamProgress = fraction;
          final permille = (fraction * 1000).floor();
          if (permille == _streamPermille) return;
          _streamPermille = permille;
          if (key == _status.trackKey) _notify();
        },
      );
      if (token.isCancelled || _disposed) return;
      if (path == null) {
        _unfetchableStreams.add(key);
      } else {
        _providedStreams.add(key);
        await _guard<void>(() => Channel.stemsProvideStream(key, path), null);
      }
    } on StemsDownloadCancelled {
      return;
    } catch (e) {
      debugPrint('Stems: could not fetch the stream: $e');
      if (!token.isCancelled) _failedStreams.add(key);
    } finally {
      if (identical(_streamCancel, token)) {
        _streamCancel = null;
        _streamKey = null;
        if (!_disposed) {
          _maybeFetchStream(); // the queued one, if the playing one is done
          _notify();
        }
      }
    }
  }

  /// Stops the running fetch (stems switched off, or nobody needs that stream
  /// now); failures are forgotten so the next session tries again.
  void _dropStreamFetch() {
    _streamCancel?.cancel();
    _streamCancel = null;
    _streamKey = null;
  }

  // ===========================================================================
  // Mix
  // ===========================================================================

  /// Moves a fader (0–1). Drags call this per frame; levels reach the engine
  /// at most every [levelInterval], and [commitFader] sends the last one.
  void setFader(Stem stem, double value) =>
      _applyMix(_mix.withFader(stem, quantizeFader(value)));

  /// A fader gesture ended: make sure the engine has its final value now.
  void commitFader() => _flushLevels();

  /// Double-tap: the fader back to 100%.
  void resetFader(Stem stem) =>
      _applyMix(_mix.withFader(stem, StemsMix.unity), flush: true);

  void togglePad(Stem stem) => _applyMix(_mix.togglePad(stem), flush: true);

  void tapCombo(StemCombo combo) =>
      _applyMix(_mix.tapCombo(combo), flush: true);

  /// Every fader to 100%, every pad on.
  void reset() => _applyMix(_mix.reset(), flush: true);

  void _applyMix(StemsMix next, {bool flush = false}) {
    if (_disposed || next == _mix) return;
    _mix = next;
    _engaged.value = next.engaged;
    if (flush) {
      _flushLevels();
    } else {
      _scheduleLevels();
    }
    _syncArmed();
    if (next.engaged) unawaited(_prepareEngine());
    _notify();
  }

  void _scheduleLevels() {
    _levelsPending = true;
    if (_levelsTimer == null) _sendLevels();
  }

  void _flushLevels({bool force = false}) {
    _levelsTimer?.cancel();
    _levelsTimer = null;
    _sendLevels(force: force);
  }

  void _sendLevels({bool force = false}) {
    _levelsPending = false;
    final levels = _mix.effectiveLevels;
    final last = _lastSentLevels;
    if (!force && last != null && listEquals(last, levels)) return;
    _lastSentLevels = levels;
    _fire(
      () => Channel.stemsSetLevels(
        vocals: levels[Stem.vocals.index],
        drums: levels[Stem.drums.index],
        instruments: levels[Stem.instruments.index],
      ),
    );
    _levelsTimer = Timer(levelInterval, _onLevelsWindowEnd);
  }

  void _onLevelsWindowEnd() {
    _levelsTimer = null;
    if (_levelsPending) _sendLevels();
  }

  // ===========================================================================
  // Plumbing
  // ===========================================================================

  /// A native call whose failure — missing engine, platform error, wrong
  /// answer type, timeout — reads as [fallback] instead of an exception.
  Future<T> _guard<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call().timeout(nativeTimeout);
    } catch (e) {
      debugPrint('Stems: native call failed: $e');
      return fallback;
    }
  }

  /// A native call nobody waits for. Sent synchronously, so calls keep their
  /// order.
  void _fire(Future<void> Function() call) {
    unawaited(
      call().catchError((Object e) {
        debugPrint('Stems: native call failed: $e');
      }),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _download?.cancel();
    _levelsTimer?.cancel();
    _unloadTimer?.cancel();
    _streamCancel?.cancel();
    _events?.cancel();
    _engaged.dispose();
    super.dispose();
  }
}
