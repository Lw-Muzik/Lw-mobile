import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/lyrics_model.dart';

/// One word of the active lyric line with the window it is sung in.
@immutable
class TimedWord {
  const TimedWord(this.text, this.startMs, this.endMs);
  final String text;
  final int startMs;
  final int endMs;

  @override
  bool operator ==(Object other) =>
      other is TimedWord &&
      other.text == text &&
      other.startMs == startMs &&
      other.endMs == endMs;

  @override
  int get hashCode => Object.hash(text, startMs, endMs);

  @override
  String toString() => 'TimedWord($text, $startMs, $endMs)';
}

/// Splits a synced line into timed words — port of the desktop's `timedWords`.
///
/// Uses real Enhanced-LRC word timing when the source has it; otherwise paces
/// the line's own words across its duration, weighted by length, so the fill
/// still tracks the music — the closest we can get to Apple's karaoke without
/// word data. [endMs] is the next line's start (else start + 4s).
List<TimedWord> timedWords(LyricLine line, {int? endMs}) {
  final start = line.timestamp?.inMilliseconds ?? 0;
  final end = endMs ?? start + 4000;
  final words = line.words;
  if (words != null && words.isNotEmpty) {
    return [
      for (var i = 0; i < words.length; i++)
        TimedWord(
          words[i].text,
          words[i].startTime.inMilliseconds,
          i + 1 < words.length ? words[i + 1].startTime.inMilliseconds : end,
        ),
    ];
  }
  final parts = line.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final totalChars = parts.fold<int>(0, (n, w) => n + w.length);
  if (totalChars == 0) return const [];
  final span = (end - start) < 400 ? 400 : end - start;
  var acc = start.toDouble();
  return [
    for (final w in parts)
      TimedWord(
        w,
        acc.round(),
        (acc += span * (w.length / totalChars)).round(),
      ),
  ];
}

/// The active lyric line, filled word by word in time with the music: sung
/// words solid, the current word sweeping left to right, upcoming words dim.
///
/// Inherits its text style from the surrounding [DefaultTextStyle] (the line's
/// animated style). Only the painter listens to [positionMs], so the fill
/// repaints each frame without rebuilding or relaying out anything.
class WordFillText extends StatefulWidget {
  const WordFillText({
    super.key,
    required this.words,
    required this.positionMs,
    this.dimAlpha = 0.28,
  });

  final List<TimedWord> words;

  /// Lyric-clock position (playback position + LRC offset), in ms.
  final ValueListenable<int> positionMs;

  final double dimAlpha;

  @override
  State<WordFillText> createState() => _WordFillTextState();
}

class _WordFillTextState extends State<WordFillText> {
  _Layout? _layout;

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  /// Lays the line out (dim + lit layers and each word's boxes), reusing the
  /// previous layout when nothing that affects it changed.
  _Layout _layoutFor(
    String text,
    TextStyle style,
    double maxWidth,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final key = (text, style, maxWidth, scaler, direction, widget.dimAlpha);
    final cached = _layout;
    if (cached != null && cached.key == key) return cached;
    cached?.dispose();

    final dim = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          color: Colors.white.withValues(alpha: widget.dimAlpha),
        ),
      ),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    final lit = TextPainter(
      text: TextSpan(
        text: text,
        // The glow lives on the dim layer; doubling it here would bloom.
        style: style.copyWith(color: Colors.white, shadows: const []),
      ),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);

    final boxes = <List<TextBox>>[];
    var at = 0;
    for (final w in widget.words) {
      boxes.add(
        lit.getBoxesForSelection(
          TextSelection(baseOffset: at, extentOffset: at + w.text.length),
        ),
      );
      at += w.text.length + 1;
    }
    return _layout = _Layout(key, dim, lit, boxes);
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final text = widget.words.map((w) => w.text).join(' ');
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Text(text, style: style.copyWith(color: Colors.white));
    }
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final l = _layoutFor(
          text,
          style,
          constraints.maxWidth,
          scaler,
          direction,
        );
        return Semantics(
          label: text,
          excludeSemantics: true,
          child: CustomPaint(
            size: Size(constraints.maxWidth, l.dim.height),
            painter: _WordFillPainter(
              dim: l.dim,
              lit: l.lit,
              words: widget.words,
              boxes: l.boxes,
              positionMs: widget.positionMs,
            ),
          ),
        );
      },
    );
  }
}

class _Layout {
  _Layout(this.key, this.dim, this.lit, this.boxes);
  final Object key;
  final TextPainter dim;
  final TextPainter lit;
  final List<List<TextBox>> boxes;

  void dispose() {
    dim.dispose();
    lit.dispose();
  }
}

class _WordFillPainter extends CustomPainter {
  _WordFillPainter({
    required this.dim,
    required this.lit,
    required this.words,
    required this.boxes,
    required this.positionMs,
  }) : super(repaint: positionMs);

  final TextPainter dim;
  final TextPainter lit;
  final List<TimedWord> words;
  final List<List<TextBox>> boxes;
  final ValueListenable<int> positionMs;

  @override
  void paint(Canvas canvas, Size size) {
    dim.paint(canvas, Offset.zero);

    final pos = positionMs.value;
    final filled = Path();
    var any = false;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (pos < w.startMs) break;
      final span = w.endMs - w.startMs;
      final p = pos >= w.endMs || span <= 0
          ? 1.0
          : (pos - w.startMs) / span;
      // A word can wrap across boxes; fill them in reading order.
      final wordBoxes = boxes[i];
      var remaining =
          wordBoxes.fold<double>(0, (n, b) => n + (b.right - b.left)) * p;
      for (final b in wordBoxes) {
        if (remaining <= 0) break;
        final width = (b.right - b.left).clamp(0.0, remaining);
        final rtl = b.direction == TextDirection.rtl;
        filled.addRect(
          Rect.fromLTRB(
            rtl ? b.right - width : b.left,
            b.top,
            rtl ? b.right : b.left + width,
            b.bottom,
          ),
        );
        remaining -= width;
        any = true;
      }
    }
    if (!any) return;
    canvas.save();
    canvas.clipPath(filled);
    lit.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WordFillPainter old) =>
      old.dim != dim ||
      old.lit != lit ||
      old.words != words ||
      old.positionMs != positionMs;
}
