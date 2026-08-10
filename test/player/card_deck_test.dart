/// The card deck as a follower of whatever track is playing.
///
/// The behaviour under test is the one the old deck could not have: it moved
/// only when something remembered to tell it to, so a crossfade (which advances
/// the index seconds before the track ends), gapless playback (which advances
/// it through a different stream) and the previous button (which did not tell it
/// at all) each teleported. None of those are simulated here as *causes* —
/// that is the point. They are all just `currentSongId` changing underneath the
/// widget, so one test covers every one of them, including the ones nobody has
/// written yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eq_app/player/swipe_animation.dart';

/// Rebuildable host so a test can move `currentSongId` from outside, the way
/// the real controller does.
class _Host extends StatefulWidget {
  final int itemCount;
  final void Function(int)? onPageChanged;
  const _Host({super.key, required this.itemCount, this.onPageChanged});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int songId = 0;

  void moveTo(int id) => setState(() => songId = id);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: AnimatedPlayerCard(
            itemCount: widget.itemCount,
            currentSongId: songId,
            onPageChanged: (page) {
              widget.onPageChanged?.call(page);
              moveTo(page);
            },
            itemBuilder: (context, index, {bool isActive = false}) =>
                Center(child: Text('track $index')),
          ),
        ),
      ),
    );
  }
}

void main() {
  group('following an index that moved elsewhere', () {
    testWidgets('advances a card when something else moves it forward',
        (tester) async {
      var pageChangedCalls = 0;
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        _Host(
          key: key,
          itemCount: 10,
          onPageChanged: (_) => pageChangedCalls++,
        ),
      );
      expect(find.text('track 0'), findsOneWidget);

      // A crossfade starting, a gapless track ending, the notification's next
      // button — all of them look exactly like this.
      key.currentState!.moveTo(1);
      await tester.pump();

      // It animates rather than jumping: mid-flight both cards are on screen.
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('track 0'), findsOneWidget,
          reason: 'the outgoing card should still be in the air');

      await tester.pumpAndSettle();
      expect(find.text('track 0'), findsNothing);
      expect(find.text('track 1'), findsOneWidget);

      expect(pageChangedCalls, 0,
          reason: 'the deck did not cause this move and must not echo it back');
    });

    testWidgets('brings the previous card back when moved backward',
        (tester) async {
      var pageChangedCalls = 0;
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        _Host(
          key: key,
          itemCount: 10,
          onPageChanged: (_) => pageChangedCalls++,
        ),
      );

      key.currentState!.moveTo(4);
      await tester.pumpAndSettle();
      expect(find.text('track 4'), findsOneWidget);

      // The previous button.
      key.currentState!.moveTo(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('track 3'), findsOneWidget,
          reason: 'the returning card should be on screen while it travels');

      await tester.pumpAndSettle();
      expect(find.text('track 3'), findsOneWidget);
      expect(pageChangedCalls, 0);
    });

    testWidgets('a jump of many tracks lands on the right one', (tester) async {
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(_Host(key: key, itemCount: 60));

      key.currentState!.moveTo(41);
      await tester.pumpAndSettle();

      expect(find.text('track 41'), findsOneWidget);
      expect(find.text('track 0'), findsNothing);
    });

    testWidgets('a repeat-all wrap throws a card instead of dissolving',
        (tester) async {
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(_Host(key: key, itemCount: 8));

      key.currentState!.moveTo(7);
      await tester.pumpAndSettle();

      // next() under repeat-all sets the index straight to 0.
      key.currentState!.moveTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // Mid-flight the card being wrapped to is already behind the one
      // leaving, rather than the thrown card flying off over an empty deck.
      expect(find.text('track 7'), findsOneWidget);
      expect(find.text('track 0'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('track 0'), findsOneWidget);
      expect(find.text('track 7'), findsNothing);
    });

    testWidgets('a second move arriving mid-flight is still honoured',
        (tester) async {
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(_Host(key: key, itemCount: 10));

      key.currentState!.moveTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      // Track ends while the previous card is still travelling.
      key.currentState!.moveTo(2);
      await tester.pumpAndSettle();

      expect(find.text('track 2'), findsOneWidget,
          reason: 'the deck must not strand itself a card behind');
    });
  });

  group('the user moving the deck', () {
    testWidgets('a fling forward reports the move exactly once',
        (tester) async {
      final moves = <int>[];
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        _Host(key: key, itemCount: 10, onPageChanged: moves.add),
      );

      await tester.fling(find.byType(AnimatedPlayerCard), const Offset(320, 0), 1600);
      await tester.pumpAndSettle();

      expect(moves, [1], reason: 'one gesture is one track, reported once');
      expect(find.text('track 1'), findsOneWidget);
    });

    testWidgets('a fling backward goes back', (tester) async {
      final moves = <int>[];
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        _Host(key: key, itemCount: 10, onPageChanged: moves.add),
      );
      key.currentState!.moveTo(5);
      await tester.pumpAndSettle();

      await tester.fling(
          find.byType(AnimatedPlayerCard), const Offset(-320, 0), 1600);
      await tester.pumpAndSettle();

      expect(moves, [4]);
      expect(find.text('track 4'), findsOneWidget);
    });

    testWidgets('a small drag returns the card and changes nothing',
        (tester) async {
      final moves = <int>[];
      await tester.pumpWidget(
        _Host(itemCount: 10, onPageChanged: moves.add),
      );

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(AnimatedPlayerCard)));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(moves, isEmpty);
      expect(find.text('track 0'), findsOneWidget);
    });

    testWidgets('the end of the queue refuses to advance', (tester) async {
      final moves = <int>[];
      final key = GlobalKey<_HostState>();
      await tester.pumpWidget(
        _Host(key: key, itemCount: 3, onPageChanged: moves.add),
      );
      key.currentState!.moveTo(2);
      await tester.pumpAndSettle();

      await tester.fling(
          find.byType(AnimatedPlayerCard), const Offset(320, 0), 2000);
      await tester.pumpAndSettle();

      expect(moves, isEmpty);
      expect(find.text('track 2'), findsOneWidget);
    });

    testWidgets('the start of the queue refuses to go back', (tester) async {
      final moves = <int>[];
      await tester.pumpWidget(
        _Host(itemCount: 3, onPageChanged: moves.add),
      );

      await tester.fling(
          find.byType(AnimatedPlayerCard), const Offset(-320, 0), 2000);
      await tester.pumpAndSettle();

      expect(moves, isEmpty);
      expect(find.text('track 0'), findsOneWidget);
    });
  });

  group('speed matters', () {
    testWidgets('a hard flick leaves sooner than a gentle push', (tester) async {
      Future<int> framesToSettle(double velocity) async {
        final key = GlobalKey<_HostState>();
        await tester.pumpWidget(_Host(key: key, itemCount: 10));
        await tester.fling(
            find.byType(AnimatedPlayerCard), const Offset(200, 0), velocity);

        var frames = 0;
        while (find.text('track 0').evaluate().isNotEmpty && frames < 400) {
          await tester.pump(const Duration(milliseconds: 8));
          frames++;
        }
        await tester.pumpAndSettle();
        return frames;
      }

      final fast = await framesToSettle(6000);
      final slow = await framesToSettle(700);

      // The old deck ran a fixed 380ms curve, so these were identical. That
      // equality was the whole "doesn't feel like a real card" complaint.
      expect(fast, lessThan(slow));
    });
  });
}
