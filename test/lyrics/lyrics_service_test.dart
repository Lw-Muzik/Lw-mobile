import 'dart:convert';

import 'package:eq_app/models/recognition_result.dart';
import 'package:eq_app/services/lyrics/lrclib_resolver.dart';
import 'package:eq_app/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:on_audio_query/on_audio_query.dart';

const _synced = '[00:01.00] Hello from the other side\n[00:05.00] I must have called';

SongModel _song({
  required String data,
  required String title,
  String? artist,
  String? stem,
  int id = 7,
}) => SongModel({
  '_id': id,
  '_data': data,
  'title': title,
  'artist': artist,
  'duration': 295000,
  '_display_name': '${stem ?? title}.mp3',
  '_display_name_wo_ext': stem ?? title,
});

/// LRCLIB that only knows "Hello" by "Adele".
MockClient _lrclib(List<String> log) => MockClient((req) async {
  log.add('${req.url.path} ${req.url.query}');
  final q = req.url.queryParameters;
  final known =
      (q['track_name'] == 'Hello' && q['artist_name'] == 'Adele') ||
      q['q'] == 'Hello Adele';
  if (!known) {
    return req.url.path == '/api/get'
        ? Response('{"message":"not found"}', 404)
        : Response('[]', 200);
  }
  final hit = {
    'trackName': 'Hello',
    'artistName': 'Adele',
    'duration': 295,
    'syncedLyrics': _synced,
  };
  return Response.bytes(
    utf8.encode(jsonEncode(req.url.path == '/api/get' ? hit : [hit])),
    200,
  );
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weak local tags are fingerprinted before the online lookup', () async {
    final log = <String>[];
    var identified = 0;
    final service = LyricsService(
      lrclib: LrclibResolver(client: _lrclib(log)),
      identify: (_) async {
        identified++;
        return const RecognitionResult(title: 'Hello', artist: 'Adele');
      },
      backend: (t, a) async => null,
    );
    final data = await service.loadLyrics(
      _song(data: '/nonexistent/track01.mp3', title: 'track01', artist: '<unknown>', stem: 'track01'),
    );
    expect(data, isNotNull);
    expect(data!.isSynced, isTrue);
    expect(identified, 1);
    expect(log.first, contains('track_name=Hello'));
  });

  test('a streamed track is never fingerprinted and LRCLIB wins over the backend', () async {
    var identified = 0;
    var backendCalls = 0;
    final service = LyricsService(
      lrclib: LrclibResolver(client: _lrclib([])),
      identify: (_) async {
        identified++;
        return null;
      },
      backend: (t, a) async {
        backendCalls++;
        return 'backend lyrics';
      },
    );
    final data = await service.loadLyrics(
      _song(data: 'https://rr1.googlevideo.com/x', title: 'Adele - Hello (Official Music Video)', artist: 'YouTube Music'),
    );
    expect(data?.lines.first.text, 'Hello from the other side');
    expect(identified, 0);
    expect(backendCalls, 0);
  });

  test('mistagged track that misses is identified once and retried', () async {
    var identified = 0;
    final service = LyricsService(
      lrclib: LrclibResolver(client: _lrclib([])),
      identify: (_) async {
        identified++;
        return const RecognitionResult(title: 'Hello', artist: 'Adele');
      },
      backend: (t, a) async => null,
    );
    final data = await service.loadLyrics(
      _song(data: '/nonexistent/x.mp3', title: 'Wrong Title', artist: 'Wrong Artist', stem: 'x'),
    );
    expect(data, isNotNull);
    expect(identified, 1);
  });

  test('backend error JSON / blank text counts as a miss', () async {
    final service = LyricsService(
      lrclib: LrclibResolver(client: MockClient((_) async => Response('[]', 200))),
      backend: (t, a) async => '   ',
    );
    final data = await service.loadLyrics(
      _song(data: 'https://example.com/a.mp3', title: 'Nothing', artist: 'Nobody'),
    );
    expect(data, isNull);
  });

  test('isMetadataWeak', () {
    expect(LyricsService.isMetadataWeak(_song(data: '/a.mp3', title: 'Hello', artist: '')), isTrue);
    expect(LyricsService.isMetadataWeak(_song(data: '/a.mp3', title: 'Hello', artist: 'Unknown Artist')), isTrue);
    expect(LyricsService.isMetadataWeak(_song(data: '/a.mp3', title: '01 hello', artist: 'Adele', stem: '01 hello')), isTrue);
    expect(LyricsService.isMetadataWeak(_song(data: '/a.mp3', title: 'Hello', artist: 'Adele', stem: '01 hello')), isFalse);
  });
}
