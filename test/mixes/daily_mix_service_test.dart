/// Feeding the mix engine from a real database.
///
/// The engine's own rules are tested in `daily_mixes_test.dart` with no
/// database at all. What is tested here is the wiring: that listening history
/// recorded through the repository actually reaches the engine, that the keys
/// the engine returns map back to playable tracks, and that a mix is built once
/// per daypart rather than on every read.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/data/streamed_track.dart';
import 'package:eq_app/models/cloud_file.dart';
import 'package:eq_app/services/mixes/daily_mix_service.dart';
import 'package:eq_app/services/mixes/daily_mixes.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

void main() {
  late LibraryDatabase db;
  late LibraryRepository repo;
  late DailyMixService service;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    service = DailyMixService(repo);
  });

  tearDown(() async => db.close());

  Future<void> insert(
    int id, {
    required String genre,
    required String artist,
    int duration = 200000,
  }) =>
      repo.upsertSongs([
        SongsCompanion.insert(
          id: Value(id),
          data: '/music/$id.mp3',
          title: Value('Track $id'),
          artist: Value(artist),
          genre: Value(genre),
          duration: Value(duration),
        ),
      ]);

  /// A cluster big and varied enough for the engine to accept as a taste.
  Future<void> insertTaste(String genre, int from, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await insert(from + i, genre: genre, artist: '$genre artist ${i % 5}');
    }
  }

  final afternoon = DateTime(2026, 8, 26, 14);
  final evening = DateTime(2026, 8, 26, 19);

  test('an empty library produces no mixes', () async {
    expect(await service.mixes(now: afternoon), isEmpty);
  });

  test('a library with one taste produces one mix of playable tracks',
      () async {
    await insertTaste('Afrobeat', 100, count: 30);

    final mixes = await service.mixes(now: afternoon);
    expect(mixes, hasLength(1));
    expect(mixes.single.descriptor, 'Afrobeat');
    expect(mixes.single.name, 'afrobeat afternoon');
    expect(mixes.single.tracks, isNotEmpty);
    // Local tracks come out ready to play; nothing else needs resolving here.
    expect(mixes.single.tracks.every((t) => t.isReady), isTrue);
    expect(mixes.single.tracks.every((t) => t.song!.data.isNotEmpty), isTrue);
    expect(mixes.single.hasRemote, isFalse);
  });

  test('two tastes produce two mixes', () async {
    await insertTaste('Afrobeat', 100, count: 20);
    await insertTaste('Soul', 200, count: 20);

    final mixes = await service.mixes(now: afternoon);
    expect(mixes.map((m) => m.descriptor).toSet(), {'Afrobeat', 'Soul'});
  });

  group('listening history reaches the engine', () {
    test('a skipped track is not treated as proven', () async {
      await insertTaste('Afrobeat', 100, count: 20);
      // Ten plays, all abandoned in the first few seconds.
      for (var i = 0; i < 10; i++) {
        await repo.recordPlayEvent(
          songId: 100,
          atSec: 1700000000 + i * 3600,
          msPlayed: 2000,
          completed: false,
        );
      }

      final stats = await repo.playStats();
      expect(stats[100]!.plays, 10);
      expect(stats[100]!.skips, 10,
          reason: '2s of a 200s track is a skip by any measure');
      expect(stats[100]!.isProven, isFalse);
    });

    test('a track played through is proven', () async {
      await insertTaste('Afrobeat', 100, count: 20);
      for (var i = 0; i < 5; i++) {
        await repo.recordPlayEvent(
          songId: 101,
          atSec: 1700000000 + i * 3600,
          msPlayed: 195000,
          completed: true,
        );
      }
      final stats = await repo.playStats();
      expect(stats[101]!.skips, 0);
      expect(stats[101]!.isProven, isTrue);
    });

    test('a track with no duration cannot be judged a skip', () async {
      await insert(300, genre: 'Afrobeat', artist: 'A', duration: 0);
      await repo.recordPlayEvent(
        songId: 300, atSec: 1700000000, msPlayed: 10, completed: false);
      final stats = await repo.playStats();
      expect(stats[300]!.skips, 0,
          reason: 'unknown length means the fraction is unknowable');
    });

    test('hours of the day are recorded per track', () async {
      await insert(400, genre: 'Afrobeat', artist: 'A');
      // 1700000000 is a fixed instant; the hour is whatever it is locally, but
      // it must be the same one every time and it must be recorded.
      await repo.recordPlayEvent(
        songId: 400, atSec: 1700000000, msPlayed: 190000, completed: true);
      final hours = await repo.playHours();
      expect(hours[400], hasLength(1));
      expect(hours[400]!.single, inInclusiveRange(0, 23));
    });
  });

  group('pruning', () {
    test('history older than the retention window is dropped', () async {
      await insert(500, genre: 'Afrobeat', artist: 'A');
      const now = 1700000000;
      await repo.recordPlayEvent(
        songId: 500,
        atSec: now - (kPlayEventRetentionDays + 5) * 86400,
        msPlayed: 190000,
        completed: true,
      );
      await repo.recordPlayEvent(
        songId: 500, atSec: now - 86400, msPlayed: 190000, completed: true);

      expect(await repo.playEventCount(), 2);
      await repo.prunePlayEvents(now);
      expect(await repo.playEventCount(), 1,
          reason: 'taste from three months ago is not taste today');
    });
  });

  group('caching', () {
    test('the same daypart returns the identical list', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final first = await service.mixes(now: afternoon);
      final second = await service.mixes(now: afternoon);
      expect(identical(first, second), isTrue,
          reason: 'rebuilding produces the same answer at the cost of three '
              'queries and a clustering pass');
    });

    test('a new daypart rebuilds', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final noon = await service.mixes(now: afternoon);
      final dusk = await service.mixes(now: evening);
      expect(identical(noon, dusk), isFalse);
      expect(dusk.single.name, 'afrobeat evening');
    });

    test('force rebuilds within the same daypart', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final first = await service.mixes(now: afternoon);
      final forced = await service.mixes(now: afternoon, force: true);
      expect(identical(first, forced), isFalse);
    });

    test('each launch (a new service) gets different mixes', () async {
      await insertTaste('Afrobeat', 100, count: 60);
      final launches = {
        for (var v = 0; v < 4; v++)
          (await DailyMixService(repo, variation: v).mixes(now: afternoon))
              .single
              .tracks
              .map((t) => t.song!.id)
              .join(','),
      };
      expect(launches.length, 4);
    });

    test('pull to refresh gives new tracks, not the same list again', () async {
      await insertTaste('Afrobeat', 100, count: 60);
      final service = DailyMixService(repo, variation: 1);
      final first = await service.mixes(now: afternoon);
      final forced = await service.mixes(now: afternoon, force: true);
      expect(service.variation, isNot(1));
      expect(
        forced.single.tracks.map((t) => t.song!.id),
        isNot(first.single.tracks.map((t) => t.song!.id)),
      );
    });

    test('reshuffle starts a new session', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final service = DailyMixService(repo, variation: 1);
      final first = await service.mixes(now: afternoon);
      service.reshuffle();
      final second = await service.mixes(now: afternoon);
      expect(identical(first, second), isFalse);
    });

    test('invalidate drops the cache, for after a library scan', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final first = await service.mixes(now: afternoon);
      service.invalidate();
      final second = await service.mixes(now: afternoon);
      expect(identical(first, second), isFalse);
    });
  });

  group('playlists', () {
    test('a playlist can be created, filled and read back', () async {
      final id = await repo.createPlaylist('Evening', 1700000000);
      await repo.addToPlaylist(
        id,
        const [
          PlaylistItem(source: 'local', songId: 1, title: 'One'),
          PlaylistItem(
              source: 'youtube', externalId: 'abc', title: 'Two',
              artist: 'Someone'),
        ],
        1700000000,
      );

      final entries = await repo.playlistEntries(id);
      expect(entries.map((e) => e.title), ['One', 'Two']);
      // The reason a playlist can hold this at all: MediaStore playlists cannot.
      expect(entries.last.source, 'youtube');
      expect(entries.last.externalId, 'abc');
    });

    test('a summary carries its track count', () async {
      final id = await repo.createPlaylist('Evening', 1700000000);
      await repo.addToPlaylist(
        id,
        const [PlaylistItem(source: 'local', songId: 1, title: 'One')],
        1700000000,
      );
      final all = await repo.playlists();
      expect(all.single.name, 'Evening');
      expect(all.single.trackCount, 1);
    });

    test('appending keeps positions contiguous', () async {
      final id = await repo.createPlaylist('P', 1);
      await repo.addToPlaylist(
        id, const [PlaylistItem(source: 'local', title: 'A')], 1);
      await repo.addToPlaylist(
        id, const [PlaylistItem(source: 'local', title: 'B')], 2);
      final entries = await repo.playlistEntries(id);
      expect(entries.map((e) => e.title), ['A', 'B']);
    });

    test('deleting a playlist takes its entries with it', () async {
      final id = await repo.createPlaylist('P', 1);
      await repo.addToPlaylist(
        id, const [PlaylistItem(source: 'local', title: 'A')], 1);
      await repo.deletePlaylist(id);
      expect(await repo.playlists(), isEmpty);
      expect(await repo.playlistEntries(id), isEmpty);
    });
  });

  group('blending a drive and YouTube in', () {
    CloudFile cloudFile(String id, String artist) => CloudFile(
          provider: CloudProvider.googleDrive,
          fileId: id,
          name: '$id.mp3',
          folderPath: '/M',
          size: 1,
          mimeType: 'audio/mpeg',
          trackTitle: 'Cloud $id',
          trackArtist: artist,
        );

    YtTrack ytTrack(String id) => YtTrack(
        videoId: id, title: 'YT $id', playlistId: '', playlistTitle: '');

    test('drive files matching a taste reach the mix', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final service = DailyMixService(
        repo,
        cloudLibrary: () => [for (var i = 0; i < 10; i++) cloudFile('c$i', 'Afrobeat')],
      );

      final mix = (await service.mixes(now: afternoon)).single;
      expect(mix.hasRemote, isTrue);
      expect(mix.tracks.any((t) => t.source == MixSource.cloud), isTrue);
    });

    test('YouTube tracks reach the mix', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final service = DailyMixService(
        repo,
        youTube: (_) async => [for (var i = 0; i < 10; i++) ytTrack('y$i')],
      );

      final mix = (await service.mixes(now: afternoon)).single;
      expect(mix.tracks.any((t) => t.source == MixSource.youtube), isTrue);
    });

    test("YouTube is asked only about tastes the library already has", () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final asked = <String>[];
      final service = DailyMixService(
        repo,
        youTube: (descriptor) async {
          asked.add(descriptor);
          return const [];
        },
      );
      await service.mixes(now: afternoon);
      expect(asked, ['Afrobeat'],
          reason: 'streaming may add variety inside a taste, never invent one');
    });

    // Offline is a normal state for this app.
    test('a YouTube failure costs the variety and nothing else', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final service = DailyMixService(
        repo,
        youTube: (_) async => throw StateError('offline'),
      );

      final mixes = await service.mixes(now: afternoon);
      expect(mixes, hasLength(1));
      expect(mixes.single.tracks, isNotEmpty);
      expect(mixes.single.hasRemote, isFalse);
    });

    test('no drive and no YouTube is simply a local mix', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final mixes = await DailyMixService(repo).mixes(now: afternoon);
      expect(mixes.single.hasRemote, isFalse);
    });

    test('the user\'s own music still holds the majority', () async {
      await insertTaste('Afrobeat', 100, count: 30);
      final service = DailyMixService(
        repo,
        cloudLibrary: () =>
            [for (var i = 0; i < 200; i++) cloudFile('c$i', 'Afrobeat')],
      );
      final mix = (await service.mixes(now: afternoon)).single;
      final remote =
          mix.tracks.where((t) => t.source != MixSource.local).length;
      expect(remote, lessThan(mix.length / 2));
    });

    group('YouTube radio follows what the user plays', () {
      ResolvedMix tasteMix(List<ResolvedMix> mixes) =>
          mixes.firstWhere((m) => m.descriptor == 'Afrobeat');
      Future<void> playThrough(int songId, int times) async {
        for (var i = 0; i < times; i++) {
          await repo.recordPlayEvent(
            songId: songId,
            atSec: 1700000000 + songId * 100 + i,
            msPlayed: 195000,
            completed: true,
          );
        }
      }

      YtTrack radioTrack(String id, {String? title, String? artist}) => YtTrack(
          videoId: id,
          title: title ?? 'Radio $id',
          artist: artist ?? 'Someone Else',
          playlistId: '',
          playlistTitle: '');

      test('the most-played songs of a mix seed its radio', () async {
        await insertTaste('Afrobeat', 100, count: 30);
        await playThrough(105, 6);
        await playThrough(110, 3);
        final seeds = <String>[];
        final service = DailyMixService(
          repo,
          youTubeRadio: (seed) async {
            seeds.add(seed.key);
            return [for (var i = 0; i < 20; i++) radioTrack('r${seed.key}-$i')];
          },
        );

        final mix = tasteMix(await service.mixes(now: afternoon));
        expect(seeds, containsAll(['105', '110']));
        final yt = mix.tracks.where((t) => t.source == MixSource.youtube);
        expect(yt, isNotEmpty);
        // Both seeds contribute, interleaved — not just the first one.
        final ids = yt.map((t) => t.track!.videoId).toList();
        expect(ids.any((id) => id.startsWith('r105')), isTrue);
        expect(ids.any((id) => id.startsWith('r110')), isTrue);
        expect(mix.length, greaterThanOrEqualTo(20),
            reason: 'a mix is a playlist, not a song');
      });

      test('radio picks by other artists still join the taste', () async {
        await insertTaste('Afrobeat', 100, count: 30);
        await playThrough(100, 4);
        final service = DailyMixService(
          repo,
          youTubeRadio: (_) async =>
              [for (var i = 0; i < 20; i++) radioTrack('r$i', artist: 'Artist $i')],
        );
        final mixes = await service.mixes(now: afternoon);
        expect(tasteMix(mixes).tracks.any((t) => t.source == MixSource.youtube), isTrue);
        // Anything besides the taste is a favourite's radio mix — opening with
        // the user's own song — never a cluster of streamed strangers.
        for (final mix in mixes.where((m) => m.descriptor != 'Afrobeat')) {
          expect(mix.tracks.first.source, MixSource.local);
          expect(mix.name, endsWith(' mix'));
        }
      });

      test('songs already on the phone are not streamed', () async {
        await insertTaste('Afrobeat', 100, count: 30);
        await playThrough(100, 4);
        final service = DailyMixService(
          repo,
          youTubeRadio: (_) async => [
            radioTrack('owned', title: 'Track 103 (Official Video)', artist: 'Afrobeat artist 3 - Topic'),
            for (var i = 0; i < 20; i++) radioTrack('r$i'),
          ],
        );
        final mix = tasteMix(await service.mixes(now: afternoon));
        expect(mix.tracks.any((t) => t.track?.videoId == 'owned'), isFalse);
      });

      test('no plays yet: the taste name is searched instead', () async {
        await insertTaste('Afrobeat', 100, count: 30);
        var radioCalls = 0;
        final asked = <String>[];
        final service = DailyMixService(
          repo,
          youTubeRadio: (_) async {
            radioCalls++;
            return const [];
          },
          youTube: (descriptor) async {
            asked.add(descriptor);
            return [for (var i = 0; i < 10; i++) ytTrack('y$i')];
          },
        );
        final mix = tasteMix(await service.mixes(now: afternoon));
        expect(radioCalls, 0);
        expect(asked, ['Afrobeat']);
        expect(mix.tracks.any((t) => t.source == MixSource.youtube), isTrue);
      });

      test('a full radio skips the name search', () async {
        await insertTaste('Afrobeat', 100, count: 30);
        await playThrough(100, 4);
        var searched = false;
        final service = DailyMixService(
          repo,
          youTubeRadio: (_) async => [for (var i = 0; i < 20; i++) radioTrack('r$i')],
          youTube: (_) async {
            searched = true;
            return const [];
          },
        );
        await service.mixes(now: afternoon);
        expect(searched, isFalse);
      });

      test('a radio failure falls back to the name search', () async {
        await insertTaste('Afrobeat', 100, count: 30);
        await playThrough(100, 4);
        final service = DailyMixService(
          repo,
          youTubeRadio: (_) async => throw StateError('offline'),
          youTube: (_) async => [for (var i = 0; i < 10; i++) ytTrack('y$i')],
        );
        final mix = tasteMix(await service.mixes(now: afternoon));
        expect(mix.tracks.any((t) => t.source == MixSource.youtube), isTrue);
      });
    });

    group('streamed listening counts as the user\'s own', () {
      var nextSec = 1700000000;
      Future<StreamedTrack> streamedPlay(
        String videoId, {
        required String artist,
        int plays = 2,
        bool skipped = false,
      }) async {
        final t = StreamedTrack(
          videoId: videoId,
          songId: videoId.hashCode.abs(),
          title: 'Song $videoId',
          artist: artist,
          durationMs: 200000,
          lastPlayedSec: nextSec,
        );
        await repo.rememberStreamed(t);
        for (var i = 0; i < plays; i++) {
          await repo.recordPlayEvent(
            songId: t.songId,
            atSec: nextSec++,
            msPlayed: skipped ? 3000 : 198000,
            completed: !skipped,
          );
        }
        return t;
      }

      YtTrack related(String id) => YtTrack(
          videoId: id, title: 'Related $id', artist: 'Other $id',
          playlistId: '', playlistTitle: '');

      test('the catalog round-trips and skips are judged by its durations', () async {
        await streamedPlay('a1', artist: 'Burna Boy', plays: 3);
        await streamedPlay('a2', artist: 'Burna Boy', plays: 2, skipped: true);
        final tracks = await repo.streamedTracks();
        expect(tracks.map((t) => t.videoId), unorderedEquals(['a1', 'a2']));
        final stats = await repo.playStatsFor({
          for (final t in tracks) t.songId: t.durationMs,
        });
        expect(stats['a1'.hashCode.abs()]!.skips, 0);
        expect(stats['a2'.hashCode.abs()]!.skips, 2);
      });

      test('nothing on the phone, only streaming: Home still gets mixes', () async {
        // Three songs by one artist form a taste; two others are one-offs.
        for (final id in ['b1', 'b2', 'b3']) {
          await streamedPlay(id, artist: 'Burna Boy');
        }
        await streamedPlay('c1', artist: 'Tems');
        await streamedPlay('d1', artist: 'Rema');
        final asked = <String?>[];
        final service = DailyMixService(
          repo,
          youTubeRadio: (seed) async {
            asked.add(seed.videoId);
            return [for (var i = 0; i < 30; i++) related('${seed.videoId}-$i')];
          },
        );
        final mixes = await service.mixes(now: afternoon);
        expect(mixes.length, greaterThanOrEqualTo(DailyMixService.minMixes));
        expect(mixes.map((m) => m.descriptor), contains('Burna Boy'));
        for (final mix in mixes) {
          expect(mix.length, greaterThanOrEqualTo(MixRules.minClusterSize),
              reason: 'every card is a playlist');
        }
        expect(asked, everyElement(isNotNull),
            reason: 'a streamed seed is radioed by its video id, no search');
      });

      test('one artist\'s favourites still give several mixes', () async {
        for (final id in ['g1', 'g2', 'g3', 'g4']) {
          await streamedPlay(id, artist: 'Burna Boy');
        }
        final service = DailyMixService(
          repo,
          youTubeRadio: (seed) async =>
              [for (var i = 0; i < 30; i++) related('${seed.videoId}-$i')],
        );
        final mixes = await service.mixes(now: afternoon);
        expect(mixes.length, DailyMixService.minMixes);
        final songRadios = mixes.where((m) => m.name.endsWith(' radio'));
        expect(songRadios, isNotEmpty,
            reason: 'artists ran out, so songs seed radios');
        expect(songRadios.every((m) => m.seededBySong), isTrue);
        expect(mixes.map((m) => m.name).toSet(), hasLength(mixes.length));
      });

      test('a radio mix opens with the favourite and never repeats it', () async {
        await streamedPlay('t1', artist: 'Tems', plays: 4);
        final service = DailyMixService(
          repo,
          youTubeRadio: (seed) async => [
            YtTrack(videoId: 't1', title: 'Song t1', artist: 'Tems',
                playlistId: '', playlistTitle: ''),
            for (var i = 0; i < 30; i++) related('x$i'),
          ],
        );
        final mix = (await service.mixes(now: afternoon)).first;
        expect(mix.name, 'tems mix');
        expect(mix.tracks.first.track!.videoId, 't1');
        expect(mix.tracks.where((t) => t.track?.videoId == 't1'), hasLength(1));
        expect(mix.length, MixRules.tracksPerMix);
      });

      test('streams the user skipped do not count as listening', () async {
        await streamedPlay('s1', artist: 'Skipped', plays: 3, skipped: true);
        var called = false;
        final service = DailyMixService(
          repo,
          youTubeRadio: (_) async {
            called = true;
            return const [];
          },
        );
        expect(await service.mixes(now: afternoon), isEmpty);
        expect(called, isFalse);
      });
    });
  });
}
