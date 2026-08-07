/// The hand-off from Discover to the player, end to end.
///
/// Reproduces exactly what a tap does: search, resolve, build the player's own
/// `SongModel`, then check that what comes out is (a) something the player can
/// stream and (b) something it can draw artwork from. Those are the two things
/// that were reported broken, and neither is visible from the parsers alone.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eq_app/services/ytmusic/parse/yt_json.dart';
import 'package:eq_app/services/ytmusic/yt_innertube.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

void main() {
  tearDownAll(YtWorker.instance.dispose);

  /// Every surface a track can reach the player from. A thumbnail missing on
  /// any one of them is a default cover on that screen and nowhere else, which
  /// is exactly the kind of gap a single-surface test misses.
  test('every surface yields a track with artwork and a video id', () async {
    final surfaces = <String, List<ExploreItem>>{};

    for (final filter in [SearchFilter.songs, SearchFilter.videos]) {
      final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
        YtOp.search,
        {'query': 'Burna Boy', 'params': filter.params},
      );
      surfaces['search:${filter.label}'] =
          shelves.expand((s) => s.items).where((i) => i.isPlayable).toList();
    }

    final sections =
        await YtWorker.instance.run<List<ExploreSection>>(YtOp.categories);
    // A *genre* page, not a mood: moods list playlists only and carry no Songs
    // shelf at all, so picking the first category tests nothing about tracks.
    final category = sections
        .expand((s) => s.categories)
        .firstWhere((c) => c.title == 'African' || c.title == 'Hip hop');
    final page = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.categoryPage,
      {'params': category.params},
    );
    surfaces['category'] =
        page.expand((s) => s.items).where((i) => i.isPlayable).toList();

    for (final entry in surfaces.entries) {
      expect(entry.value, isNotEmpty, reason: '${entry.key} had no tracks');
      final withArt =
          entry.value.where((i) => (i.thumbnail ?? '').isNotEmpty).length;
      expect(withArt, entry.value.length,
          reason: '${entry.key}: ${entry.value.length - withArt} of '
              '${entry.value.length} tracks carry no artwork url');
      for (final item in entry.value) {
        expect(item.id, isNotEmpty, reason: '${entry.key}: empty video id');
      }
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('radio tracks carry artwork too', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy Last Last', 'params': SearchFilter.songs.params},
    );
    final seed = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    final batch =
        await YtWorker.instance.run<RadioBatch>(YtOp.radio, {'videoId': seed.id});

    expect(batch.tracks, isNotEmpty);
    final withArt =
        batch.tracks.where((t) => (t.thumbnail ?? '').isNotEmpty).length;
    expect(withArt, batch.tracks.length,
        reason: '${batch.tracks.length - withArt} radio tracks have no artwork');
  }, timeout: const Timeout(Duration(seconds: 60)));

  /// Tapping a search result seeds a station, so the queue behind that one song
  /// has to be real music — not just titles.
  ///
  /// `YtRadioQueue.fill` resolves a batch before appending it and silently drops
  /// whatever fails, so radio tracks that don't resolve don't raise anything:
  /// they just quietly shorten the queue until the music stops early. This
  /// resolves the head of the batch the way `fill` does and insists it survives.
  test('a station seeded from a search result queues playable tracks', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy Last Last', 'params': SearchFilter.songs.params},
    );
    final seed = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    final batch =
        await YtWorker.instance.run<RadioBatch>(YtOp.radio, {'videoId': seed.id});

    expect(batch.tracks, isNotEmpty, reason: 'the station came back empty');
    final head = batch.tracks.take(3).toList();
    final targets = await Future.wait([
      for (final track in head)
        YtWorker.instance
            .run<StreamTarget>(YtOp.resolveAudio, {'videoId': track.videoId})
            // A single dud in a station is YouTube's business, not a failure of
            // this feature; the assertion below is about the batch as a whole.
            .then<StreamTarget?>((t) => t, onError: (_) => null),
    ]);

    final playable = targets.nonNulls.toList();
    expect(playable, hasLength(head.length),
        reason: '${head.length - playable.length} of ${head.length} station '
            'tracks would have been dropped on the way to the queue');
    for (final target in playable) {
      expect(YtInnerTube.isStreamUrl(target.url), isTrue,
          reason: 'a station track resolved to something the player seams '
              'would not recognise as a stream: ${target.url}');
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  /// The cover the player will draw. `ArtworkService` reads a file this app has
  /// to have written first, so a thumbnail url that doesn't fetch is a default
  /// cover for the whole song — which is what was reported.
  test('thumbnail urls fetch, at the size the player asks for', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy', 'params': SearchFilter.songs.params},
    );
    final withArt = shelves
        .expand((s) => s.items)
        .where((i) => i.isPlayable && (i.thumbnail ?? '').isNotEmpty)
        .take(3)
        .toList();
    expect(withArt, isNotEmpty);

    final client = HttpClient();
    try {
      for (final item in withArt) {
        final resized = thumbnailAt(item.thumbnail!, 512);
        final response =
            await (await client.getUrl(Uri.parse(resized))).close();
        expect(response.statusCode, 200,
            reason: 'cover would not fetch: \$resized');
        final bytes =
            await response.fold<int>(0, (n, chunk) => n + chunk.length);
        expect(bytes, greaterThan(1024), reason: 'empty cover: \$resized');
      }
    } finally {
      client.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  /// The one that matters most: does the resolved target actually stream?
  ///
  /// A URL that resolves but 403s on fetch looks, from the UI, exactly like
  /// "the player opened and nothing happened" — which is what was reported.
  test('the resolved target streams bytes the way a player asks for them',
      () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy Last Last', 'params': SearchFilter.songs.params},
    );
    final song = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    final target = await YtWorker.instance
        .run<StreamTarget>(YtOp.resolveAudio, {'videoId': song.id});

    final client = HttpClient();
    try {
      // A player opens with a Range request, never a plain GET.
      final request = await client.getUrl(Uri.parse(target.url));
      target.headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');
      final response = await request.close();

      expect(response.statusCode, anyOf(200, 206),
          reason: 'the CDN refused the target the app would hand the player');
      expect(response.headers.contentType?.mimeType, contains('audio'));
      final bytes = await response.fold<int>(0, (n, chunk) => n + chunk.length);
      expect(bytes, greaterThan(1024));
    } finally {
      client.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  /// just_audio is handed these headers verbatim. If the CDN rejects a request
  /// carrying them, playback is silent — so this checks the exact pairing the
  /// player boundary uses, not the one the resolver happened to use.
  test('the default playback headers are accepted by the CDN', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'afrobeats', 'params': SearchFilter.songs.params},
    );
    final song = shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);
    final target = await YtWorker.instance
        .run<StreamTarget>(YtOp.resolveAudio, {'videoId': song.id});

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(target.url));
      YtInnerTube.audioPlaybackHeaders.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final response = await request.close();
      expect(response.statusCode, anyOf(200, 206),
          reason: 'audioPlaybackHeaders are what the player actually sends');
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
