/// Mixes built for one person out of the music they own.
///
/// The claims worth pinning are the ones the feature exists for: that a mix is
/// stable while you look at it and different tomorrow, that it is mostly music
/// with a record and substantially music you have forgotten, and that a group
/// too small or too narrow to be a taste produces no mix rather than a thin one.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/mixes/daily_mixes.dart';

MixCandidate track(
  String key, {
  String? artist,
  String? genre,
  int playCount = 0,
  int plays = 0,
  int skips = 0,
  Set<int> hours = const {},
}) =>
    MixCandidate(
      key: key,
      artist: artist,
      genre: genre,
      playCount: playCount,
      plays: plays,
      skips: skips,
      hours: hours,
    );

/// A cluster big and varied enough to count as a taste.
List<MixCandidate> taste(
  String genre,
  String prefix, {
  int count = 20,
  int playCount = 0,
  int plays = 0,
}) =>
    [
      for (var i = 0; i < count; i++)
        track(
          '$prefix$i',
          genre: genre,
          // Varied artists, or the group is a discography rather than a taste.
          artist: '$prefix artist ${i % 5}',
          playCount: playCount,
          plays: plays,
        ),
    ];

final _afternoon = DateTime(2026, 8, 26, 14);
final _evening = DateTime(2026, 8, 26, 19);
final _nextDay = DateTime(2026, 8, 27, 14);

