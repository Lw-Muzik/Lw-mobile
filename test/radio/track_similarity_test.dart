/// What a station made of local files decides is related.
///
/// The seed has no service to ask, so the answer is arithmetic over metadata.
/// The cases that matter are the ones where metadata lies: an untagged library
/// where nine hundred files share "Unknown Artist", a genre column that is
/// empty, a draw asked for more tracks than exist.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/radio/track_similarity.dart';

TrackTraits t(
  String key, {
  String? artist,
  String? album,
  String? genre,
  int? addedAtSec,
  int playCount = 0,
}) =>
    TrackTraits(
      key: key,
      artist: artist,
      album: album,
      genre: genre,
      addedAtSec: addedAtSec,
      playCount: playCount,
    );

void main() {
  final seed = t('seed', artist: 'Kaya', album: 'Sunrise', genre: 'Afrobeat');

  group('what counts as related', () {
    test('the same artist outweighs the same genre', () {
      final sameArtist = t('a', artist: 'Kaya', genre: 'Rock');
      final sameGenre = t('b', artist: 'Someone', genre: 'Afrobeat');
      expect(
        similarity(seed, sameArtist),
        greaterThan(similarity(seed, sameGenre)),
      );
    });

    test('the same genre outweighs the same album alone', () {
      final sameGenre = t('a', artist: 'Someone', genre: 'Afrobeat');
      final sameAlbum = t('b', artist: 'Someone', album: 'Sunrise');
      expect(
        similarity(seed, sameGenre),
        greaterThan(similarity(seed, sameAlbum)),
      );
    });

    test('matching everything beats matching one thing', () {
      final all = t('a', artist: 'Kaya', album: 'Sunrise', genre: 'Afrobeat');
      final one = t('b', artist: 'Kaya');
      expect(similarity(seed, all), greaterThan(similarity(seed, one)));
    });

    test('nothing in common scores zero, not a negative', () {
      expect(similarity(seed, t('a', artist: 'Nobody', genre: 'Polka')), 0);
    });

    test('matching is case- and whitespace-insensitive', () {
      expect(similarity(seed, t('a', artist: '  kAyA ')),
          SimilarityWeights.sameArtist);
    });
  });

  group('metadata that lies', () {
    // The case that would otherwise dominate an untagged library: every
    // untagged file would be maximally "related" to every other one.
    test('"Unknown Artist" on both sides is not a match', () {
      final unknownSeed = t('s', artist: 'Unknown Artist');
      expect(similarity(unknownSeed, t('a', artist: 'Unknown Artist')), 0);
    });

    test('an empty genre on both sides is not a match', () {
      final blank = t('s', artist: 'A', genre: '');
      expect(similarity(blank, t('a', artist: 'B', genre: '')), 0);
    });

    test('a null field never matches another null', () {
      expect(similarity(t('s'), t('a')), 0);
    });
  });

  group('the other signals', () {
    test('being added around the same time counts for something', () {
      const now = 1700000000;
      final near = t('a', addedAtSec: now + 60 * 60 * 24 * 3);
      final far = t('b', addedAtSec: now + 60 * 60 * 24 * 300);
      final s = t('s', addedAtSec: now);
      expect(similarity(s, near), SimilarityWeights.nearbyAddition);
      expect(similarity(s, far), 0);
    });

    test('play count adds a little, and stops adding past the ceiling', () {
      final some = similarity(seed, t('a', playCount: 5));
      final many = similarity(seed, t('b', playCount: 10));
      final absurd = similarity(seed, t('c', playCount: 10000));
      expect(some, greaterThan(0));
      expect(many, greaterThan(some));
      expect(absurd, many, reason: 'past the ceiling more plays say nothing new');
      expect(many, SimilarityWeights.familiarity);
    });
  });

  group('drawing a station', () {
    final library = [
      for (var i = 0; i < 20; i++) t('kaya$i', artist: 'Kaya', genre: 'Afrobeat'),
      for (var i = 0; i < 20; i++) t('other$i', artist: 'Nobody', genre: 'Polka'),
    ];

    test('never draws the seed itself', () {
      final drawn = drawStation(
        seed: seed,
        candidates: [seed, ...library],
        exclude: {},
        limit: 50,
        random: Random(1),
      );
      expect(drawn.map((c) => c.key), isNot(contains('seed')));
    });

    test('never draws anything already offered', () {
      final already = {for (var i = 0; i < 20; i++) 'kaya$i'};
      final drawn = drawStation(
        seed: seed,
        candidates: library,
        exclude: already,
        limit: 50,
        random: Random(1),
      );
      expect(drawn.map((c) => c.key).toSet().intersection(already), isEmpty);
    });

    test('never draws the same track twice in one draw', () {
      final drawn = drawStation(
        seed: seed,
        candidates: library,
        exclude: {},
        limit: 40,
        random: Random(7),
      );
      expect(drawn.map((c) => c.key).toSet().length, drawn.length);
    });

    test('favours related music without ever being a pure filter', () {
      // Over many draws the related half should dominate — but the unrelated
      // half must remain reachable, or a station can never leave one artist.
      var related = 0;
      var unrelated = 0;
      for (var run = 0; run < 40; run++) {
        for (final drawn in drawStation(
          seed: seed,
          candidates: library,
          exclude: {},
          limit: 5,
          random: Random(run),
        )) {
          drawn.key.startsWith('kaya') ? related++ : unrelated++;
        }
      }
      expect(related, greaterThan(unrelated * 2));
      expect(unrelated, greaterThan(0));
    });

    test('a station started twice is not the same station', () {
      List<String> run(int seedValue) => drawStation(
            seed: seed,
            candidates: library,
            exclude: {},
            limit: 10,
            random: Random(seedValue),
          ).map((c) => c.key).toList();
      expect(run(1), isNot(equals(run(2))));
    });

    test('asking for more than exists returns everything once', () {
      final drawn = drawStation(
        seed: seed,
        candidates: library,
        exclude: {},
        limit: 500,
        random: Random(3),
      );
      expect(drawn.length, library.length);
      expect(drawn.map((c) => c.key).toSet().length, library.length);
    });

    test('an empty library draws nothing rather than throwing', () {
      expect(
        drawStation(
          seed: seed,
          candidates: const [],
          exclude: {},
          limit: 10,
          random: Random(1),
        ),
        isEmpty,
      );
    });

    test('a limit of zero draws nothing', () {
      expect(
        drawStation(
          seed: seed,
          candidates: library,
          exclude: {},
          limit: 0,
          random: Random(1),
        ),
        isEmpty,
      );
    });

    test('a library of nothing but the seed draws nothing', () {
      expect(
        drawStation(
          seed: seed,
          candidates: [seed],
          exclude: {},
          limit: 10,
          random: Random(1),
        ),
        isEmpty,
      );
    });
  });
}
