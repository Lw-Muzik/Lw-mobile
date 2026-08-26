/// Keeping a station's queue topped up, whatever the station is made of.
///
/// This is the half of the old `YtRadioQueue` that was never about YouTube:
/// station identity, per-station single-flight, de-duplication, headroom, the
/// Autoplay preference, and appending to the player's queue. Every bug this
/// code has had lived here rather than in the fetching, which is exactly why it
/// is worth having once instead of once per source.
///
/// The comments below record what those bugs were. They are not decoration —
/// each one marks a guard that looks removable and is not.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'station_source.dart';

class RadioQueue {
  RadioQueue._();

  static final RadioQueue instance = RadioQueue._();

  static const _prefsKey = 'ytmusic.autoplay';

  /// How close to the end of the queue to get before fetching more.
  ///
  /// Five tracks is roughly fifteen minutes of warning. It used to be three,
  /// which on a queue that only ever grew by eight meant the station lived
  /// permanently on the edge of running out — and because a failed fetch is
  /// swallowed on purpose, one bad moment ended it silently.
  static const _headroom = 5;

  /// How many tracks to add per fill.
  ///
  /// A YouTube page holds about fifty; this once took eight and threw the rest
  /// away, which is why a station was a seed plus eight tracks and looked like
  /// it had run out before it started. Sources may take fewer — a station
  /// showing pictures writes a manifest per track and runs a shorter way ahead.
  static const batchSize = 25;

  /// Every track this station has already handed over.
  ///
  /// Insertion-ordered, which [_advanceSeed] depends on: the last entry is the
  /// furthest point the station has reached.
  final Set<String> _offered = {};

  bool _enabled = true;
  StationSource? _source;

  /// Which station is playing, counted rather than named.
  ///
  /// A fill spends seconds in the network and the user can start a different
  /// station in that time. Everything a reply wants to write back belongs to
  /// the station that asked, so work carries this number and is dropped on
  /// arrival if it no longer matches.
  int _station = 0;

  /// The station a fetch is in flight for, or null when none is.
  ///
  /// Deliberately not a plain `_fetching` flag: that made the *new* station's
  /// first fill a no-op whenever the old one's fetch was still in the air —
  /// which is exactly when a new station is started — so the queue kept the
  /// only tracks it had, the previous station's.
  int? _fetchingFor;

  /// Whether a station is the thing currently playing.
  bool get isLive => _source != null;

  /// The station running right now, to be handed back to [isStation] later.
  int get station => _station;

  /// Whether [station] is still the one playing.
  ///
  /// The question every piece of in-flight work must ask before it writes
  /// anything down. [isLive] answers a different and weaker question — whether
  /// *a* station is playing — and answering that one is how a fill for the
  /// station the user had just left went on appending to their new queue.
  bool isStation(int station) => isLive && _station == station;

  /// What is supplying the current station, or null when none is attached.
  @visibleForTesting
  StationSource? get source => _source;

  bool get enabled => _enabled;

  Future<void>? _loading;

