/// Telling YouTube's audio from the user's own, so the stems engine never
/// separates a YouTube download (YouTube Developer Policies III.I.7).
///
/// Folders can't do it — Android puts downloads beside the user's Phone Link
/// uploads, and iOS used to put them beside the user's imports — so every
/// saved path is recorded, downloads from before the ledger are found by their
/// DASH container, and the whole list goes to the engine as excluded prefixes.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eq_app/services/stems/stems_exclusions.dart';
import 'package:eq_app/services/ytmusic/yt_download_registry.dart';

const _docsA = '/var/mobile/Containers/Data/Application/AAAA/Documents';
const _docsB = '/var/mobile/Containers/Data/Application/BBBB/Documents';

/// The first 12 bytes of an MP4: box size, `ftyp`, major brand.
List<int> _mp4Head(String brand) => [
  0, 0, 0, 0x1c, //
  ...'ftyp'.codeUnits,
  ...brand.codeUnits,
  0, 0, 0, 0, ...'iso6'.codeUnits, ...'mp41'.codeUnits,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  YtDownloadRegistry registry({String? docs = _docsA}) =>
      YtDownloadRegistry(documentsPath: () async => docs);

  group('the ledger', () {
    test(
      'records each saved path once, and says when it learned one',
      () async {
        final r = registry();
        var changes = 0;
        r.addListener(() => changes++);

        await r.record('/storage/emulated/0/Music/HypeMuzik/A - B.m4a');
        await r.record('/storage/emulated/0/Music/HypeMuzik/A - B.m4a');
        final added = await r.recordAll([
          '/storage/emulated/0/Music/HypeMuzik/C - D.m4a',
          '',
        ]);

        expect(added, 1);
        expect(changes, 2);
        expect(await r.paths(), [
          '/storage/emulated/0/Music/HypeMuzik/A - B.m4a',
          '/storage/emulated/0/Music/HypeMuzik/C - D.m4a',
        ]);
      },
    );

    test('keeps paths inside Documents relative, so they survive iOS moving '
        'the app container on update', () async {
      await registry(docs: _docsA).record('$_docsA/Music/YouTube/x.m4a');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(YtDownloadRegistry.prefsKey), [
        'docs:Music/YouTube/x.m4a',
      ]);
      expect(await registry(docs: _docsB).paths(), [
        '$_docsB/Music/YouTube/x.m4a',
      ]);
    });

    test('treats /private/var and /var as the same container', () async {
      await registry(docs: _docsA).record('/private$_docsA/Music/y.m4a');
      expect(await registry(docs: _docsA).paths(), ['$_docsA/Music/y.m4a']);
    });

    test(
      'drops relative entries it cannot resolve rather than guessing',
      () async {
        await registry(docs: _docsA).record('$_docsA/Music/z.m4a');
        expect(await registry(docs: null).paths(), isEmpty);
      },
    );

    test('is capped, oldest first', () async {
      final r = registry();
      await r.recordAll([
        for (var i = 0; i <= YtDownloadRegistry.maxEntries; i++)
          '/storage/emulated/0/Music/HypeMuzik/$i.m4a',
      ]);
      final paths = await r.paths();
      expect(paths, hasLength(YtDownloadRegistry.maxEntries));
      expect(paths.first, '/storage/emulated/0/Music/HypeMuzik/1.m4a');
    });
  });

  group('finding downloads made before the ledger', () {
    late Directory folder;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('yt_sweep_test');
    });

    tearDown(() async {
      if (await folder.exists()) await folder.delete(recursive: true);
    });

    Future<File> write(String name, List<int> bytes) async {
      final file = File('${folder.path}/$name');
      await file.parent.create(recursive: true);
      return file.writeAsBytes([...bytes, ...List.filled(64, 0)]);
    }

    test('a DASH-branded MP4 is YouTube; an ordinary M4A is not', () async {
      expect(
        await YtDownloadRegistry.isYouTubeDash(
          await write('yt.m4a', _mp4Head('dash')),
        ),
        isTrue,
      );
      expect(
        await YtDownloadRegistry.isYouTubeDash(
          await write('itunes.m4a', _mp4Head('M4A ')),
        ),
        isFalse,
      );
      final tiny = File('${folder.path}/tiny.m4a')..writeAsBytesSync([0, 1]);
      expect(await YtDownloadRegistry.isYouTubeDash(tiny), isFalse);
      expect(
        await YtDownloadRegistry.isYouTubeDash(File('${folder.path}/none')),
        isFalse,
      );
    });

    test(
      'the sweep records only DASH .m4a files directly in the folder',
      () async {
        final yt = await write('Artist - Song.m4a', _mp4Head('dash'));
        await write('Mine.m4a', _mp4Head('M4A '));
        await write('Odd.mp3', _mp4Head('dash'));
        await write('Filed/Away.m4a', _mp4Head('dash'));
        final r = registry(docs: null);

        expect(await r.sweep([folder, Directory('${folder.path}/missing')]), 1);
        expect(await r.paths(), [yt.path]);
        expect(await r.sweep([folder]), 0, reason: 'already known');
      },
    );
  });

  test('the shared-storage root comes from the app external directory', () {
    expect(
      YtDownloadRegistry.sharedStorageRoot(
        '/storage/emulated/0/Android/data/x.a.zix/files',
      ),
      '/storage/emulated/0',
    );
    expect(
      YtDownloadRegistry.sharedStorageRoot(
        '/storage/emulated/10/Android/data/x.a.zix/files',
      ),
      '/storage/emulated/10',
    );
    expect(YtDownloadRegistry.sharedStorageRoot('/data/user/0/files'), isNull);
  });

  group('excluded prefixes', () {
    test('directories end in exactly one slash', () {
      expect(asDirectoryPrefix('/tmp/hype_video'), '/tmp/hype_video/');
      expect(asDirectoryPrefix('/tmp/hype_video/'), '/tmp/hype_video/');
    });

    test('are de-duplicated in order, and untouched on Android', () {
      expect(
        expandExcludedPrefixes([
          '/data/user/0/x.a.zix/cache/hype_video/',
          '/storage/emulated/0/Music/HypeMuzik/a.m4a',
          '/data/user/0/x.a.zix/cache/hype_video/',
          '',
        ], isIOS: false),
        [
          '/data/user/0/x.a.zix/cache/hype_video/',
          '/storage/emulated/0/Music/HypeMuzik/a.m4a',
        ],
      );
    });

    test('carry both spellings of an iOS container path', () {
      expect(
        expandExcludedPrefixes([
          '$_docsA/Music/YouTube/',
          '/private$_docsB/Music/b.m4a',
        ], isIOS: true),
        [
          '$_docsA/Music/YouTube/',
          '/private$_docsA/Music/YouTube/',
          '/private$_docsB/Music/b.m4a',
          '$_docsB/Music/b.m4a',
        ],
      );
    });
  });
}
