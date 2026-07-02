import 'dart:async';
import 'package:flutter/foundation.dart';
import '../Helpers/Channel.dart';
import '../models/stem_model.dart';

class StemController extends ChangeNotifier {
  final Map<Stem, StemState> _stemStates = {
    for (var s in Stem.values) s: StemState(),
  };

  bool _isSeparating = false;
  double _separationProgress = 0.0;
  String _separationMessage = '';
  bool _stemModeActive = false;
  String? _currentStemSong;
  bool _hasStemsForCurrentSong = false;

  StreamSubscription? _progressSub;

  // Getters
  Map<Stem, StemState> get stemStates => Map.unmodifiable(_stemStates);
  bool get isSeparating => _isSeparating;
  double get separationProgress => _separationProgress;
  String get separationMessage => _separationMessage;
  bool get stemModeActive => _stemModeActive;
  String? get currentStemSong => _currentStemSong;
  bool get hasStemsForCurrentSong => _hasStemsForCurrentSong;

  StemState stateFor(Stem stem) => _stemStates[stem]!;

  // ---- Actions ----

  Future<void> separateCurrentSong(String filePath) async {
    if (_isSeparating) return;
    _isSeparating = true;
    _separationProgress = 0.0;
    _separationMessage = 'Starting...';
    notifyListeners();

    final outputDir = await StemCache.stemDirFor(filePath);

    // Clear old stems if they exist (ensures re-separation replaces stale cache)
    await StemCache.clearStemsFor(filePath);

    _progressSub?.cancel();
    _progressSub = Channel.stemProgressStream.listen((event) {
      final progress = (event['progress'] as num?)?.toInt() ?? 0;
      final message = event['message'] as String? ?? '';

      if (progress < 0) {
        // Error or cancelled
        _isSeparating = false;
        _separationProgress = 0.0;
        _separationMessage = message;
        notifyListeners();
        _progressSub?.cancel();
        return;
      }

      _separationProgress = progress / 100.0;
      _separationMessage = message;

      if (progress >= 100) {
        _isSeparating = false;
        _hasStemsForCurrentSong = true;
        _progressSub?.cancel();
      }

      notifyListeners();
    });

    await Channel.separateStems(filePath, outputDir);
  }

  void cancelSeparation() {
    Channel.cancelStemSeparation();
    _isSeparating = false;
    _separationProgress = 0.0;
    _separationMessage = 'Cancelled';
    _progressSub?.cancel();
    notifyListeners();
  }

  Future<void> loadStems(String filePath) async {
    final paths = await StemCache.stemPaths(filePath);
    await Channel.loadStems(
      vocalsPath: paths[Stem.vocals]!,
      drumsPath: paths[Stem.drums]!,
      bassPath: paths[Stem.bass]!,
      otherPath: paths[Stem.other]!,
    );
    _currentStemSong = filePath;
    notifyListeners();
  }

  void unloadStems() {
    // Deactivate native stem mixing BEFORE unmapping the stem buffers so the
    // audio thread can't touch freed mappings.
    if (_stemModeActive) {
      Channel.deactivateStemMode();
    }
    Channel.unloadStems();
    _currentStemSong = null;
    _stemModeActive = false;
    notifyListeners();
  }

  Future<void> activateStemMode() async {
    await Channel.activateStemMode();
    _stemModeActive = true;
    notifyListeners();
  }

  Future<void> deactivateStemMode() async {
    await Channel.deactivateStemMode();
    _stemModeActive = false;
    notifyListeners();
  }

  void setVolume(Stem stem, double volume) {
    _stemStates[stem] = _stemStates[stem]!.copyWith(volume: volume);
    Channel.setStemVolume(stem.index, volume);
    notifyListeners();
  }

  void toggleMute(Stem stem) {
    final current = _stemStates[stem]!;
    final newMuted = !current.muted;
    _stemStates[stem] = current.copyWith(muted: newMuted);
    Channel.setStemMute(stem.index, newMuted);
    notifyListeners();
  }

  void toggleSolo(Stem stem) {
    final current = _stemStates[stem]!;
    final newSoloed = !current.soloed;
    _stemStates[stem] = current.copyWith(soloed: newSoloed);
    Channel.setStemSolo(stem.index, newSoloed);
    notifyListeners();
  }

  void stemSeek(int samplePosition) {
    Channel.stemSeek(samplePosition);
  }

  // ---- Presets ----

  void applyKaraoke() {
    _stemStates[Stem.vocals] = _stemStates[Stem.vocals]!.copyWith(muted: true, soloed: false);
    _stemStates[Stem.drums] = _stemStates[Stem.drums]!.copyWith(muted: false, soloed: false, volume: 1.0);
    _stemStates[Stem.bass] = _stemStates[Stem.bass]!.copyWith(muted: false, soloed: false, volume: 1.0);
    _stemStates[Stem.other] = _stemStates[Stem.other]!.copyWith(muted: false, soloed: false, volume: 1.0);
    _applyStemStates();
    notifyListeners();
  }

  void applyAcapella() {
    for (var s in Stem.values) {
      _stemStates[s] = _stemStates[s]!.copyWith(
        soloed: s == Stem.vocals,
        muted: false,
        volume: 1.0,
      );
    }
    _applyStemStates();
    notifyListeners();
  }

  void applyInstrumental() {
    _stemStates[Stem.vocals] = _stemStates[Stem.vocals]!.copyWith(muted: true, soloed: false);
    _stemStates[Stem.drums] = _stemStates[Stem.drums]!.copyWith(muted: false, soloed: false, volume: 1.0);
    _stemStates[Stem.bass] = _stemStates[Stem.bass]!.copyWith(muted: false, soloed: false, volume: 1.0);
    _stemStates[Stem.other] = _stemStates[Stem.other]!.copyWith(muted: false, soloed: false, volume: 1.0);
    _applyStemStates();
    notifyListeners();
  }

  void resetAll() {
    for (var s in Stem.values) {
      _stemStates[s] = StemState();
    }
    _applyStemStates();
    notifyListeners();
  }

  void _applyStemStates() {
    for (var s in Stem.values) {
      final state = _stemStates[s]!;
      Channel.setStemVolume(s.index, state.volume);
      Channel.setStemMute(s.index, state.muted);
      Channel.setStemSolo(s.index, state.soloed);
    }
  }

  // ---- Song change handling ----

  Future<void> onSongChanged(String? songPath) async {
    // Free the previous song's stems: 4 whole-file float32 WAV mmaps
    // (~340MB for a 4-minute track) that used to stay mapped in BOTH players'
    // engines for the life of the process — nothing ever called unloadStems.
    // Re-opening the mixer for that song just re-mmaps from the disk cache.
    if (_currentStemSong != null && _currentStemSong != songPath) {
      unloadStems();
    }
    if (songPath == null) {
      _hasStemsForCurrentSong = false;
      notifyListeners();
      return;
    }
    _hasStemsForCurrentSong = await StemCache.stemsExist(songPath);
    notifyListeners();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
