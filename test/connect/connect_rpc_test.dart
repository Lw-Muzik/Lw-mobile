import 'dart:convert';
import 'dart:io';

import 'package:eq_app/services/connect/connect_executor.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_rpc.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

const me = '6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b';

Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/connect/$name').readAsStringSync())
        as Map<String, Object?>;

const rickSong = ExploreItem(
  id: 'dQw4w9WgXcQ',
  kind: ExploreKind.song,
  title: 'Never Gonna Give You Up',
  subtitle: 'Song • Rick Astley • 3:33',
  thumbnail: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
  artist: 'Rick Astley',
  album: 'Whenever You Need Somebody',
  durationSecs: 213,
  hasVideo: true,
);

const rickAlbum = ExploreItem(
  id: 'MPREb_abc123',
  kind: ExploreKind.album,
  title: 'Whenever You Need Somebody',
  subtitle: 'Album • Rick Astley • 1987',
  thumbnail: 'https://lh3.googleusercontent.com/abc=w226-h226',
  artist: 'Rick Astley',
);

class FakeCatalog implements ConnectCatalog {
  @override
  bool available = true;
  Object? failWith;
  final calls = <String>[];

  void _check(String call) {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<ExploreShelf>> search(String query, SearchFilter filter) async {
    _check('search $query ${filter.name}');
    return const [
      ExploreShelf(title: 'Top result', items: [rickSong]),
      ExploreShelf(title: 'Albums', items: [rickAlbum]),
    ];
  }

  @override
  Future<List<String>> suggest(String query) async {
    _check('suggest $query');
    return ['rick astley', 'rick and morty'];
  }

  @override
  Future<({String title, List<YtTrack> tracks})> open(ExploreItem item) async {
    _check('open ${item.kind.name} ${item.id}');
    return (
      title: 'Whenever You Need Somebody',
      tracks: const [
        YtTrack(
          videoId: 'dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
          artist: 'Rick Astley',
          album: 'Whenever You Need Somebody',
          durationSecs: 213,
          thumbnail: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        ),
        YtTrack(videoId: 'gone', title: 'Region locked', isAvailable: false),
      ],
    );
  }

  @override
  Future<List<ExploreShelf>> artist(String browseId) async {
    _check('artist $browseId');
    return const [ExploreShelf(title: 'Songs', items: [rickSong])];
  }
}

class FakeLibrary implements ConnectLibrary {
  final pages = <String>[];

  @override
  Future<Map<int, SongModel>> songsByIds(Iterable<int> ids) async => {};

