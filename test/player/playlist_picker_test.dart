/// Adding the playing song to a playlist from the player: the playlists that
/// already hold it are ticked, choosing another adds it, and with none yet
/// the first is named in place — all against a real (in-memory) library.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:eq_app/data/library_database.dart';
import 'package:eq_app/data/library_repository.dart';
import 'package:eq_app/player/actions/song_action_pages.dart';

void main() {
  late LibraryDatabase db;
  late LibraryRepository repo;

  const song = PlaylistItem(
    source: 'youtube',
    externalId: 'efmvnvohSI4',
    title: 'Wilmer (feat. Bera)',
    artist: 'Patoranking',
  );

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() => db.close());

  Future<List<(String, bool)>> pump(WidgetTester tester) async {
    final added = <(String, bool)>[];
    await tester.pumpWidget(
      Provider<LibraryRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SingleChildScrollView(
              child: PlaylistPickerPage(
                item: song,
                onBack: () {},
                onAdded: (playlist, {required already}) =>
                    added.add((playlist.name, already)),
              ),
            ),
          ),
        ),
      ),
    );
    // The picker reads the library after its first frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    return added;
  }

  testWidgets('ticks what holds the song, adds it to what doesn\'t', (
    tester,
  ) async {
    late int road;
    await tester.runAsync(() async {
      final afro = await repo.createPlaylist('Afro', 1);
      road = await repo.createPlaylist('Road trip', 2);
      await repo.addToPlaylist(afro, [song], 3);
    });
    final added = await pump(tester);

    expect(find.text('Afro'), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.text('Road trip'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(added, [('Road trip', false)]);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    // An empty playlist that just got the song says so.
    expect(find.text('1 song'), findsNWidgets(2));
    final holding = await tester.runAsync(() => repo.playlistsHolding(song));
    expect(holding, contains(road));
  });

  testWidgets('choosing one that already has it says so, adds nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final afro = await repo.createPlaylist('Afro', 1);
      await repo.addToPlaylist(afro, [song], 2);
    });
    final added = await pump(tester);
    await tester.tap(find.text('Afro'));
    await tester.pumpAndSettle();
    expect(added, [('Afro', true)]);
    final entries = await tester.runAsync(() async {
      final lists = await repo.playlists();
      return repo.playlistEntries(lists.single.id);
    });
    expect(entries, hasLength(1));
  });

  testWidgets('with no playlists, the first is named in place', (tester) async {
    final added = await pump(tester);

    expect(find.textContaining('No playlists yet'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Sunday');
    await tester.pump();
    await tester.tap(find.text('Create'));
    // The library writes, then the pause that lets the tick be seen.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(added, [('Sunday', false)]);
    final lists = await tester.runAsync(repo.playlists);
    expect(lists!.single.name, 'Sunday');
    expect(lists.single.trackCount, 1);
  });
}