void main() {
  group('dayparts', () {
    test('the day is divided the way someone listening would describe it', () {
      expect(Daypart.of(DateTime(2026, 1, 1, 6)), Daypart.earlyMorning);
      expect(Daypart.of(DateTime(2026, 1, 1, 9)), Daypart.morning);
      expect(Daypart.of(DateTime(2026, 1, 1, 14)), Daypart.afternoon);
      expect(Daypart.of(DateTime(2026, 1, 1, 19)), Daypart.evening);
      expect(Daypart.of(DateTime(2026, 1, 1, 23)), Daypart.lateNight);
      expect(Daypart.of(DateTime(2026, 1, 1, 2)), Daypart.lateNight,
          reason: 'two in the morning is late night, not early morning');
    });

    test('late night wraps around midnight', () {
      expect(Daypart.lateNight.hours, containsAll([22, 23, 0, 1, 4]));
      expect(Daypart.lateNight.hours, isNot(contains(12)));
    });
  });

  group('what gets a mix at all', () {
    test('an empty library gets none', () {
      expect(buildDailyMixes(library: const [], now: _afternoon), isEmpty);
    });

    // The rule that stops the app offering "a jazz mix" to someone with four
    // jazz tracks.
    test('a group too small to be a taste gets none', () {
      final library = [
        ...taste('Afrobeat', 'a'),
        ...taste('Jazz', 'j', count: 4),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes.map((m) => m.descriptor), isNot(contains('Jazz')));
    });

    // Twelve tracks by one artist is not a *genre* mix. It may still be an
    // artist mix, which is the fallback — so what is asserted here is that the
    // genre never becomes the descriptor.
    test('a genre filled by one artist does not become a genre mix', () {
      final library = [
        for (var i = 0; i < 20; i++)
          track('solo$i', genre: 'Ambient', artist: 'One Person'),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes.map((m) => m.descriptor), isNot(contains('Ambient')));
    });

    test('untagged music does not become a mix of its own', () {
      final library = [
        for (var i = 0; i < 40; i++)
          track('u$i', genre: '  ', artist: 'Unknown Artist'),
      ];
      expect(buildDailyMixes(library: library, now: _afternoon), isEmpty,
          reason: 'every untagged file would otherwise land in one huge group');
    });

    test('several real tastes get one mix each', () {
      final library = [
        ...taste('Afrobeat', 'a'),
        ...taste('Soul', 's'),
        ...taste('Rock', 'r'),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes, hasLength(3));
      expect(mixes.map((m) => m.descriptor).toSet(),
          {'Afrobeat', 'Soul', 'Rock'});
    });

    test('the number of mixes is capped', () {
      final library = [
        for (var g = 0; g < 12; g++) ...taste('Genre$g', 'g$g'),
      ];
      expect(
        buildDailyMixes(library: library, now: _afternoon).length,
        lessThanOrEqualTo(6),
      );
    });

    test('the most-listened taste comes first', () {
      final library = [
        ...taste('Quiet', 'q'),
        ...taste('Loved', 'l', playCount: 20, plays: 20),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes.first.descriptor, 'Loved');
    });
  });

  group('clustering falls back when genres are missing', () {
    // This asserted `isEmpty` when it was first written, which matched what the
    // code did and not what it was for: the variety rule was being applied to
    // artist clusters, which have one artist by construction, so the fallback
    // could never fire. A device with an untagged library showed no mixes at
    // all and gave it away.
    test('an untagged library still clusters by artist', () {
      final library = [
        for (var i = 0; i < 20; i++) track('x$i', artist: 'Band A'),
        for (var i = 0; i < 20; i++) track('y$i', artist: 'Band B'),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes.map((m) => m.descriptor).toSet(), {'Band A', 'Band B'});
    });

    test('an artist group too small is still not a taste', () {
      final library = [
        for (var i = 0; i < 4; i++) track('x$i', artist: 'Band A'),
      ];
      expect(buildDailyMixes(library: library, now: _afternoon), isEmpty);
    });

    // Genre clustering keeps its variety rule: this is the album case.
    test('one artist filling a whole genre is still not a genre mix', () {
      final library = [
        for (var i = 0; i < 20; i++)
          track('a$i', genre: 'Ambient', artist: 'One Person'),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes.map((m) => m.descriptor), isNot(contains('Ambient')),
          reason: 'twelve tracks by one artist is an album, not a genre mix');
    });

    // A library of downloads is full of YouTube's auto-generated artist
    // channels. On a real device the fallback produced a mix called
    // "chris brown - topic late night".
    test('a YouTube "- Topic" artist is named like an artist', () {
      final library = [
        for (var i = 0; i < 20; i++)
          track('t$i', artist: 'Chris Brown - Topic'),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes.single.descriptor, 'Chris Brown');
      expect(mixes.single.name, 'chris brown afternoon');
    });

    test('the "- Topic" channel and the artist are one cluster, not two', () {
      final library = [
        for (var i = 0; i < 10; i++) track('a$i', artist: 'Chris Brown'),
        for (var i = 0; i < 10; i++)
          track('b$i', artist: 'Chris Brown - Topic'),
      ];
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes, hasLength(1),
          reason: 'two thin clusters where there is obviously one artist');
      expect(mixes.single.length, greaterThanOrEqualTo(16));
    });

    test('one genre across many artists still produces its mix', () {
      final library = taste('OnlyGenre', 'o', count: 30);
      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes, hasLength(1));
      expect(mixes.single.descriptor, 'OnlyGenre');
    });
  });

  group('naming', () {
    test('a mix is named for its taste and the time of day', () {
      final mixes =
          buildDailyMixes(library: taste('Afrobeat', 'a'), now: _evening);
      expect(mixes.single.name, 'afrobeat evening');
    });

    test('the same taste is named differently later in the day', () {
      final library = taste('Afrobeat', 'a');
      final afternoon = buildDailyMixes(library: library, now: _afternoon);
      final evening = buildDailyMixes(library: library, now: _evening);
      expect(afternoon.single.name, isNot(evening.single.name));
    });
  });

  group('the same mix while you look at it, a different one tomorrow', () {
    final library = [...taste('Afrobeat', 'a', count: 60)];

    test('building twice for the same moment gives the same mix', () {
      final first = buildDailyMixes(library: library, now: _afternoon);
      final second = buildDailyMixes(library: library, now: _afternoon);
      expect(first.single.trackKeys, second.single.trackKeys,
          reason: 'a card that reshuffles on rebuild is one nobody can point at');
    });

    test('any moment within the same daypart gives the same mix', () {
      final early = buildDailyMixes(
          library: library, now: DateTime(2026, 8, 26, 12, 5));
      final late = buildDailyMixes(
          library: library, now: DateTime(2026, 8, 26, 16, 55));
      expect(early.single.trackKeys, late.single.trackKeys);
    });

    test('a different daypart gives a different mix', () {
      final afternoon = buildDailyMixes(library: library, now: _afternoon);
      final evening = buildDailyMixes(library: library, now: _evening);
      expect(afternoon.single.trackKeys, isNot(evening.single.trackKeys));
    });

    // The actual answer to "the same old boring mixes".
    test('tomorrow gives a different mix', () {
      final today = buildDailyMixes(library: library, now: _afternoon);
      final tomorrow = buildDailyMixes(library: library, now: _nextDay);
      expect(today.single.trackKeys, isNot(tomorrow.single.trackKeys));
    });
  });

  group('what goes into a mix', () {
    test('no track appears twice', () {
      final mixes = buildDailyMixes(
        library: taste('Afrobeat', 'a', count: 60),
        now: _afternoon,
      );
      final keys = mixes.single.trackKeys;
      expect(keys.toSet().length, keys.length);
    });

    test('rediscovery: a mix is not only the most-played', () {
      final library = [
        for (var i = 0; i < 30; i++)
          track('played$i',
              genre: 'Afrobeat', artist: 'artist ${i % 5}',
              playCount: 10, plays: 10),
        for (var i = 0; i < 30; i++)
          track('unheard$i', genre: 'Afrobeat', artist: 'artist ${i % 5}'),
      ];
      final keys = buildDailyMixes(library: library, now: _afternoon)
          .single
          .trackKeys;
      final unheard = keys.where((k) => k.startsWith('unheard')).length;
      expect(unheard, greaterThan(0),
          reason: 'a mix of what you already play is one you could make yourself');
      expect(keys.where((k) => k.startsWith('played')).length, greaterThan(0));
    });

    test('a track skipped most times it played is not treated as proven', () {
      const skipped = MixCandidate(
          key: 's', plays: 10, skips: 9, genre: 'X', artist: 'A');
      expect(skipped.isProven, isFalse);
    });

    test('one skip out of one play is not a verdict', () {
      const once =
          MixCandidate(key: 's', plays: 1, skips: 1, genre: 'X', artist: 'A');
      expect(once.isProven, isFalse);
      expect(once.isNovel, isFalse, reason: 'it has been played');
    });

    test('a v1 install with play counts but no events still has proven tracks',
        () {
      const legacy = MixCandidate(key: 'l', playCount: 9, genre: 'X');
      expect(legacy.isProven, isTrue);
      expect(legacy.isNovel, isFalse);
    });

    test('the mix is capped at the requested length', () {
      final mixes = buildDailyMixes(
        library: taste('Afrobeat', 'a', count: 200),
        now: _afternoon,
        tracksPerMix: 25,
      );
      expect(mixes.single.length, 25);
    });
  });

  group('cold start — a fresh install with no history at all', () {
    test('still produces mixes, drawn entirely from what is owned', () {
      final library = taste('Afrobeat', 'a', count: 40);
      expect(library.every((t) => t.isNovel), isTrue);

      final mixes = buildDailyMixes(library: library, now: _afternoon);
      expect(mixes, hasLength(1));
      expect(mixes.single.length, greaterThanOrEqualTo(20),
          reason: 'an empty proven pool must not produce a short mix');
    });
  });

  group('time of day biases what is drawn', () {
    test('music played at this hour is favoured over music that is not', () {
      // Two halves of one taste, identical but for when they get played.
      final library = [
        for (var i = 0; i < 30; i++)
          track('day$i',
              genre: 'Afrobeat', artist: 'a${i % 5}',
              playCount: 5, plays: 5, hours: const {13, 14, 15}),
        for (var i = 0; i < 30; i++)
          track('night$i',
              genre: 'Afrobeat', artist: 'a${i % 5}',
              playCount: 5, plays: 5, hours: const {23, 0, 1}),
      ];
      final keys =
          buildDailyMixes(library: library, now: _afternoon).single.trackKeys;
      final day = keys.where((k) => k.startsWith('day')).length;
      final night = keys.where((k) => k.startsWith('night')).length;
      expect(day, greaterThan(night));
      expect(night, greaterThan(0),
          reason: 'a bias, not a filter — the rest must stay reachable');
    });
  });
}