  @override
  Future<({int total, List<SongModel> songs})> page({
    required int offset,
    required int limit,
    String? query,
  }) async {
    pages.add('$offset $limit $query');
    return (
      total: 1,
      songs: [
        SongModel({
          '_id': 18342,
          '_data': '/music/sura.mp3',
          'title': 'Sura Yako',
          'artist': 'Sauti Sol',
          'album': 'Midnight Train',
          'duration': 201000,
          '_display_name': 'sura.mp3',
          '_display_name_wo_ext': 'sura',
          '_size': 1,
          'is_music': true,
        }),
      ],
    );
  }
}

void main() {
  late FakeCatalog catalog;
  late FakeLibrary library;
  late ConnectRpcHandler handler;

  setUp(() {
    catalog = FakeCatalog();
    library = FakeLibrary();
    handler = ConnectRpcHandler(catalog: catalog, library: library, deviceId: me);
  });

  Future<Map<String, Object?>> answer(Map<String, Object?> rpc) async {
    final frame = ConnectFrame.fromJson(rpc) as RpcFrame;
    final result = await handler.handle(frame);
    return jsonDecode(result.encode()) as Map<String, Object?>;
  }

  /// The fixture's id is reused by more than one result file; compare all but
  /// the id, which is the request's own.
  Map<String, Object?> expectedFor(String name, String id) =>
      {...fixture(name), 'id': id};

  group('answers match the contract fixtures', () {
    test('search', () async {
      final reply = await answer(fixture('rpc.search.from.json'));
      expect(reply, expectedFor('rpc_result.search.json', 'r-1'));
      expect(catalog.calls, ['search rick astley top']);
    });

    test('suggest', () async {
      final reply = await answer(fixture('rpc.suggest.from.json'));
      expect(reply, expectedFor('rpc_result.suggest.json', 'r-2'));
    });

    test('open drops tracks YouTube will not serve', () async {
      final reply = await answer(fixture('rpc.open.from.json'));
      expect(reply, expectedFor('rpc_result.open.json', 'r-3'));
      expect(catalog.calls, ['open album MPREb_abc123']);
    });

    test('artist', () async {
      final reply = await answer(fixture('rpc.artist.from.json'));
      expect(reply, expectedFor('rpc_result.artist.json', 'r-4'));
      expect(catalog.calls, ['artist UCuAXFkgsw1L7xaCfnd5JJOw']);
    });

    test('library answers local refs owned by this phone', () async {
      final reply = await answer(fixture('rpc.library.from.json'));
      expect(reply, expectedFor('rpc_result.library.json', 'r-5'));
      expect(library.pages, ['0 100 sauti']);
    });
  });

  group('search filters', () {
    test('each contract filter reaches its app filter', () async {
      for (final filter in ConnectSearchFilter.values) {
        await answer({
          't': 'rpc',
          'id': 'r',
          'from': 'w',
          'method': 'search',
          'params': {'query': 'q', 'filter': filter.name},
        });
      }
      expect(catalog.calls, [
        'search q top',
        'search q songs',
        'search q videos',
        'search q albums',
        'search q artists',
        'search q playlists',
      ]);
    });
  });

  group('library paging', () {
    Future<void> ask(Map<String, Object?> params) => answer({
          't': 'rpc',
          'id': 'r',
          'from': 'w',
          'method': 'library',
          'params': params,
        });

    test('a limit above 200 is served at 200; a negative offset at 0', () async {
      await ask({'offset': -5, 'limit': 5000});
      expect(library.pages, ['0 200 null']);
    });

    test('a blank query is no query', () async {
      await ask({'offset': 200, 'limit': 50, 'query': '   '});
      expect(library.pages, ['200 50 null']);
    });
  });

  group('errors', () {
    test('YouTube unavailable is not_signed_in, without calling it', () async {
      catalog.available = false;
      for (final name in [
        'rpc.search.from.json',
        'rpc.suggest.from.json',
        'rpc.open.from.json',
        'rpc.artist.from.json',
      ]) {
        final reply = await answer(fixture(name));
        expect(reply['ok'], isFalse, reason: name);
        expect(reply['error'], 'not_signed_in', reason: name);
      }
      expect(catalog.calls, isEmpty);
      // The library does not depend on YouTube.
      expect((await answer(fixture('rpc.library.from.json')))['ok'], isTrue);
    });

    test('a YouTube failure is failed', () async {
      catalog.failWith = const YtException('Could not reach YouTube');
      final reply = await answer(fixture('rpc.search.from.json'));
      expect(reply, {'t': 'rpc_result', 'id': 'r-1', 'ok': false, 'error': 'failed'});
    });

    test('bad params are failed', () async {
      final reply = await answer({
        't': 'rpc',
        'id': 'r-9',
        'from': 'w',
        'method': 'search',
        'params': {'query': 'q', 'filter': 'podcasts'},
      });
      expect(reply['error'], 'failed');
    });

    test('an unknown method is unsupported', () async {
      final reply = await answer({
        't': 'rpc',
        'id': 'r-9',
        'from': 'w',
        'method': 'lyrics',
        'params': {},
      });
      expect(reply, {'t': 'rpc_result', 'id': 'r-9', 'ok': false, 'error': 'unsupported'});
    });
  });
}
