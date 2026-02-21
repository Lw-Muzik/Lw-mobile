import 'dart:math';

import 'package:flutter/material.dart';

class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  const SeekBar({
    super.key,
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  SeekBarState createState() => SeekBarState();
}

class SeekBarState extends State<SeekBar> {
  static final RegExp _durationRegex = RegExp(
    r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$',
  );
  double? _dragValue;
  late SliderThemeData _sliderThemeData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _sliderThemeData = SliderTheme.of(context).copyWith(trackHeight: 2.0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SliderTheme(
          data: _sliderThemeData.copyWith(
            thumbShape: HiddenThumbComponentShape(),
            activeTrackColor: Colors.blue.shade100,
            inactiveTrackColor: Colors.grey.shade300,
          ),
          child: ExcludeSemantics(
            child: Slider(
              min: 0.0,
              max: widget.duration.inMilliseconds.toDouble(),
              value: min(
                widget.bufferedPosition.inMilliseconds.toDouble(),
                widget.duration.inMilliseconds.toDouble(),
              ),
              onChanged: (value) {
                setState(() {
                  _dragValue = value;
                });
                if (widget.onChanged != null) {
                  widget.onChanged!(Duration(milliseconds: value.round()));
                }
              },
              onChangeEnd: (value) {
                if (widget.onChangeEnd != null) {
                  widget.onChangeEnd!(Duration(milliseconds: value.round()));
                }
                _dragValue = null;
              },
            ),
          ),
        ),
        SliderTheme(
          data: _sliderThemeData.copyWith(
            inactiveTrackColor: Colors.transparent,
          ),
          child: Slider(
            min: 0.0,
            max: widget.duration.inMilliseconds.toDouble(),
            value: min(
              _dragValue ?? widget.position.inMilliseconds.toDouble(),
              widget.duration.inMilliseconds.toDouble(),
            ),
            onChanged: (value) {
              setState(() {
                _dragValue = value;
              });
              if (widget.onChanged != null) {
                widget.onChanged!(Duration(milliseconds: value.round()));
              }
            },
            onChangeEnd: (value) {
              if (widget.onChangeEnd != null) {
                widget.onChangeEnd!(Duration(milliseconds: value.round()));
              }
              _dragValue = null;
            },
          ),
        ),
        // Positioned(
        //   right: 16.0,
        //   bottom: 0.0,
        //   child: Text(
        //       RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
        //               .firstMatch("$_remaining")
        //               ?.group(1) ??
        //           '$_remaining',
        //       style: Theme.of(context).textTheme.bodySmall),
        // ),
        Positioned(
          right: 0.0,
          left: 0.0,
          bottom: -5.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _durationRegex.firstMatch("${widget.position}")?.group(1) ??
                      '- ${widget.position}',
                  style: Theme.of(context).textTheme.bodyMedium!.apply(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  "-${_durationRegex.firstMatch("$_remaining")?.group(1)}",
                  style: Theme.of(context).textTheme.bodyMedium!.apply(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Duration get _remaining => widget.duration - widget.position;
}

class HiddenThumbComponentShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.zero;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

void showSliderDialog({
  required BuildContext context,
  required String title,
  required int divisions,
  required double min,
  required double max,
  String valueSuffix = '',
  required double value,
  required Stream<double> stream,
  required ValueChanged<double> onChanged,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, textAlign: TextAlign.center),
      content: StreamBuilder<double>(
        stream: stream,
        builder: (context, snapshot) => SizedBox(
          height: 100.0,
          child: Column(
            children: [
              Text(
                '${snapshot.data?.toStringAsFixed(1)}$valueSuffix',
                style: const TextStyle(
                  fontFamily: 'Fixed',
                  fontWeight: FontWeight.bold,
                  fontSize: 24.0,
                ),
              ),
              Slider(
                divisions: divisions,
                min: min,
                max: max,
                value: snapshot.data ?? value,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

T? ambiguate<T>(T? value) => value;

// ---------------------------------------------------------------------------
// Waveform Seek Bar
// ---------------------------------------------------------------------------

class WaveformSeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;
  final Color activeColor;
  final Color inactiveColor;
  final double barWidth;
  final double minBarSpacing;
  final double height;
  final bool isPlaying;

  const WaveformSeekBar({
    Key? key,
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
    this.activeColor = const Color(0xFFD4A825),
    this.inactiveColor = const Color(0x55FFFFFF),
    this.barWidth = 6.5,
    this.minBarSpacing = 2.5,
    this.height = 85,
    this.isPlaying = true,
  }) : super(key: key);

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  static final RegExp _durationRegex = RegExp(
    r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$',
  );

  List<double> _barHeights = [];
  double? _dragProgress;
  double? _dragStartProgress;
  double? _dragStartX;
  int? _lastSeedHash;
  int _lastBarCount = 0;

  @override
  void didUpdateWidget(WaveformSeekBar old) {
    super.didUpdateWidget(old);
    final newHash = widget.duration.inMilliseconds;
    if (_lastSeedHash != newHash) {
      _generateBars(newHash, _lastBarCount);
    }
  }

  void _generateBars(int seed, int count) {
    if (count <= 0) return;
    _lastSeedHash = seed;
    _lastBarCount = count;
    final rng = Random(seed);
    _barHeights = List.generate(count, (_) {
      final base = 0.15 + rng.nextDouble() * 0.85;
      return rng.nextDouble() > 0.7 ? min(base * 1.3, 1.0) : base;
    });
  }

  double _currentProgress() {
    return _dragProgress ??
        (widget.duration.inMilliseconds > 0
            ? widget.position.inMilliseconds / widget.duration.inMilliseconds
            : 0.0);
  }

  double _totalWaveWidth(int barCount, double spacing) {
    final step = widget.barWidth + spacing;
    return barCount * step - spacing;
  }

  void _onDragStart(
    double localX,
    double widgetWidth,
    int barCount,
    double spacing,
  ) {
    // Capture baseline: the progress when drag began, and the finger start X.
    _dragStartProgress = _currentProgress();
    _dragStartX = localX;
    setState(() => _dragProgress = _dragStartProgress);
  }

  void _onDragUpdate(
    double localX,
    double widgetWidth,
    int barCount,
    double spacing,
  ) {
    if (_dragStartProgress == null || _dragStartX == null) return;
    final totalW = _totalWaveWidth(barCount, spacing);
    final delta = (_dragStartX! - localX) / totalW;
    final progress = (_dragStartProgress! + delta).clamp(0.0, 1.0);
    setState(() => _dragProgress = progress);
    final ms = (progress * widget.duration.inMilliseconds).round();
    widget.onChanged?.call(Duration(milliseconds: ms));
  }

  void _onDragEnd() {
    if (_dragProgress != null) {
      final ms = (_dragProgress! * widget.duration.inMilliseconds).round();
      widget.onChangeEnd?.call(Duration(milliseconds: ms));
    }
    setState(() {
      _dragProgress = null;
      _dragStartProgress = null;
      _dragStartX = null;
    });
  }

  void _onTapUp(
    double localX,
    double widgetWidth,
    int barCount,
    double spacing,
  ) {
    final totalW = _totalWaveWidth(barCount, spacing);
    final centerX = widgetWidth / 2;
    final cur = _currentProgress();
    final delta = (localX - centerX) / totalW;
    final progress = (cur + delta).clamp(0.0, 1.0);
    final ms = (progress * widget.duration.inMilliseconds).round();
    widget.onChangeEnd?.call(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _currentProgress();
    final remaining = widget.duration - widget.position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final availableW = constraints.maxWidth;
              final minUnit = widget.barWidth + widget.minBarSpacing;
              final barCount = (availableW / minUnit).floor().clamp(10, 200);
              final actualSpacing = barCount > 1
                  ? (availableW - barCount * widget.barWidth) / (barCount - 1)
                  : 0.0;

              if (_barHeights.length != barCount ||
                  _lastSeedHash != widget.duration.inMilliseconds) {
                _generateBars(widget.duration.inMilliseconds, barCount);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) => _onDragStart(
                  d.localPosition.dx,
                  availableW,
                  barCount,
                  actualSpacing,
                ),
                onHorizontalDragUpdate: (d) => _onDragUpdate(
                  d.localPosition.dx,
                  availableW,
                  barCount,
                  actualSpacing,
                ),
                onHorizontalDragEnd: (_) => _onDragEnd(),
                onTapUp: (d) => _onTapUp(
                  d.localPosition.dx,
                  availableW,
                  barCount,
                  actualSpacing,
                ),
                child: ClipRect(
                  child: SizedBox(
                    height: widget.height,
                    width: availableW,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        barHeights: _barHeights,
                        progress: progress.clamp(0.0, 1.0),
                        activeColor: widget.activeColor,
                        inactiveColor: widget.inactiveColor,
                        barWidth: widget.barWidth,
                        barSpacing: actualSpacing,
                        showPlayhead: widget.isPlaying || _dragProgress != null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _durationRegex.firstMatch("${widget.position}")?.group(1) ??
                    '${widget.position}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.apply(color: widget.activeColor),
              ),
              Text(
                _durationRegex.firstMatch("$remaining")?.group(1) ??
                    '$remaining',
                style: Theme.of(context).textTheme.bodyMedium!.apply(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> barHeights;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double barWidth;
  final double barSpacing;
  final bool showPlayhead;

  _WaveformPainter({
    required this.barHeights,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.barWidth,
    required this.barSpacing,
    required this.showPlayhead,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty) return;

    final count = barHeights.length;
    final step = barWidth + barSpacing;
    final totalWaveW = count * step - barSpacing;
    final centerX = size.width / 2;
    final midY = size.height / 2;
    final maxBarH = size.height * 0.9;
    final radius = Radius.circular(barWidth / 2);

    // Offset so the current-progress bar sits at centerX
    final offsetX = centerX - progress * totalWaveW;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final x = offsetX + i * step;
      // Skip bars outside the visible area
      if (x + barWidth < 0 || x > size.width) continue;

      final barH = barHeights[i] * maxBarH;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, midY),
          width: barWidth,
          height: barH,
        ),
        radius,
      );

      final barCenter = x + barWidth / 2;
      canvas.drawRRect(
        rect,
        barCenter <= centerX ? activePaint : inactivePaint,
      );
    }

    // --- Playhead (fixed at center) ---
    if (showPlayhead) {
      final top = 0.0;
      final bot = size.height;

      // Glow
      final glowPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.3)
        ..strokeWidth = 10.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawLine(Offset(centerX, top), Offset(centerX, bot), glowPaint);

      // Core line
      final linePaint = Paint()
        ..color = activeColor
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(centerX, top), Offset(centerX, bot), linePaint);

      // Dot caps
      final dotPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, top), 5.0, dotPaint);
      canvas.drawCircle(Offset(centerX, bot), 5.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.showPlayhead != showPlayhead ||
      old.barHeights != barHeights;
}
