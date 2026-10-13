import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eq_app/models/lyrics_model.dart';
import 'package:eq_app/services/connect/connect_executor.dart';
import 'package:eq_app/services/connect/connect_lyrics.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_rpc.dart';
import 'package:eq_app/services/lyrics/lrclib_resolver.dart';
import 'package:eq_app/services/lyrics_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:on_audio_query/on_audio_query.dart';

const me = '6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b';

SongModel song({int id = 7, String data = '/music/a.mp3'}) => SongModel({
      '_id': id,
      '_data': data,
      'title': 'Hello',
      'artist': 'Adele',
      'album': '25',
      'duration': 295000,
      '_display_name': 'Hello.mp3',
      '_display_name_wo_ext': 'Hello',
    });

class FakeSource implements ConnectLyricsSource {
  final Map<int, Completer<LyricsData?>> pending = {};
  final Map<int, LyricsData?> ready = {};
  int calls = 0;

  @override
  Future<LyricsData?> lyricsFor(SongModel song) {
    calls++;
    if (ready.containsKey(song.id)) return Future.value(ready[song.id]);
    return (pending[song.id] ??= Completer<LyricsData?>()).future;
  }
}

class _NoCatalog implements ConnectCatalog {
  @override
  bool get available => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoLibrary implements ConnectLibrary {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ConnectRpcHandler handler(
  FakeSource? source,
  SongModel? Function() current, {
  Duration window = const Duration(seconds: 10),
}) =>
    ConnectRpcHandler(
      catalog: _NoCatalog(),
      library: _NoLibrary(),
      deviceId: me,
      lyrics: source,
      currentSong: source == null ? null : current,
      lyricsWindow: window,
    );

RpcFrame ask([String id = 'r-1']) =>
    RpcFrame(id: id, from: 'web', method: 'lyrics', params: const {});

Map<String, Object?> result(RpcResultFrame f) {
  expect(f.ok, isTrue);
  return jsonDecode(jsonEncode(f.result)) as Map<String, Object?>;
}

LyricsData synced() => parseLrc(
      '[00:01.00]<00:01.00>Hello <00:01.50>there\n'
      '[00:05.00]\n'
      '[00:06.00]Second line\n'
      '[00:09.00]third',
    ).withSource('lrclib');

void main() {
  group('lyricsResultOf', () {
    final track = const LocalTrackRef(
      deviceId: me,
      id: '7',
      title: 'Hello',
      artist: 'Adele',
    );

    test('synced lines carry ms starts, word timing and the source', () {
      final r = lyricsResultOf(track, synced());
      expect(r.found, isTrue);
      expect(r.synced, isTrue);
      expect(r.source, 'lrclib');
      expect(r.lines.first.startMs, 1000);
      expect(r.lines.first.text, 'Hello there');
      expect(r.lines.first.words!.map((w) => (w.startMs, w.endMs, w.text)), [
        (1000, 1500, 'Hello'),
        (1500, 2000, 'there'),
      ]);
      // A line with no word timing says so with null, not an empty list.
      expect(r.lines[1].words, isNull);
      expect(r.track, same(track));
    });

    test('the LRC offset is taken off so starts are track time', () {
      final data = parseLrc('[offset:500]\n[00:02.00]a\n[00:03.00]b');
      final r = lyricsResultOf(track, data);
      expect(r.lines.map((l) => l.startMs), [1500, 2500]);
    });

    test('plain lyrics are unsynced with null starts and no words', () {
      final r = lyricsResultOf(track, parseLrc('one\ntwo'));
      expect(r.found, isTrue);
      expect(r.synced, isFalse);
      expect(r.lines.map((l) => l.startMs), [null, null]);
      expect(r.lines.map((l) => l.words), [null, null]);
    });

    test('a mixed list (some lines untimed) is not claimed to be synced', () {
      final data = LyricsData(
        isSynced: true,
        raw: '',
        lines: const [
          LyricLine(timestamp: Duration(seconds: 1), text: 'a'),
          LyricLine(text: 'b'),
        ],
      );
      final r = lyricsResultOf(track, data);
      expect(r.synced, isFalse);
      expect(r.lines.every((l) => l.startMs == null), isTrue);
    });

    test('none, or only blank lines, is found:false with no lines', () {
      for (final data in [
        null,
        const LyricsData(lines: [], isSynced: false, raw: ''),
        const LyricsData(
          lines: [LyricLine(text: '  ')],
          isSynced: false,
          raw: '',
        ),
      ]) {
        final r = lyricsResultOf(track, data);
        expect(r.found, isFalse);
        expect(r.synced, isFalse);
        expect(r.source, isNull);
        expect(r.lines, isEmpty);
        expect(r.track, same(track));
      }
    });

    test('the instrumental gap stays as an empty line', () {
      final data = LyricsData(
        isSynced: true,
        raw: '',
        lines: const [
          LyricLine(timestamp: Duration(seconds: 1), text: 'a'),
          LyricLine(timestamp: Duration(seconds: 5), text: ''),
        ],
      );
      final r = lyricsResultOf(track, data);
      expect(r.lines.last.text, '');
      expect(r.lines.last.startMs, 5000);
    });

    test('the result matches the contract fixture shape', () {
      final fixture = jsonDecode(
        File('test/fixtures/connect/rpc_result.lyrics.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final fromFixture = LyricsResult.fromJson(fixture['result']);
      expect(
        jsonDecode(jsonEncode(fromFixture.toJson())),
        fixture['result'],
      );
    });
  });

  group('the lyrics rpc', () {
    test('answers for the current track from the resolver', () async {
      final src = FakeSource()..ready[7] = synced();
      final h = handler(src, () => song());
      final r = result(await h.handle(ask()));
      expect(r['found'], isTrue);
      expect(r['synced'], isTrue);
      expect((r['track']! as Map)['src'], 'local');
      expect((r['track']! as Map)['id'], '7');
      expect((r['lines']! as List), hasLength(3));
    });

    test('plain lyrics', () async {
      final src = FakeSource()..ready[7] = parseLrc('one\ntwo').withSource('file');
      final r = result(await handler(src, () => song()).handle(ask()));
      expect(r['found'], isTrue);
      expect(r['synced'], isFalse);
      expect(r['source'], 'file');
    });

    test('no lyrics found: found:false, with the track', () async {
      final src = FakeSource()..ready[7] = null;
      final r = result(await handler(src, () => song()).handle(ask()));
      expect(r['found'], isFalse);
      expect(r['lines'], isEmpty);
      expect(r['track'], isNotNull);
    });

    test('nothing playing: track null, found:false, resolver untouched',
        () async {
      final src = FakeSource();
      final r = result(await handler(src, () => null).handle(ask()));
      expect(r['track'], isNull);
      expect(r['found'], isFalse);
      expect(src.calls, 0);
    });

    test('a resolver that throws is found:false, not an error', () async {
      final src = _Throwing();
      final h = ConnectRpcHandler(
        catalog: _NoCatalog(),
        library: _NoLibrary(),
        deviceId: me,
        lyrics: src,
        currentSong: () => song(),
      );
      final r = result(await h.handle(ask()));
      expect(r['found'], isFalse);
    });

    test('without a resolver the method is unsupported', () async {
      final f = await handler(null, () => song()).handle(ask());
      expect(f.ok, isFalse);
      expect(f.error, RpcError.unsupported);
    });

    test('a slow lookup answers found:false at the window, then found on re-ask',
        () {
      fakeAsync((async) {
        final src = FakeSource();
        final h = handler(src, () => song());
        RpcResultFrame? first;
        h.handle(ask('r-1')).then((v) => first = v);

        async.elapse(const Duration(seconds: 9));
        expect(first, isNull, reason: 'still within the window');
        async.elapse(const Duration(seconds: 2));
        expect(first, isNotNull);
        expect(result(first!)['found'], isFalse);
        expect(result(first!)['track'], isNotNull);

        // The lookup was not abandoned: it finishes and the next ask has it.
        src.pending[7]!.complete(synced());
        async.flushMicrotasks();
        RpcResultFrame? second;
        h.handle(ask('r-2')).then((v) => second = v);
        async.flushMicrotasks();
        expect(result(second!)['found'], isTrue);
        expect(src.calls, 2);
      });
    });

    test('a lookup that finishes inside the window is answered at once', () {
      fakeAsync((async) {
        final src = FakeSource();
        final h = handler(src, () => song());
        RpcResultFrame? out;
        h.handle(ask()).then((v) => out = v);
        async.elapse(const Duration(seconds: 3));
        src.pending[7]!.complete(synced());
        async.flushMicrotasks();
        expect(result(out!)['found'], isTrue);
      });
    });

    test('a different track gets its own answer', () async {
      final src = FakeSource()
        ..ready[7] = synced()
        ..ready[8] = null;
      var current = song();
      final h = handler(src, () => current);
      expect(result(await h.handle(ask()))['found'], isTrue);
      current = song(id: 8);
      final r = result(await h.handle(ask()));
      expect(r['found'], isFalse);
      expect((r['track']! as Map)['id'], '8');
    });
  });

  group('LyricsService shares one lookup per song', () {
    test('a second ask while the first is running joins it', () async {
      var backendCalls = 0;
      final gate = Completer<String?>();
      final service = LyricsService(
        lrclib: LrclibResolver(
          client: MockClient((req) async => req.url.path == '/api/get'
              ? Response('{}', 404)
              : Response('[]', 200)),
        ),
        backend: (title, artist) {
          backendCalls++;
          return gate.future;
        },
      );
      final s = song(data: 'https://yt/x');
      final a = service.loadLyrics(s);
      final b = service.loadLyrics(s);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.complete('[00:01.00]hi');
      final results = await Future.wait([a, b]);
      expect(backendCalls, 1);
      expect(results[0], same(results[1]));
      expect(results[0]!.source, 'hypemuzik');
      // And now it is cached.
      expect(await service.loadLyrics(s), same(results[0]));
      expect(backendCalls, 1);
    });
  });
}

class _Throwing implements ConnectLyricsSource {
  @override
  Future<LyricsData?> lyricsFor(SongModel song) => throw StateError('boom');
}
