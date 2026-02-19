import 'dart:math';

import 'package:flutter/material.dart';

class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  const SeekBar({
    Key? key,
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
  }) : super(key: key);

  @override
  SeekBarState createState() => SeekBarState();
}

class SeekBarState extends State<SeekBar> {
  static final RegExp _durationRegex =
      RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$');
  double? _dragValue;
  late SliderThemeData _sliderThemeData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _sliderThemeData = SliderTheme.of(context).copyWith(
      trackHeight: 2.0,
    );
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
              value: min(widget.bufferedPosition.inMilliseconds.toDouble(),
                  widget.duration.inMilliseconds.toDouble()),
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
            value: min(_dragValue ?? widget.position.inMilliseconds.toDouble(),
                widget.duration.inMilliseconds.toDouble()),
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
                    _durationRegex
                            .firstMatch("${widget.position}")
                            ?.group(1) ??
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
            )),
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
              Text('${snapshot.data?.toStringAsFixed(1)}$valueSuffix',
                  style: const TextStyle(
                      fontFamily: 'Fixed',
                      fontWeight: FontWeight.bold,
                      fontSize: 24.0)),
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
  final int barCount;
  final double barWidth;
  final double barSpacing;
  final double height;

  const WaveformSeekBar({
    Key? key,
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
    this.activeColor = const Color(0xFFD4A825),
    this.inactiveColor = const Color(0x55FFFFFF),
    this.barCount = 60,
    this.barWidth = 2.5,
    this.barSpacing = 1.5,
    this.height = 48,
  }) : super(key: key);

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  static final RegExp _durationRegex =
      RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$');

  List<double> _barHeights = [];
  double? _dragProgress;
  int? _lastSeedHash;

  @override
  void didUpdateWidget(WaveformSeekBar old) {
    super.didUpdateWidget(old);
    // Regenerate waveform when the track changes (different duration)
    final newHash = widget.duration.inMilliseconds;
    if (_lastSeedHash != newHash) {
      _generateBars(newHash);
    }
  }

  void _generateBars(int seed) {
    _lastSeedHash = seed;
    final rng = Random(seed);
    _barHeights = List.generate(widget.barCount, (_) {
      // Mix of short and tall bars for an organic waveform look
      final base = 0.15 + rng.nextDouble() * 0.85;
      // Occasional tall spikes
      return rng.nextDouble() > 0.7 ? min(base * 1.3, 1.0) : base;
    });
  }

  double _progressFromPosition(Offset local, double totalWidth) {
    return (local.dx / totalWidth).clamp(0.0, 1.0);
  }

  void _handleDrag(Offset local, double totalWidth) {
    final progress = _progressFromPosition(local, totalWidth);
    setState(() => _dragProgress = progress);
    final ms = (progress * widget.duration.inMilliseconds).round();
    widget.onChanged?.call(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    if (_barHeights.isEmpty || _barHeights.length != widget.barCount) {
      _generateBars(widget.duration.inMilliseconds);
    }

    final progress = _dragProgress ??
        (widget.duration.inMilliseconds > 0
            ? widget.position.inMilliseconds / widget.duration.inMilliseconds
            : 0.0);

    final remaining = widget.duration - widget.position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) =>
                    _handleDrag(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _handleDrag(d.localPosition, constraints.maxWidth),
                onHorizontalDragEnd: (d) {
                  if (_dragProgress != null) {
                    final ms =
                        (_dragProgress! * widget.duration.inMilliseconds)
                            .round();
                    widget.onChangeEnd?.call(Duration(milliseconds: ms));
                  }
                  setState(() => _dragProgress = null);
                },
                onTapUp: (d) {
                  final p =
                      _progressFromPosition(d.localPosition, constraints.maxWidth);
                  final ms = (p * widget.duration.inMilliseconds).round();
                  widget.onChangeEnd?.call(Duration(milliseconds: ms));
                },
                child: SizedBox(
                  height: widget.height,
                  width: constraints.maxWidth,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      barHeights: _barHeights,
                      progress: progress.clamp(0.0, 1.0),
                      activeColor: widget.activeColor,
                      inactiveColor: widget.inactiveColor,
                      barWidth: widget.barWidth,
                      barSpacing: widget.barSpacing,
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
                style: Theme.of(context).textTheme.bodyMedium!.apply(
                      color: widget.activeColor,
                    ),
              ),
              Text(
                _durationRegex.firstMatch("$remaining")?.group(1) ?? '$remaining',
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

  _WaveformPainter({
    required this.barHeights,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.barWidth,
    required this.barSpacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty) return;

    final totalBarWidth = barWidth + barSpacing;
    final count = barHeights.length;
    // Center the waveform
    final totalWidth = count * totalBarWidth - barSpacing;
    final startX = (size.width - totalWidth) / 2;
    final midY = size.height / 2;
    final maxBarHeight = size.height * 0.9;
    final progressX = startX + progress * totalWidth;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final x = startX + i * totalBarWidth;
      final barH = barHeights[i] * maxBarHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, midY),
          width: barWidth,
          height: barH,
        ),
        Radius.circular(barWidth / 2),
      );

      // Bar center determines active/inactive
      final barCenter = x + barWidth / 2;
      canvas.drawRRect(rect, barCenter <= progressX ? activePaint : inactivePaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.barHeights != barHeights;
}
