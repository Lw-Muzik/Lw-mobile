/// A collaboration's "Go to artists": each credited artist listed, the one
/// tapped is the one opened, and one being looked up shows it is working.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/actions/song_action_pages.dart';
import 'package:eq_app/services/ytmusic/yt_models.dart';

void main() {
  testWidgets('lists every artist and opens the one chosen', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistPickerPage(
            artists: const [
              YtArtistRef('Burna Boy', id: 'UCburna'),
              YtArtistRef('Ed Sheeran', id: 'UCed'),
            ],
            busy: 'Ed Sheeran',
            onBack: () {},
            onPick: (artist) => picked.add(artist.name),
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the spinner never settles.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Burna Boy'), findsOneWidget);
    expect(find.text('Ed Sheeran'), findsOneWidget);
    // The one being looked up shows a spinner and waits.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Burna Boy'));
    await tester.tap(find.text('Ed Sheeran'));
    expect(picked, ['Burna Boy']);
  });
}
