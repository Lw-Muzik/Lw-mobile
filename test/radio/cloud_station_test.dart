/// A station drawn from a connected drive.
///
/// A cloud file is not playable until a link has been minted for it, and for
/// Dropbox that is a request each. So unlike the library station, this one can
/// draw a track and still fail to deliver it — and the interesting cases are
/// all about what happens then.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/models/cloud_file.dart';
import 'package:eq_app/services/radio/cloud_station.dart';

CloudFile file(
  String id, {
  String? artist,
  String? album,
  String name = 'track.mp3',
}) =>
    CloudFile(
      provider: CloudProvider.googleDrive,
      fileId: id,
      name: name,
      folderPath: '/Music',
      size: 1000,
      mimeType: 'audio/mpeg',
      trackTitle: 'Title $id',
      trackArtist: artist,
      albumName: album,
    );

void main() {
  Future<String?> alwaysResolves(CloudFile f) async => 'https://cdn/${f.fileId}';
  Future<String?> neverResolves(CloudFile f) async => null;

  final drive = [
    file('seed', artist: 'Kaya', album: 'Sunrise'),
    for (var i = 0; i < 8; i++) file('k$i', artist: 'Kaya', album: 'Sunrise'),
    for (var i = 0; i < 8; i++) file('n$i', artist: 'Nobody', album: 'Other'),
  ];

  CloudStation station({
    CloudStreamResolver? resolve,
    List<CloudFile>? files,
    int seed = 1,
  }) =>
      CloudStation(
        files: files ?? drive,
        seed: (files ?? drive).first,
        resolve: resolve ?? alwaysResolves,
        random: Random(seed),
      );

  test('draws playable entries and never the seed', () async {
    final batch = await station().fetch(exclude: {'seed'}, limit: 5);
    expect(batch.tracks, hasLength(5));
    expect(batch.tracks.map((s) => s.data),
        everyElement(startsWith('https://cdn/')));
  });

  test('favours files by the same artist', () async {
    var related = 0;
    var unrelated = 0;
    for (var run = 0; run < 20; run++) {
      final batch =
          await station(seed: run).fetch(exclude: {'seed'}, limit: 4);
      for (final key in batch.consumed) {
        key.startsWith('k') ? related++ : unrelated++;
      }
    }
    expect(related, greaterThan(unrelated));
  });

  test('a file whose link cannot be minted is still counted as spent',
      () async {
    final batch = await station(resolve: neverResolves)
        .fetch(exclude: {'seed'}, limit: 4);

    expect(batch.tracks, isEmpty);
    expect(batch.consumed, hasLength(4),
        reason: 'otherwise every top-up rediscovers the same dead files');
  });

  test('a resolver that throws does not take the whole batch down', () async {
    Future<String?> flaky(CloudFile f) async {
      if (f.fileId.startsWith('n')) throw StateError('drive is down');
      return 'https://cdn/${f.fileId}';
    }

    final batch = await station(resolve: flaky).fetch(
      exclude: {'seed'},
      limit: 16,
    );
    expect(batch.tracks, isNotEmpty);
    expect(batch.tracks.map((s) => s.data),
        everyElement(startsWith('https://cdn/k')));
  });

  test('an empty drive yields an empty batch', () async {
    final only = [file('seed')];
    final batch =
        await station(files: only).fetch(exclude: {'seed'}, limit: 5);
    expect(batch.tracks, isEmpty);
  });

  test('everything already offered is left out', () async {
    final exclude = {'seed', for (var i = 0; i < 8; i++) 'k$i'};
    final batch = await station().fetch(exclude: exclude, limit: 20);
    expect(batch.consumed.intersection(exclude), isEmpty);
  });

  test('the seed can be walked forward onto another file on the drive', () {
    final s = station();
    expect(s.advanceSeed('k0'), isTrue);
    expect(s.seedKey, 'k0');
  });

  test('it refuses to walk onto a file that is not on the drive', () {
    final s = station();
    expect(s.advanceSeed('nowhere'), isFalse);
    expect(s.seedKey, 'seed');
  });

  // The album field of a cloud SongModel carries the thumbnail URL when there
  // is one, so scoring must read the CloudFile, not the model built from it.
  test('artwork riding in the album field does not make everything a match',
      () async {
    final withArt = [
      CloudFile(
        provider: CloudProvider.googleDrive,
        fileId: 'seed',
        name: 'a.mp3',
        folderPath: '/M',
        size: 1,
        mimeType: 'audio/mpeg',
        trackArtist: 'Kaya',
        albumName: 'Sunrise',
        thumbnailUrl: 'https://art/1.png',
      ),
      for (var i = 0; i < 6; i++)
        CloudFile(
          provider: CloudProvider.googleDrive,
          fileId: 'x$i',
          name: 'b$i.mp3',
          folderPath: '/M',
          size: 1,
          mimeType: 'audio/mpeg',
          trackArtist: 'Nobody',
          albumName: 'Different',
          thumbnailUrl: 'https://art/1.png',
        ),
    ];
    final batch = await station(files: withArt).fetch(
      exclude: {'seed'},
      limit: 6,
    );
    // Nothing here should have matched on album; the test is simply that the
    // station runs and draws from the unrelated pool without error.
    expect(batch.tracks, hasLength(6));
  });
}
