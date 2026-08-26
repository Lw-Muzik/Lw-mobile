/// The rules that keep a station topped up, and the three bugs that wrote them.
///
/// These assertions came from `test/ytmusic/yt_radio_*_test.dart`, which tested
/// the same rules back when they lived inside `YtRadioQueue` and only YouTube
/// had a station. The rules did not change when they moved; the source of the
/// music did.
///
/// Two things are testable here that were not before. `fill` reached a network
/// singleton through a real `AppController`, so its per-station single-flight
/// guard was documented as untested — a fake [StationSource] and a fake
/// [StationSink] now reach it directly. And a stale continuation token can be
/// checked by asking the *source object* whether it kept one, which is the
/// point of moving the cursor out of the singleton.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/services/radio/radio_queue.dart';
import 'package:eq_app/services/radio/station_source.dart';

SongModel song(String key) => SongModel({
      '_id': key.hashCode.abs(),
      '_data': '/music/$key.mp3',
      'title': key,
      '_display_name': '$key.mp3',
      '_display_name_wo_ext': key,
      '_size': 0,
      'file_extension': 'mp3',
      'is_music': true,
    });

/// A queue that records what was appended to it.
class FakeSink implements StationSink {
  FakeSink([List<SongModel>? initial]) : songs = [...?initial];

  @override
  final List<SongModel> songs;

  int appends = 0;

  @override
  Future<void> appendToQueue(List<SongModel> extra) async {
    appends++;
    songs.addAll(extra);
  }
}

/// A station whose answers are scripted, and which records what it was asked.
class FakeSource implements StationSource {
  FakeSource({
    required String seed,
    List<List<String>>? pages,
    this.hasMore = true,
    this.gate,
  })  : _seed = seed,
        _pages = [...?pages];

  String _seed;
  final List<List<String>> _pages;
  final bool hasMore;

  /// When set, a fetch waits on it — so a test can hold one in flight.
  final Future<void>? gate;

  final List<Set<String>> excludesSeen = [];
  final List<int> limitsSeen = [];
  int fetches = 0;
  bool advanceRefused = false;

  @override
  String get seedKey => _seed;

  @override
  String get kind => 'fake';

  @override
  bool advanceSeed(String key) {
    if (advanceRefused || key == _seed) return false;
    _seed = key;
    return true;
  }

