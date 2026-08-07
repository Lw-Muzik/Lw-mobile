/// The whole stack against the real YouTube: worker isolate, network, parsers.
///
/// **Excluded from the default run** — these need a working connection and
/// depend on a service nobody here controls, so a red build must never mean
/// "YouTube was slow". Run them deliberately:
///
/// ```
/// flutter test --tags live test/ytmusic/yt_live_test.dart
/// ```
///
/// They are also the only thing that catches YouTube reshaping a page. The
/// fixture tests in `yt_parse_test.dart` will stay green forever against a
/// response that is no longer the one being sent; these will not. Run them when
/// Discover starts behaving oddly, before suspecting anything else.
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:eq_app/services/ytmusic/parse/yt_tracks.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_worker.dart';

void main() {
  tearDownAll(YtWorker.instance.dispose);

  test('categories come back with both grids populated', () async {
    final sections =
        await YtWorker.instance.run<List<ExploreSection>>(YtOp.categories);

    expect(sections, isNotEmpty);
    final total =
        sections.fold<int>(0, (sum, s) => sum + s.categories.length);
    // 38 the day this was written. Asserting a floor rather than the number
    // means YouTube adding a genre is not a test failure, but losing most of
    // them is.
    expect(total, greaterThanOrEqualTo(20),
        reason: 'only $total categories — the grid parser may be stale');
    for (final section in sections) {
      for (final category in section.categories) {
        expect(category.params, isNotEmpty);
      }
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a category page yields shelves with items, songs among them', () async {
    final sections =
        await YtWorker.instance.run<List<ExploreSection>>(YtOp.categories);
    final category = sections
        .expand((s) => s.categories)
        .firstWhere((c) => c.title == 'African',
            orElse: () => sections.first.categories.first);

    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.categoryPage,
      {'params': category.params},
    );

    expect(shelves, isNotEmpty, reason: 'no shelves on ${category.title}');
    for (final shelf in shelves) {
      expect(shelf.items, isNotEmpty, reason: 'empty shelf "${shelf.title}"');
    }
    // A Songs shelf is a carousel holding list rows. Losing it is the exact
    // regression that emptied twenty genre pages on desktop, and it is silent.
    final songs = shelves.expand((s) => s.items).where((i) => i.isPlayable);
    expect(songs, isNotEmpty,
        reason: 'no playable rows — the row reader may have gone stale');
    // Albums are the other thing that quietly disappears.
    final albums =
        shelves.expand((s) => s.items).where((i) => i.kind == ExploreKind.album);
    expect(albums, isNotEmpty, reason: 'no albums on ${category.title}');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('every search filter returns its own kind', () async {
    for (final filter in SearchFilter.values) {
      final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
        YtOp.search,
        {'query': 'Burna Boy', 'params': filter.params},
      );
      expect(shelves, isNotEmpty, reason: 'no results for ${filter.label}');
      final items = shelves.expand((s) => s.items);
      expect(items, isNotEmpty, reason: 'empty shelves for ${filter.label}');

      final expected = switch (filter) {
        SearchFilter.songs => ExploreKind.song,
        SearchFilter.videos => ExploreKind.video,
        SearchFilter.albums => ExploreKind.album,
        SearchFilter.artists => ExploreKind.artist,
        SearchFilter.playlists => ExploreKind.playlist,
        // The unfiltered query is a mix by design — nothing to assert.
        SearchFilter.top => null,
      };
      if (expected == null) continue;
      expect(items.where((i) => i.kind == expected), isNotEmpty,
          reason: 'the ${filter.label} filter returned no $expected');
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('suggestions complete a partial query', () async {
    final suggestions = await YtWorker.instance
        .run<List<String>>(YtOp.suggestions, {'query': 'burna'});
    expect(suggestions, isNotEmpty);
    expect(suggestions.first.toLowerCase(), contains('burna'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a playlist from search opens into tracks', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'afrobeats hits', 'params': SearchFilter.playlists.params},
    );
    final playlist = shelves
        .expand((s) => s.items)
        .firstWhere((i) => i.kind == ExploreKind.playlist);
    // The VL prefix is load-bearing: without it this is an HTTP 400.
    expect(playlist.id, startsWith('VL'));

    final list = await YtWorker.instance.run<YtTrackList>(YtOp.trackList, {
      'id': playlist.id,
      'kind': TrackListKind.playlist.index,
      'title': playlist.title,
    });
    expect(list.tracks, isNotEmpty, reason: 'opened "${playlist.title}" empty');
    expect(list.tracks.every((t) => t.videoId.isNotEmpty), isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('a song resolves to a playable, unexpired audio target', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy Last Last', 'params': SearchFilter.songs.params},
    );
    final song =
        shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);

    final target = await YtWorker.instance
        .run<StreamTarget>(YtOp.resolveAudio, {'videoId': song.id});

    expect(target.url, contains('googlevideo.com'));
    expect(target.headers, isNotEmpty,
        reason: 'the CDN checks the User-Agent that resolved the url');
    expect(target.expiresAt, isNotNull,
        reason: 'no stated expiry means the cache must treat it as stale');
    expect(target.isFresh, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  /// The reason `idleTimeout` is raised and prefetch exists.
  ///
  /// Measured with curl on one connection: a cold resolve is ~0.74 s of which
  /// ~0.6 s is the TLS handshake; a reused connection resolves in ~0.14 s. This
  /// asserts the worker actually gets that reuse — if the pool ever stops being
  /// shared, the second resolve regresses to handshake territory and this fails.
  test('a warm connection resolves far faster than a cold one', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'afrobeats', 'params': SearchFilter.songs.params},
    );
    final songs =
        shelves.expand((s) => s.items).where((i) => i.isPlayable).toList();
    expect(songs.length, greaterThanOrEqualTo(3));

    final watch = Stopwatch()..start();
    await YtWorker.instance
        .run<StreamTarget>(YtOp.resolveAudio, {'videoId': songs[0].id});
    final cold = watch.elapsedMilliseconds;

    final warm = <int>[];
    for (final song in songs.skip(1).take(2)) {
      watch.reset();
      await YtWorker.instance
          .run<StreamTarget>(YtOp.resolveAudio, {'videoId': song.id});
      warm.add(watch.elapsedMilliseconds);
    }

    // ignore: avoid_print
    print('resolve: cold ${cold}ms, warm $warm');
    final slowest = warm.reduce((a, b) => a > b ? a : b);
    // Deliberately loose — this is a network measurement, and the point is that
    // reuse is happening at all, not a precise budget.
    expect(slowest, lessThan(1500),
        reason: 'a pooled resolve should be a few hundred ms at most');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('radio seeds from a song and offers a continuation', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy Last Last', 'params': SearchFilter.songs.params},
    );
    final song =
        shelves.expand((s) => s.items).firstWhere((i) => i.isPlayable);

    final batch = await YtWorker.instance
        .run<RadioBatch>(YtOp.radio, {'videoId': song.id});

    expect(batch.tracks, isNotEmpty, reason: 'radio came back empty');
    // The seed is returned marked `selected` and must not be queued again.
    expect(batch.tracks.any((t) => t.videoId == song.id), isFalse);
    expect(batch.continuation, isNotNull,
        reason: 'no token means the radio cannot continue');
  }, timeout: const Timeout(Duration(seconds: 60)));

  /// Either shape is a pass. YouTube offers HLS for a minority of videos and
  /// adaptive-only for the rest, and which one a given video gets is YouTube's
  /// choice — so this asserts that whichever arrived is *usable*, not which.
  test('a music video resolves to something playable', () async {
    final shelves = await YtWorker.instance.run<List<ExploreShelf>>(
      YtOp.search,
      {'query': 'Burna Boy', 'params': SearchFilter.videos.params},
    );
    final video = shelves
        .expand((s) => s.items)
        .firstWhere((i) => i.kind == ExploreKind.video);

    final target = await YtWorker.instance
        .run<StreamTarget>(YtOp.resolveVideo, {'videoId': video.id});

    switch (target.format) {
      case YtStreamFormat.hls:
        expect(target.url, startsWith('https://'));
        expect(target.url, contains('manifest'));
      case YtStreamFormat.dash:
        // The manifest is a document, not a URL, and has to be well-formed
        // enough for a player to open — including the escaping, since a raw
        // `&` in a googlevideo URL is what makes it malformed XML.
        expect(target.url, startsWith('<?xml'));
        expect(target.url, contains('<MPD'));
        expect(target.url, contains('mimeType="video/mp4"'));
        expect(target.url, contains('mimeType="audio/mp4"'));
        expect(target.url, contains('<SegmentBase indexRange="'));
        expect(target.url, contains('&amp;'));
        expect(RegExp(r'<BaseURL>[^<]*&(?!amp;|lt;|gt;|quot;)')
            .hasMatch(target.url), isFalse,
            reason: 'an unescaped & makes the manifest invalid XML');
      case YtStreamFormat.progressive:
        fail('video resolved to a progressive target, which it never should');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
