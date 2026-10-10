import 'package:eq_app/models/lyrics_model.dart';
import 'package:eq_app/player/widgets/word_fill_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timedWords', () {
    test('uses Enhanced-LRC word timing, last word ends at the line end', () {
      final data = parseLrc('[00:10.00]<00:10.00>Hello <00:10.50>from <00:11.20>here\n[00:13.00]next');
      final words = timedWords(data.lines.first, endMs: 13000);
      expect(words, const [
        TimedWord('Hello', 10000, 10500),
        TimedWord('from', 10500, 11200),
        TimedWord('here', 11200, 13000),
      ]);
    });

    test('synthesises timing weighted by word length across the line', () {
      final line = parseLrc('[00:02.00]aa bbbb').lines.first;
      final words = timedWords(line, endMs: 5000);
      expect(words.map((w) => w.text), ['aa', 'bbbb']);
      expect(words.first.startMs, 2000);
      expect(words.first.endMs, 3000); // 2 of 6 chars of a 3 s line
      expect(words.last.endMs, 5000);
    });

    test('defaults to a 4 s line and a 400 ms minimum span', () {
      final line = parseLrc('[00:01.00]solo').lines.first;
      expect(timedWords(line).single.endMs, 5000);
      expect(timedWords(line, endMs: 1100).single.endMs, 1400);
    });
  });

  group('activeLineIndex', () {
    final lines = parseLrc('[00:01.00]a\n[00:03.00]b\n[00:06.00]c').lines;
    test('finds the line being sung', () {
      expect(activeLineIndex(lines, const Duration(milliseconds: 500)), -1);
      expect(activeLineIndex(lines, const Duration(seconds: 1)), 0);
      expect(activeLineIndex(lines, const Duration(milliseconds: 4500)), 1);
      expect(activeLineIndex(lines, const Duration(minutes: 1)), 2);
    });
    test('skips trailing untimed lines', () {
      final mixed = [...lines, const LyricLine(text: 'untimed')];
      expect(activeLineIndex(mixed, const Duration(minutes: 1)), 2);
    });
  });

  group('WordFillText', () {
    const words = [
      TimedWord('Hello', 0, 500),
      TimedWord('from', 500, 1000),
      TimedWord('the', 1000, 1500),
      TimedWord('other', 1500, 2000),
      TimedWord('side', 2000, 2600),
    ];

    Widget host(ValueNotifier<int> clock, {bool reduceMotion = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: SizedBox(
                width: 160,
                child: DefaultTextStyle(
                  style: const TextStyle(fontSize: 28),
                  child: WordFillText(words: words, positionMs: clock),
                ),
              ),
            ),
          ),
        );

    testWidgets('paints, wraps, and repaints as the clock moves', (tester) async {
      final clock = ValueNotifier<int>(0);
      await tester.pumpWidget(host(clock));
      final paint = find.descendant(
        of: find.byType(WordFillText),
        matching: find.byType(CustomPaint),
      );
      expect(paint, findsOneWidget);
      // 160 px at 28 pt can't hold the line on one row: it wrapped.
      expect(tester.getSize(paint).height, greaterThan(40));
      expect(find.bySemanticsLabel('Hello from the other side'), findsOneWidget);

      for (final ms in [250, 1250, 2600, 9000]) {
        clock.value = ms;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      clock.dispose();
    });

    testWidgets('reduced motion shows the plain line', (tester) async {
      final clock = ValueNotifier<int>(0);
      await tester.pumpWidget(host(clock, reduceMotion: true));
      expect(find.text('Hello from the other side'), findsOneWidget);
      clock.dispose();
    });
  });
}