  @override
  Future<StationBatch> fetch({
    required Set<String> exclude,
    required int limit,
  }) async {
    fetches++;
    excludesSeen.add({...exclude});
    limitsSeen.add(limit);
    if (gate != null) await gate;
    if (_pages.isEmpty) return StationBatch.empty;
    final keys = _pages.removeAt(0).where((k) => !exclude.contains(k)).toList();
    return StationBatch(
      tracks: [for (final k in keys) song(k)],
      consumed: keys.toSet(),
      hasMore: hasMore,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final radio = RadioQueue.instance;
  setUp(radio.resetForTest);

  // ---------------------------------------------------------------------------
  group('when the queue is short enough to top up', () {
    test('a queue with plenty left is left alone', () {
      expect(RadioQueue.needsFill(queueLength: 50, index: 0), isFalse);
      expect(RadioQueue.needsFill(queueLength: 50, index: 20), isFalse);
    });

    test('five tracks from the end is the moment to fetch', () {
      expect(RadioQueue.needsFill(queueLength: 26, index: 20), isTrue);
      expect(RadioQueue.needsFill(queueLength: 26, index: 19), isFalse);
    });

    test('the last track certainly needs more', () {
      expect(RadioQueue.needsFill(queueLength: 26, index: 25), isTrue);
    });

    test('an index past the end still asks rather than going quiet', () {
      // A queue that shrank under a running station must not leave the fetch
      // permanently unreachable.
      expect(RadioQueue.needsFill(queueLength: 3, index: 9), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('which station a fetch belongs to', () {
    test('starting another station leaves the first one behind', () {
      radio.attach(FakeSource(seed: 'first'));
      final inFlight = radio.station;

      radio.attach(FakeSource(seed: 'second'));

      expect(radio.isStation(inFlight), isFalse,
          reason: 'a fill still in the air was asked for by a station the '
              'user has since left');
      expect(radio.isStation(radio.station), isTrue);
    });

    test('detaching ends the station a fetch was for', () {
      radio.attach(FakeSource(seed: 'first'));
      final inFlight = radio.station;
      radio.detach();
      expect(radio.isStation(inFlight), isFalse);
    });

    test('walking the seed forward is the same station, not a new one', () {
      radio.attach(FakeSource(seed: 'first'));
      final inFlight = radio.station;
      radio.offeredForTest.add('a');
      radio.advanceSeedForTest();

      expect(radio.isStation(inFlight), isTrue,
          reason: 'walking forward is how one station keeps going — a fill in '
              'flight for it is still wanted');
    });
  });

  // ---------------------------------------------------------------------------
  group('a page that arrives for a station the user has left', () {
    test('contributes nothing: no tracks, no record of what it offered',
        () async {
      final sink = FakeSink();
      final gate = Completer<void>();
      final source = FakeSource(
        seed: 'first',
        pages: [
          ['a', 'b'],
        ],
        gate: gate.future,
      );
      radio.attach(source);

      final inFlight = radio.fill(sink, force: true);
      // The user starts something else while that fetch is in the air.
      radio.attach(FakeSource(seed: 'second'));
      gate.complete();
      await inFlight;

      expect(sink.appends, 0,
          reason: 'appending these is the queue keeping the old radio');
      expect(radio.offeredForTest, {'second'},
          reason: 'the new station never offered those, so it must not think '
              'it has');
    });

    test("cannot poison the new station's cursor, because it is not shared",
        () {
      final first = FakeSource(seed: 'first');
      radio.attach(first);
      final second = FakeSource(seed: 'second');
      radio.attach(second);

      // The old station's source can be advanced all it likes; it is a
      // different object and nothing consults it any more. This is the bug that
      // used to survive every track change until the app was killed.
      first.advanceSeed('somewhere-else');
      expect(second.seedKey, 'second');
      expect(radio.source, same(second));
    });
  });

  // ---------------------------------------------------------------------------
  group('a page that arrives for the station that asked for it', () {
    test('is appended, and what it offered is remembered', () async {
      final sink = FakeSink();
      radio.attach(FakeSource(seed: 'seed', pages: [
        ['a', 'b'],
      ]));

      await radio.fill(sink, force: true);

      expect(sink.songs.map((s) => s.title), ['a', 'b']);
      expect(radio.offeredForTest, {'seed', 'a', 'b'});
    });

    test('the seed and anything already offered are excluded from the ask',
        () async {
      final sink = FakeSink();
      final source = FakeSource(seed: 'seed', pages: [
        ['a'],
        ['b'],
      ]);
      radio.attach(source);

      await radio.fill(sink, force: true);
      await radio.fill(sink, force: true);

      expect(source.excludesSeen.first, {'seed'});
      expect(source.excludesSeen.last, {'seed', 'a'},
          reason: 'page overlap is normal and must not reach the queue twice');
    });

    test('a track that was selected but would not play is not re-offered',
        () async {
      final sink = FakeSink();
      // consumed names a track that never appears in tracks — a resolve that
      // failed. It must still count as spent.
      final source = _DroppingSource(seed: 'seed');
      radio.attach(source);

      await radio.fill(sink, force: true);

      expect(radio.offeredForTest, contains('dead'),
          reason: 'a station with one dead entry would otherwise spend every '
              'top-up rediscovering it');
    });
  });

  // ---------------------------------------------------------------------------
  group('one fetch at a time, per station', () {
    test('a second fill for the same station is dropped while one is running',
        () async {
      final sink = FakeSink();
      final gate = Completer<void>();
      final source = FakeSource(
        seed: 'seed',
        pages: [
          ['a'],
          ['b'],
        ],
        gate: gate.future,
      );
      radio.attach(source);

      final first = radio.fill(sink, force: true);
      await radio.fill(sink, force: true);
      gate.complete();
      await first;

      expect(source.fetches, 1);
    });

    // The guard the old code got wrong: a plain `_fetching` flag made the NEW
    // station's first fill a no-op whenever the old one's fetch was still in
    // the air — which is precisely when a new station gets started.
    test("a fetch for a station the user left does not block the new one's",
        () async {
      final sink = FakeSink();
      final gate = Completer<void>();
      final stale = FakeSource(
        seed: 'first',
        pages: [
          ['a'],
        ],
        gate: gate.future,
      );
      radio.attach(stale);
      final inFlight = radio.fill(sink, force: true);

      final fresh = FakeSource(seed: 'second', pages: [
        ['x', 'y'],
      ]);
      radio.attach(fresh);
      await radio.fill(sink, force: true);

      expect(fresh.fetches, 1,
          reason: 'the new station must be able to fetch immediately');
      expect(sink.songs.map((s) => s.title), ['x', 'y']);

      gate.complete();
      await inFlight;
      expect(sink.songs.map((s) => s.title), ['x', 'y'],
          reason: 'the stale reply must still not append');
    });
  });

  // ---------------------------------------------------------------------------
  group('walking the seed forward keeps the station going', () {
    test('moves to the deepest track the station chose', () {
      final source = FakeSource(seed: 'seed');
      radio.attach(source);
      radio.offeredForTest.addAll(['a', 'b', 'c']);

      expect(radio.advanceSeedForTest(), isTrue);
      expect(source.seedKey, 'c',
          reason: 'the furthest the station got is the direction it was going');
    });

    test('the new seed is one this station picked, never an arbitrary track',
        () {
      final source = FakeSource(seed: 'seed');
      radio.attach(source);
      radio.offeredForTest.add('related');
      radio.advanceSeedForTest();

      // 'related' was returned by the station as a match for 'seed', so asking
      // what matches 'related' walks through neighbouring music. That is the
      // whole difference between an endless station and a shuffle.
      expect(source.seedKey, 'related');
    });

    test('nothing already heard comes back after the seed moves', () {
      final source = FakeSource(seed: 'seed');
      radio.attach(source);
      radio.offeredForTest.addAll(['a', 'b']);
      radio.advanceSeedForTest();

      expect(radio.offeredForTest, containsAll(['a', 'b']),
          reason: 'moving the seed must not reset what the station played');
    });

    test('a station with nothing offered yet has nowhere to move to', () {
      final source = FakeSource(seed: 'seed');
      radio.attach(source);
      expect(radio.advanceSeedForTest(), isFalse);
      expect(source.seedKey, 'seed');
    });

    test('will not move onto the seed it is already using', () {
      final source = FakeSource(seed: 'seed');
      radio.attach(source);
      radio.offeredForTest.add('a');
      expect(radio.advanceSeedForTest(), isTrue);
      expect(source.seedKey, 'a');
      // Nothing new offered since, so there is nowhere further to go and asking
      // the same seed again would only repeat the same dead pages.
      expect(radio.advanceSeedForTest(), isFalse);
    });

    test('a detached station does not walk itself back to life', () {
      radio.attach(FakeSource(seed: 'seed'));
      radio.offeredForTest.add('a');
      radio.detach();
      expect(radio.advanceSeedForTest(), isFalse,
          reason: 'something else is playing; this station is over');
    });

    test('an empty page moves the seed on rather than ending the station',
        () async {
      final sink = FakeSink();
      final source = FakeSource(seed: 'seed', pages: [
        [],
        ['b'],
      ]);
      radio.attach(source);
      radio.offeredForTest.add('a');

      await radio.fill(sink, force: true);

      expect(source.seedKey, 'a', reason: 'the spent seed was walked forward');
      expect(sink.songs.map((s) => s.title), ['b'],
          reason: 'and the second try is what fills the queue');
    });
  });

  // ---------------------------------------------------------------------------
  group('a new station forgets the last one', () {
    test('attaching clears what was offered, keeping only the new seed', () {
      radio.attach(FakeSource(seed: 'seed1'));
      radio.offeredForTest.add('a');
      radio.attach(FakeSource(seed: 'seed2'));
      expect(radio.offeredForTest, {'seed2'},
          reason: 'a track heard on one station is fair game on the next');
    });

    test('detaching forgets everything', () {
      radio.attach(FakeSource(seed: 'seed'));
      radio.offeredForTest.add('a');
      radio.detach();
      expect(radio.offeredForTest, isEmpty);
      expect(radio.isLive, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('the Autoplay gate', () {
    test('a station the app starts by itself is gated', () async {
      final sink = FakeSink();
      final source = FakeSource(seed: 'seed', pages: [
        ['a'],
      ]);
      radio.attach(source);
      await radio.setEnabled(false);

      await radio.fill(sink);

      expect(source.fetches, 0,
          reason: 'with Autoplay off the app makes no requests of its own '
              'accord, rather than fetching a batch and declining to use it');
    });

    test('a station the user asked for by name is not', () async {
      final sink = FakeSink();
      final source = FakeSource(seed: 'seed', pages: [
        ['a'],
      ]);
      radio.attach(source);
      await radio.setEnabled(false);

      await radio.fill(sink, force: true);

      expect(source.fetches, 1);
      expect(sink.songs.map((s) => s.title), ['a']);
    });

    test('onIndexChanged asks only when the end is near', () async {
      final sink = FakeSink([for (var i = 0; i < 50; i++) song('q$i')]);
      final source = FakeSource(seed: 'seed', pages: [
        ['a'],
      ]);
      radio.attach(source);

      await radio.onIndexChanged(sink, 0);
      expect(source.fetches, 0);

      await radio.onIndexChanged(sink, 45);
      expect(source.fetches, 1);
    });

    test('onIndexChanged does nothing when no station is attached', () async {
      final sink = FakeSink();
      await radio.onIndexChanged(sink, 0);
      expect(sink.appends, 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('a source that throws', () {
    test('ends the station quietly rather than raising', () async {
      final sink = FakeSink();
      radio.attach(_ThrowingSource());
      await expectLater(radio.fill(sink, force: true), completes);
      expect(sink.appends, 0);
    });

    test('and leaves the single-flight marker clear for the next try',
        () async {
      final sink = FakeSink();
      radio.attach(_ThrowingSource());
      await radio.fill(sink, force: true);
      // If the marker had leaked, this second fill would be dropped and the
      // station would be permanently stuck after one bad moment.
      final source = FakeSource(seed: 'seed', pages: [
        ['a'],
      ]);
      radio.attach(source);
      await radio.fill(sink, force: true);
      expect(source.fetches, 1);
    });
  });
}

/// A source whose page names a track that failed to become playable.
class _DroppingSource implements StationSource {
  _DroppingSource({required String seed}) : _seed = seed;
  final String _seed;

  @override
  String get seedKey => _seed;
  @override
  String get kind => 'dropping';
  @override
  bool advanceSeed(String key) => false;

  @override
  Future<StationBatch> fetch({
    required Set<String> exclude,
    required int limit,
  }) async =>
      StationBatch(
        tracks: [song('alive')],
        consumed: {'alive', 'dead'},
        hasMore: false,
      );
}

class _ThrowingSource implements StationSource {
  @override
  String get seedKey => 'seed';
  @override
  String get kind => 'throwing';
  @override
  bool advanceSeed(String key) => false;

  @override
  Future<StationBatch> fetch({
    required Set<String> exclude,
    required int limit,
  }) async =>
      throw StateError('the network is on fire');
}
