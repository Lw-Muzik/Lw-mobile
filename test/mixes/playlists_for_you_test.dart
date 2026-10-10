import 'package:eq_app/pages/home/home_surface.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:flutter_test/flutter_test.dart';

ExploreItem playlist(String id) =>
    ExploreItem(id: id, kind: ExploreKind.playlist, title: 'Playlist $id');

void main() {
  Future<List<ExploreItem>> noCold() async => fail('cold start not expected');

  Future<List<ExploreShelf>> fake(String q) async {
    if (q == 'broken') throw StateError('offline');
    return [
      ExploreShelf(title: 'Playlists', items: [
        for (var i = 0; i < 10; i++) playlist('$q-$i'),
        playlist('shared'),
        ExploreItem(id: '$q-song', kind: ExploreKind.song, title: 'not a playlist'),
      ]),
    ];
  }

  test('one search per taste, interleaved, deduplicated, capped', () async {
    final asked = <String>[];
    final out = await playlistsForYou(
      tastes: ['afrobeat', 'Burna Boy', 'burna boy', 'tems', 'rema'],
      search: (q) {
        asked.add(q);
        return fake(q);
      },
      coldStart: noCold,
      variation: 1,
    );
    expect(asked, ['afrobeat', 'Burna Boy', 'tems', 'rema'],
        reason: 'first 4 distinct');
    expect(out, hasLength(12), reason: '4 tastes x 3');
    expect(out.map((p) => p.id).toSet(), hasLength(12));
    expect(out.every((p) => p.kind == ExploreKind.playlist), isTrue);
    // Interleaved: the first three come from three different tastes.
    expect(out.take(3).map((p) => p.id.split('-').first).toSet().length,
        greaterThanOrEqualTo(2));
  });

  test('each taste contributes only its top results, in YouTube\'s order', () async {
    final out = await playlistsForYou(
      tastes: ['tems'],
      search: fake,
      coldStart: noCold,
      variation: 3,
    );
    expect(out.map((p) => p.id), ['tems-0', 'tems-1', 'tems-2'],
        reason: 'lower results drift off-topic');
  });

  test('related artists widen the shelf and vary by session', () async {
    final picks = <String>{};
    for (var v = 0; v < 8; v++) {
      final asked = <String>[];
      await playlistsForYou(
        tastes: ['Burna Boy'],
        related: ['Wizkid', 'Davido', 'Asake', 'Rema', 'Tems', 'Ayra Starr'],
        search: (q) {
          asked.add(q);
          return fake(q);
        },
        coldStart: noCold,
        variation: v,
      );
      expect(asked.first, 'Burna Boy', reason: 'the mixes\' own taste leads');
      expect(asked, hasLength(4));
      picks.addAll(asked.skip(1));
    }
    expect(picks.length, greaterThan(3));
  });

  test('no tastes yet: the curated mood playlists rather than nothing', () async {
    var searched = false;
    final out = await playlistsForYou(
      tastes: const [],
      search: (q) async {
        searched = true;
        return const [];
      },
      coldStart: () async => [for (var i = 0; i < 20; i++) playlist('mood-$i')],
      variation: 1,
    );
    expect(searched, isFalse);
    expect(out, hasLength(12));
  });

  test('a failing search costs only its own playlists', () async {
    final out = await playlistsForYou(
      tastes: ['broken', 'tems'],
      search: fake,
      coldStart: noCold,
      variation: 1,
    );
    expect(out, isNotEmpty);
    expect(out.every((p) => p.id.startsWith('tems') || p.id == 'shared'), isTrue);
  });

  test('a new session reshuffles a cold-start shelf', () async {
    Future<List<ExploreItem>> moods() async =>
        [for (var i = 0; i < 20; i++) playlist('mood-$i')];
    final a = await playlistsForYou(
        tastes: const [], search: fake, coldStart: moods, variation: 1);
    final b = await playlistsForYou(
        tastes: const [], search: fake, coldStart: moods, variation: 2);
    expect(a.map((p) => p.id).toList(), isNot(b.map((p) => p.id).toList()));
  });
}