  /// Reads the stored Autoplay setting.
  ///
  /// Idempotent, so every screen that depends on the answer can ask on open and
  /// only the first ask touches the disk. That matters because [_enabled] starts
  /// at the default: an unread preference does not read as *unknown*, it reads
  /// as `true`, and a user who turned Autoplay off in an earlier session would
  /// get stations anyway on any screen that had not loaded it.
  Future<void> loadPreference() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      // Unreadable preferences leave the default in place.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    // The setting is now known first-hand, so a later `loadPreference` must not
    // read the disk back over it — a read still in flight from another screen
    // would otherwise land after this and undo it.
    _loading ??= Future<void>.value();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
  }

  /// Returns the singleton to the state it has at app start.
  @visibleForTesting
  void resetForTest() {
    _loading = null;
    _enabled = true;
    _source = null;
    _station = 0;
    _fetchingFor = null;
    _offered.clear();
  }

  @visibleForTesting
  Set<String> get offeredForTest => _offered;

  /// Starts a station supplied by [source].
  ///
  /// [source] must be freshly built for this station and never shared with a
  /// previous one — see the note on [StationSource]. Attaching bumps the
  /// station number, so anything still in flight for the last one is dropped
  /// when it lands.
  void attach(StationSource source) {
    _station++;
    _source = source;
    // A track heard on the last station is fair game on this one, and the seed
    // is already playing so it is never worth offering back.
    _offered
      ..clear()
      ..add(source.seedKey);
  }

  /// Stops the station. Called when something that is not a station takes over.
  void detach() {
    _station++;
    _source = null;
    _offered.clear();
  }

  /// Whether a queue of [queueLength] playing [index] is close enough to its
  /// end to be worth fetching more.
  static bool needsFill({required int queueLength, required int index}) =>
      queueLength - index - 1 <= _headroom;

  /// Called as playback advances. Appends more tracks when the end is near.
  ///
  /// Cheap and safe to call on every index change — and it is called on every
  /// index change, from the one setter every track change passes through. It
  /// returns immediately unless a fetch is actually warranted.
  Future<void> onIndexChanged(StationSink controller, int index) async {
    if (!_enabled) return;
    if (!isLive) return;
    if (!needsFill(queueLength: controller.songs.length, index: index)) return;
    await fill(controller);
  }

  /// Fetches the next batch of related tracks and appends them.
  ///
  /// [force] is for a station the user explicitly started, which happens
  /// whatever the Autoplay preference says — that setting governs radio the app
  /// decides to start on its own, not radio asked for by name.
  Future<void> fill(StationSink controller, {bool force = false}) async {
    if (!_enabled && !force) return;
    final source = _source;
    if (source == null) return;

    // One fetch at a time *per station*. A fetch still running for the station
    // the user has left must not stand in for this one — that left a brand new
    // station holding nothing but the old one's tracks.
    final station = _station;
    if (_fetchingFor == station) return;
    _fetchingFor = station;
    try {
      if (await _fillOnce(controller, source, station)) return;
      if (!isStation(station)) return;
      // This seed has nothing left that is not already queued. Walk the station
      // on rather than letting it stop.
      if (!_advanceSeed(source)) return;
      await _fillOnce(controller, source, station);
    } catch (_) {
      // Radio is a courtesy. A batch that will not load costs nothing visible —
      // the queue simply ends where it would have anyway.
    } finally {
      // Only if this fetch is still the one being waited on: a station started
      // since owns the marker now.
      if (_fetchingFor == station) _fetchingFor = null;
    }
  }

  /// One fetch, written back only if it is still wanted. Returns whether it
  /// appended anything.
  ///
  /// The single place a fetch's answer is written back, and therefore the
  /// single place that asks whether the answer is still wanted. A page that
  /// arrives for a station the user has left contributes nothing at all: not
  /// its tracks and not its record of what has been offered.
  Future<bool> _fillOnce(
    StationSink controller,
    StationSource source,
    int station,
  ) async {
    final batch = await source.fetch(
      exclude: Set<String>.unmodifiable(_offered),
      limit: batchSize,
    );

    // Seconds have passed inside that fetch and the user may have started
    // something else entirely. `isLive` is not enough — a *different* station
    // is also live, and that is the case this class kept getting wrong.
    if (!isStation(station)) return false;

    _offered.addAll(batch.consumed);
    if (batch.tracks.isEmpty) return false;

    await controller.appendToQueue(batch.tracks);
    return true;
  }

  /// Points the station at a track it chose itself.
  ///
  /// A seed's own suggestions converge: measured against YouTube, one seed
  /// yields 49 tracks on the first page and then 25, 13, 4, 3 new ones — about
  /// 94 before every page is tracks already queued. At that point the station
  /// has run out of *its* suggestions, which is not the same as running out of
  /// music, and stopping there is what makes an endless station end.
  ///
  /// Moving to the deepest track the station has offered is what keeps the
  /// result related rather than random: that track is one the station itself
  /// picked as a match for the last one, so asking what matches *it* walks
  /// forward through neighbouring music. [_offered] is deliberately not
  /// cleared, so nothing already heard comes back.
  bool _advanceSeed(StationSource source) {
    if (_offered.length <= 1) return false;
    // Insertion-ordered, so the last entry is the furthest the station has got.
    final next = _offered.last;
    if (next == source.seedKey) return false;
    return source.advanceSeed(next);
  }

  @visibleForTesting
  bool advanceSeedForTest() {
    final source = _source;
    if (source == null) return false;
    return _advanceSeed(source);
  }
}
