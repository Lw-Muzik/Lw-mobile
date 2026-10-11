/// Repairing old YouTube downloads: finding them by container, identifying
/// them on YouTube Music from name and length, and writing the tagged copies
/// back in batches — with the platform and network replaced by fakes.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/services/ytmusic/parse/yt_track_info.dart';
import 'package:eq_app/services/ytmusic/yt_download_repair.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';
import 'package:eq_app/services/ytmusic/yt_song_tags.dart';

List<int> _mp4(String brand) => [
  0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...brand.codeUnits, //
  ...List<int>.filled(64, 0),
];

ExploreItem _song(String id, String title, String artist, double? secs,
        {ExploreKind kind = ExploreKind.song}) =>
    ExploreItem(
      id: id,
      kind: kind,
      title: title,
      artist: artist,
      durationSecs: secs,
    );

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('yt_repair'));
  tearDown(() => dir.delete(recursive: true));

  group('findCandidates', () {
    test('only YouTube\'s streaming files, by their ftyp brand', () async {
      File('${dir.path}/Burna Boy - Last Last.m4a').writeAsBytesSync(_mp4('dash'));
      File('${dir.path}/Mine - Tagged.m4a').writeAsBytesSync(_mp4('M4A '));
      File('${dir.path}/Song.mp3').writeAsBytesSync(_mp4('dash'));
      final found = await YtDownloadRepair.findCandidates([
        (path: '${dir.path}/Burna Boy - Last Last.m4a', durationMs: 173000),
        (path: '${dir.path}/Mine - Tagged.m4a', durationMs: 1000),
        (path: '${dir.path}/Song.mp3', durationMs: 1000),
        (path: '${dir.path}/Missing.m4a', durationMs: 1000),
      ]);
      expect(found.map((c) => c.name), ['Burna Boy - Last Last']);
      expect(found.single.durationMs, 173000);
    });
  });

  test('splitFileName', () {
    expect(splitFileName('Burna Boy - Last Last'), ('Burna Boy', 'Last Last'));
    expect(
      splitFileName('21 Savage, Metro Boomin & Burna Boy - just like me'),
      ('21 Savage, Metro Boomin & Burna Boy', 'just like me'),
    );
    expect(splitFileName('RECORDING_20260630'), (null, 'RECORDING_20260630'));
  });

  group('matchScore', () {
    test('same length and title: a match', () {
      expect(
        matchScore(
          wantTitle: 'Last Last',
          wantArtist: 'Burna Boy',
          wantMs: 173000,
          item: _song('a', 'Last Last', 'Burna Boy', 172),
        ),
        greaterThanOrEqualTo(1.0),
      );
    });
    test('another length: not a match however the title reads', () {
      expect(
        matchScore(
          wantTitle: 'Last Last',
          wantArtist: 'Burna Boy',
          wantMs: 173000,
          item: _song('a', 'Last Last', 'Burna Boy', 210),
        ),
        0,
      );
    });
    test('another title: not a match', () {
      expect(
        matchScore(
          wantTitle: 'Last Last',
          wantArtist: 'Burna Boy',
          wantMs: 173000,
          item: _song('a', 'Ye', 'Burna Boy', 173),
        ),
        0,
      );
    });
    test('no length: title and artist must both agree', () {
      expect(
        matchScore(
          wantTitle: 'Last Last',
          wantArtist: 'Burna Boy',
          wantMs: null,
          item: _song('a', 'Last Last', 'Burna Boy', 173),
        ),
        greaterThanOrEqualTo(1.0),
      );
      expect(
        matchScore(
          wantTitle: 'Last Last',
          wantArtist: 'Burna Boy',
          wantMs: null,
          item: _song('a', 'Last Last', 'Someone Else', 173),
        ),
        lessThan(1.0),
      );
    });
  });

  group('identify', () {
    test('the closest song by length', () async {
      final repair = YtDownloadRepair(
        search: (q, f) async => [
          _song('wrong', 'Last Last (Remix)', 'Burna Boy', 199),
          _song('right', 'Last Last', 'Burna Boy', 172),
        ],
      );
      final track = await repair.identify(const YtRepairCandidate(
        path: '/x.m4a',
        name: 'Burna Boy - Last Last',
        durationMs: 173000,
      ));
      expect(track?.videoId, 'right');
    });

    test('falls back to videos when no song fits', () async {
      final filters = <SearchFilter>[];
      final repair = YtDownloadRepair(
        search: (q, f) async {
          filters.add(f);
          return f == SearchFilter.songs
              ? [_song('s', 'Sungba', 'Asake', 150)]
              : [
                  _song('v', 'Asake - Sungba (Remix) (Official Video)', 'Asake',
                      215, kind: ExploreKind.video),
                ];
        },
      );
      final track = await repair.identify(const YtRepairCandidate(
        path: '/x.m4a',
        name: 'Asake - Sungba (Remix) (Official Video) (feat. Burna Boy)',
        durationMs: 215000,
      ));
      expect(filters, [SearchFilter.songs, SearchFilter.videos]);
      expect(track?.videoId, 'v');
    });

    test('the same title and length by someone else is not this file',
        () async {
      // Seen on the test tablet: "Burna Boy - Pull Up" matched another
      // artist's "Pull Up" of the same length, and "Won da Mo" a stranger's
      // re-upload whose title mentions Burna Boy.
      final repair = YtDownloadRepair(
        search: (q, f) async => f == SearchFilter.songs
            ? [_song('other', 'Pull Up', 'Crimzfrm_east', 184)]
            : [
                _song('reupload', "Burna Boy Ft D'Banj - Won Da Mo (NEW 2013)",
                    'World Of Africa TV', 245, kind: ExploreKind.video),
              ],
      );
      expect(
        await repair.identify(const YtRepairCandidate(
          path: '/x.m4a',
          name: 'Burna Boy - Pull Up',
          durationMs: 184000,
        )),
        isNull,
      );
      expect(
        await repair.identify(const YtRepairCandidate(
          path: '/y.m4a',
          name: "Burna Boy - Won da Mo (feat. D'banj)",
          durationMs: 245000,
        )),
        isNull,
      );
    });

    test('a collaboration is credited however its names are ordered',
        () async {
      final repair = YtDownloadRepair(
        search: (q, f) async => [
          _song('song', 'GWAGWALADA', 'Bnxn, Kizz Daniel & Seyi Vibez', 189),
        ],
      );
      final track = await repair.identify(const YtRepairCandidate(
        path: '/x.m4a',
        name: 'Seyi Vibez, BNXN fka Buju & Kizz Daniel - GWAGWALADA',
        durationMs: 189000,
      ));
      expect(track?.videoId, 'song');
    });

    test('nothing close is nothing', () async {
      final repair = YtDownloadRepair(search: (q, f) async => []);
      expect(
        await repair.identify(const YtRepairCandidate(
          path: '/x.m4a',
          name: 'Unknown - Thing',
          durationMs: 1000,
        )),
        isNull,
      );
    });
  });

  group('run', () {
    test('tags, writes back in batches, skips what plays, adds .lrc files',
        () async {
      final paths = [
        for (final n in ['A - One', 'B - Two', 'C - Three', 'D - Four'])
          '${dir.path}/$n.m4a',
      ];
      for (final p in paths) {
        File(p).writeAsBytesSync(_mp4('dash'));
      }
      final work = Directory('${dir.path}/work');
      final replaced = <List<String>>[];
      final remembered = <String, String>{};
      final tagger = YtSongTagger(
        trackInfo: (id) async => YtTrackInfo(videoId: id, title: 'T $id', artist: 'Ar'),
        album: (id, title) async => null,
        ytLyrics: (id) async => null,
        lrclib: ({required title, required artist, durationMs}) async =>
            '[00:01.00]hello',
        fetch: (url) async => null,
      );
      final repair = YtDownloadRepair(
        tagger: tagger,
        search: (q, f) async => q.startsWith('C')
            ? [] // not on YouTube Music: named from its file
            : [_song('id_${q[0]}', q.substring(4), q[0], 100)],
        finish: (src, dst, tags) async {
          if (src.contains('Four')) return false; // can't be repackaged
          File(dst).writeAsStringSync('tagged ${tags['title']}');
          return true;
        },
        replace: (files) async {
          replaced.add([for (final f in files) f.path]);
          return {
            for (final f in files) f.path: true,
          };
        },
        workDir: () async => work,
        remember: (videoId, path) async => remembered[videoId] = path,
        batchSize: 1,
      );
      final progress = <int>[];
      final report = await repair.run(
        [
          for (final p in paths)
            YtRepairCandidate(
              path: p,
              name: p.split('/').last.replaceAll('.m4a', ''),
              durationMs: 100000,
            ),
        ],
        playingPath: paths[1],
        onProgress: (done, total, name) => progress.add(done),
      );
      expect(report.fixed, 2); // One and Three
      expect(report.fromFileName, 1); // Three
      expect(report.skipped, 1); // Two, playing
      expect(report.failed, 1); // Four
      expect(replaced, [
        [paths[0]],
        [paths[2]],
      ], reason: 'a batch of one per write');
      expect(File('${dir.path}/A - One.lrc').readAsStringSync(), contains('hello'));
      expect(File('${dir.path}/C - Three.lrc').existsSync(), isTrue);
      expect(File('${dir.path}/B - Two.lrc').existsSync(), isFalse);
      expect(work.listSync().whereType<File>(), isEmpty,
          reason: 'temp copies are cleaned up');
      expect(progress.last, 4);
      // Identified files are remembered as downloads of their track; the one
      // named from its file name has no track to be.
      expect(remembered, {'id_A': paths[0]});
    });
  });
}
