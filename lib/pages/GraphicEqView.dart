import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import '../Helpers/Channel.dart';
import '../models/eq_models.dart';
import 'AudioFx.dart';

const Color _kAccent = Color(0xFFD4A825);
const double _kMinGain = -12.0;
const double _kMaxGain = 12.0;

class GraphicEqView extends StatefulWidget {
  const GraphicEqView({super.key});

  @override
  State<GraphicEqView> createState() => _GraphicEqViewState();
}

class _GraphicEqViewState extends State<GraphicEqView> {
  int _activeBand = -1;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final mapping = controller.currentBandMapping;
    final displayGains = controller.displayBandGains;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToggleRow(controller),
          const SizedBox(height: 12),
          _buildCurveSection(controller, displayGains, mapping),
          const SizedBox(height: 16),
          _buildBandSlidersSection(controller, displayGains, mapping),
          const SizedBox(height: 16),
          _buildPresetChips(controller),
          const SizedBox(height: 12),
          _buildSaveButton(context, controller),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Toggle switch row
  // ---------------------------------------------------------------------------

  Widget _buildToggleRow(AppController controller) {
    return FancyCard(
      isFancy: controller.isFancy,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            "Graphic EQ",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          Text(
            controller.activePresetName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _kAccent.withValues(alpha: 0.8),
                ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: controller.graphicEqEnabled,
            activeTrackColor: _kAccent,
            activeThumbColor: _kAccent,
            onChanged: (value) {
              controller.graphicEqEnabled = value;
              Channel.enableEq(value);
              Channel.enableDSPEngine(value);
              controller.enableDSP = value;
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Frequency response curve (CustomPainter)
  // ---------------------------------------------------------------------------

  Widget _buildCurveSection(
    AppController controller,
    List<double> gains,
    BandMapping mapping,
  ) {
    final screenH = MediaQuery.of(context).size.height;
    final curveHeight = (screenH * 0.22).clamp(120.0, 260.0);

    return FancyCard(
      isFancy: controller.isFancy,
      child: SizedBox(
        height: curveHeight,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _FrequencyCurvePainter(
              gains: gains,
              frequencies: mapping.frequencies,
              accent: _kAccent,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Variable-count band sliders (responsive)
  // ---------------------------------------------------------------------------

  Widget _buildBandSlidersSection(
    AppController controller,
    List<double> displayGains,
    BandMapping mapping,
  ) {
    final screenH = MediaQuery.of(context).size.height;
    final sliderHeight = (screenH * 0.26).clamp(140.0, 280.0);
    final bandCount = mapping.displayCount;
    final frequencies = mapping.frequencies;

    // Label visibility: all at <=10, every 2nd at 16, every 4th at 20+
    bool showLabel(int i) {
      if (bandCount <= 10) return true;
      if (bandCount <= 16) return i % 2 == 0 || i == bandCount - 1;
      return i % 4 == 0 || i == bandCount - 1;
    }

    return FancyCard(
      isFancy: controller.isFancy,
      child: SizedBox(
        height: sliderHeight + 40,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;

            // <=10 bands: fill width evenly, no scroll
            if (bandCount <= 10) {
              final bandWidth = availableWidth / bandCount;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(bandCount, (i) {
                  return _BandSlider(
                    frequency: frequencies[i],
                    gain: displayGains[i],
                    width: bandWidth,
                    height: sliderHeight,
                    isActive: _activeBand == i,
                    showLabel: showLabel(i),
                    onChanged: (value) {
                      controller.setDisplayBandGain(i, value);
                      controller.activePresetName = 'Custom';
                    },
                    onDragStart: () => setState(() => _activeBand = i),
                    onDragEnd: () => setState(() => _activeBand = -1),
                  );
                }),
              );
            }

            // >10 bands: fixed width per slider with horizontal scroll
            const fixedBandWidth = 38.0;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(bandCount, (i) {
                  return _BandSlider(
                    frequency: frequencies[i],
                    gain: displayGains[i],
                    width: fixedBandWidth,
                    height: sliderHeight,
                    isActive: _activeBand == i,
                    showLabel: showLabel(i),
                    onChanged: (value) {
                      controller.setDisplayBandGain(i, value);
                      controller.activePresetName = 'Custom';
                    },
                    onDragStart: () => setState(() => _activeBand = i),
                    onDragEnd: () => setState(() => _activeBand = -1),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Preset chips row
  // ---------------------------------------------------------------------------

  Widget _buildPresetChips(AppController controller) {
    final presetNames = BuiltInPresets.names;
    final savedNames = controller.savedPresets.keys
        .where((k) => !k.startsWith('_device_'))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            "Presets",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...presetNames.map((name) => _presetChip(name, controller)),
              ...savedNames.map((name) => _presetChip(name, controller, isUser: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _presetChip(String name, AppController controller, {bool isUser = false}) {
    final isSelected = controller.activePresetName == name;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(name),
        selected: isSelected,
        selectedColor: _kAccent.withValues(alpha: 0.25),
        labelStyle: TextStyle(
          color: isSelected ? _kAccent : Colors.white70,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        side: BorderSide(
          color: isSelected ? _kAccent : Colors.white24,
        ),
        backgroundColor: Colors.transparent,
        avatar: isUser
            ? Icon(Icons.person, size: 16, color: isSelected ? _kAccent : Colors.white38)
            : null,
        onSelected: (_) {
          if (isUser) {
            controller.loadPreset(name);
          } else {
            controller.applyBuiltInPreset(name);
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. Save button
  // ---------------------------------------------------------------------------

  Widget _buildSaveButton(BuildContext context, AppController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilledButton.icon(
        icon: const Icon(Icons.save_rounded, size: 20),
        label: const Text("Save as Preset"),
        style: FilledButton.styleFrom(
          backgroundColor: _kAccent.withValues(alpha: 0.15),
          foregroundColor: _kAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => _showSaveDialog(context, controller),
      ),
    );
  }

  void _showSaveDialog(BuildContext context, AppController controller) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Save Preset"),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Preset name",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                controller.savePreset(name);
                controller.activePresetName = name;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Preset "$name" saved'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(milliseconds: 1800),
                    backgroundColor: _kAccent,
                  ),
                );
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Band Slider Widget
// =============================================================================

class _BandSlider extends StatelessWidget {
  final double frequency;
  final double gain;
  final double width;
  final double height;
  final bool isActive;
  final bool showLabel;
  final ValueChanged<double> onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _BandSlider({
    required this.frequency,
    required this.gain,
    required this.width,
    required this.height,
    required this.isActive,
    required this.showLabel,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
  });

  String get _freqLabel {
    if (frequency >= 1000) {
      final k = frequency / 1000;
      return k == k.roundToDouble()
          ? '${k.round()}k'
          : '${k.toStringAsFixed(1)}k';
    }
    return frequency >= 100 ? '${frequency.round()}' : frequency.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final normalized = (gain - _kMinGain) / (_kMaxGain - _kMinGain);

    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isActive)
            Text(
              '${gain.toStringAsFixed(1)} dB',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: _kAccent,
              ),
            ),
          if (!isActive)
            const SizedBox(height: 14),

          SizedBox(
            height: height - 30,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: _kAccent,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: isActive ? _kAccent : Colors.white70,
                  overlayColor: _kAccent.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: normalized,
                  onChangeStart: (_) => onDragStart(),
                  onChanged: (v) {
                    final newGain =
                        _kMinGain + v * (_kMaxGain - _kMinGain);
                    final snapped = (newGain * 2).roundToDouble() / 2;
                    onChanged(snapped.clamp(_kMinGain, _kMaxGain));
                  },
                  onChangeEnd: (_) => onDragEnd(),
                ),
              ),
            ),
          ),

          SizedBox(
            height: 16,
            child: showLabel
                ? Text(
                    _freqLabel,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Frequency Response Curve Painter
// =============================================================================

class _FrequencyCurvePainter extends CustomPainter {
  final List<double> gains;
  final List<double> frequencies;
  final Color accent;

  _FrequencyCurvePainter({
    required this.gains,
    required this.frequencies,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty || gains.length != frequencies.length) return;

    const double padLeft = 32;
    const double padRight = 8;
    const double padTop = 12;
    const double padBottom = 20;

    final plotW = size.width - padLeft - padRight;
    final plotH = size.height - padTop - padBottom;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padLeft, padTop, plotW, plotH));

    _drawGrid(canvas, size, padLeft, padRight, padTop, padBottom, plotW, plotH);

    final points = <Offset>[];
    for (int i = 0; i < gains.length; i++) {
      final x = padLeft + _logNormalize(frequencies[i]) * plotW;
      final y = padTop + plotH * (1.0 - (gains[i] - _kMinGain) / (_kMaxGain - _kMinGain));
      points.add(Offset(x, y));
    }

    final curvePath = _catmullRomPath(points);

    final fillPath = Path.from(curvePath)
      ..lineTo(points.last.dx, padTop + plotH)
      ..lineTo(points.first.dx, padTop + plotH)
      ..close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, padTop),
        Offset(size.width / 2, padTop + plotH),
        [
          accent.withValues(alpha: 0.35),
          accent.withValues(alpha: 0.02),
        ],
      );
    canvas.drawPath(fillPath, fillPaint);

    final curvePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(curvePath, curvePaint);

    final dotPaint = Paint()..color = accent;
    for (final pt in points) {
      canvas.drawCircle(pt, 2.5, dotPaint);
    }

    canvas.restore();

    _drawAxisLabels(canvas, size, padLeft, padRight, padTop, padBottom, plotW, plotH);
  }

  static double _logNormalize(double freq) {
    const logMin = 1.3010299957; // log10(20)
    const logMax = 4.3010299957; // log10(20000)
    return (math.log(freq) / math.ln10 - logMin) / (logMax - logMin);
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double padLeft,
    double padRight,
    double padTop,
    double padBottom,
    double plotW,
    double plotH,
  ) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    for (final dB in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = padTop + plotH * (1.0 - (dB - _kMinGain) / (_kMaxGain - _kMinGain));
      _drawDashedLine(
        canvas,
        Offset(padLeft, y),
        Offset(padLeft + plotW, y),
        gridPaint,
        dashWidth: 4,
        gapWidth: 4,
      );
    }

    const freqGridLines = [100.0, 1000.0, 10000.0];
    for (final f in freqGridLines) {
      final x = padLeft + _logNormalize(f) * plotW;
      _drawDashedLine(
        canvas,
        Offset(x, padTop),
        Offset(x, padTop + plotH),
        gridPaint,
        dashWidth: 4,
        gapWidth: 4,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashWidth = 4,
    double gapWidth = 3,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final ux = dx / len;
    final uy = dy / len;

    double d = 0;
    while (d < len) {
      final segEnd = math.min(d + dashWidth, len);
      canvas.drawLine(
        Offset(start.dx + ux * d, start.dy + uy * d),
        Offset(start.dx + ux * segEnd, start.dy + uy * segEnd),
        paint,
      );
      d += dashWidth + gapWidth;
    }
  }

  void _drawAxisLabels(
    Canvas canvas,
    Size size,
    double padLeft,
    double padRight,
    double padTop,
    double padBottom,
    double plotW,
    double plotH,
  ) {
    final labelStyle = ui.TextStyle(
      color: Colors.white.withValues(alpha: 0.4),
      fontSize: 9,
    );

    for (final dB in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = padTop + plotH * (1.0 - (dB - _kMinGain) / (_kMaxGain - _kMinGain));
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.right,
        maxLines: 1,
      ))
        ..pushStyle(labelStyle)
        ..addText(dB >= 0 ? '+${dB.round()}' : '${dB.round()}');
      final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 26));
      canvas.drawParagraph(paragraph, Offset(2, y - paragraph.height / 2));
    }

    final freqLabels = <double, String>{100.0: '100', 1000.0: '1k', 10000.0: '10k'};
    for (final entry in freqLabels.entries) {
      final x = padLeft + _logNormalize(entry.key) * plotW;
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        maxLines: 1,
      ))
        ..pushStyle(labelStyle)
        ..addText(entry.value);
      final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 30));
      canvas.drawParagraph(paragraph, Offset(x - 15, padTop + plotH + 4));
    }
  }

  Path _catmullRomPath(List<Offset> points) {
    final path = Path();
    if (points.length < 2) return path;

    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

      const segments = 10;
      for (int s = 1; s <= segments; s++) {
        final t = s / segments;
        final tt = t * t;
        final ttt = tt * t;

        final x = 0.5 *
            ((2 * p1.dx) +
                (-p0.dx + p2.dx) * t +
                (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * tt +
                (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * ttt);
        final y = 0.5 *
            ((2 * p1.dy) +
                (-p0.dy + p2.dy) * t +
                (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * tt +
                (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * ttt);

        path.lineTo(x, y);
      }
    }

    return path;
  }

  @override
  bool shouldRepaint(covariant _FrequencyCurvePainter oldDelegate) {
    if (gains.length != oldDelegate.gains.length) return true;
    if (frequencies.length != oldDelegate.frequencies.length) return true;
    for (int i = 0; i < gains.length; i++) {
      if (gains[i] != oldDelegate.gains[i]) return true;
    }
    for (int i = 0; i < frequencies.length; i++) {
      if (frequencies[i] != oldDelegate.frequencies[i]) return true;
    }
    return accent != oldDelegate.accent;
  }
}
