import 'package:eq_app/Themes/app_fonts.dart';
import 'package:eq_app/player/lyrics_view.dart';
import 'package:eq_app/player/widgets/word_fill_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _tile({required bool current, bool words = false}) => MaterialApp(
      theme: ThemeData(fontFamily: AppFonts.body),
      home: Scaffold(
        body: LyricLineTile(
          text: 'Hello from the other side',
          isCurrent: current,
          alpha: 1,
          words: words
              ? const [TimedWord('Hello', 0, 500), TimedWord('there', 500, 900)]
              : null,
          lyricClockMs: ValueNotifier<int>(100),
          onTap: () {},
        ),
      ),
    );

void main() {
  testWidgets('a non-current line is Clash Display 500', (tester) async {
    await tester.pumpWidget(_tile(current: false));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Hello from the other side'));
    final style = DefaultTextStyle.of(tester.element(find.byWidget(text))).style;
    expect(style.fontFamily, AppFonts.display);
    expect(style.fontWeight, FontWeight.w500);
    expect(style.wordSpacing, closeTo(20 * 0.25, 1e-9));
  });

  testWidgets('the current line is Clash Display 600', (tester) async {
    await tester.pumpWidget(_tile(current: true));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Hello from the other side'));
    final style = DefaultTextStyle.of(tester.element(find.byWidget(text))).style;
    expect(style.fontFamily, AppFonts.display);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.wordSpacing, closeTo(28 * 0.25, 1e-9));
  });

  testWidgets('the word-fill path inherits Clash Display', (tester) async {
    await tester.pumpWidget(_tile(current: true, words: true));
    await tester.pumpAndSettle();
    final fill = find.byType(WordFillText);
    expect(fill, findsOneWidget);
    final style = DefaultTextStyle.of(tester.element(fill)).style;
    expect(style.fontFamily, AppFonts.display);
    expect(style.fontWeight, FontWeight.w600);
  });
}
