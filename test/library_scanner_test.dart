import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/services/library_scanner.dart';

void main() {
  late LibraryDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  SongModel media(int id) => SongModel({
        '_id': id,
        '_data': '/music/$id.mp3',
        'title': 'Song $id',
        '_display_name': '$id.mp3',
        '_display_name_wo_ext': '$id',
        '_size': 1,
        'date_modified': 100,
        'is_music': true,
      });

  Future<void> seed(List<int> ids) => repo.upsertSongs([
        for (final id in ids)
          SongsCompanion.insert(
            id: Value(id),
            data: '/music/$id.mp3',
            playCount: const Value(7),
          ),
      ]);

  test('a failed media query keeps every row (and its play count)', () async {
    await seed([1, 2, 3]);
    final scanner = LibraryScanner(
      repo,
      querySongs: () async => throw PlatformException(
        code: 'on_audio_query',
        message: 'lateinit property context has not been initialized',
      ),
    );
    final phases = <ScanPhase>[];
    final sub = scanner.status.listen((s) => phases.add(s.phase));

    await scanner.scan();
    await Future<void>.delayed(Duration.zero);

    expect(await repo.songCount(), 3);
    final kept = await (db.select(db.songs)..where((t) => t.id.equals(2)))
        .getSingle();
    expect(kept.playCount, 7);
    expect(phases.last, ScanPhase.error);
    await sub.cancel();
  });

  test('a library that really is empty still removes the rows', () async {
    await seed([1, 2]);
    final scanner = LibraryScanner(repo, querySongs: () async => []);

    await scanner.scan();

    expect(await repo.songCount(), 0);
  });

  test('a scan after a failed one syncs normally', () async {
    await seed([1, 2]);
    var fail = true;
    final scanner = LibraryScanner(
      repo,
      querySongs: () async {
        if (fail) throw PlatformException(code: 'x');
        return [media(1), media(3)];
      },
    );

    await scanner.scan();
    expect(await repo.songCount(), 2);

    fail = false;
    await scanner.scan();
    final ids = (await db.select(db.songs).get()).map((r) => r.id).toSet();
    expect(ids, {1, 3});
  });
}
