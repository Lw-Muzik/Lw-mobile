import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import '../Helpers/Channel.dart';
import '../models/eq_models.dart';
import 'audio_fx.dart';

const Color _kAccent = Color(0xFFD4A825);
const double _kMinGain = -15.0;
const double _kMaxGain = 15.0;

class GraphicEqView extends StatefulWidget {
  const GraphicEqView({super.key});

  @override
  State<GraphicEqView> createState() => _GraphicEqViewState();
}

class _GraphicEqViewState extends State<GraphicEqView> {
  int _activeBand = -1;
  int _curveDragBand = -1;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final mapping = controller.currentBandMapping;
    final displayGains = controller.displayBandGains;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderRow(controller),
          const SizedBox(height: 8),
          Expanded(
            child: FancyCard(
              isFancy: controller.isFancy,
              child: Column(
                children: [
                  _buildPreampRow(controller),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Container(
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _buildCurve(controller, displayGains, mapping),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    flex: 4,
                    child: _buildBandSliders(
                      controller,
                      displayGains,
                      mapping,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildPresetsRow(controller),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Header: power, title, flatten, band count
  // ---------------------------------------------------------------------------

  Widget _buildHeaderRow(AppController controller) {
    return Row(
      children: [
        _EqPowerButton(
          enabled: controller.graphicEqEnabled,
          onToggle: () {
            final newValue = !controller.graphicEqEnabled;
            controller.graphicEqEnabled = newValue;
            Channel.enableEq(newValue);
          },
        ),
        const SizedBox(width: 10),
        Text(
          "Graphic EQ",
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        // Flatten all bands to 0 dB
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.restart_alt_rounded,
              size: 19,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            tooltip: "Flatten bands",
            onPressed: () {
              final gains = controller.displayBandGains;
              for (int i = 0; i < gains.length; i++) {
                controller.setDisplayBandGain(i, 0.0);
              }
              controller.activePresetName = 'Flat';
            },
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: controller.eqBandCount,
              isDense: true,
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              items: BandMapping.supportedCounts
                  .map(
                    (c) => DropdownMenuItem(value: c, child: Text('$c bands')),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) controller.eqBandCount = v;
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreampRow(AppController controller) {
    return Row(
      children: [
        Icon(
          Icons.volume_up_rounded,
          size: 16,
          color: _kAccent.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Text(
          "Pre",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: _kAccent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
              thumbColor: _kAccent,
              overlayColor: _kAccent.withValues(alpha: 0.08),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: controller.preampGain,
              min: -15,
              max: 15,
              onChanged: (v) => controller.preampGain = v,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${controller.preampGain >= 0 ? "+" : ""}${controller.preampGain.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: controller.preampGain.abs() > 0.05
                  ? _kAccent
                  : Colors.white.withValues(alpha: 0.35),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Curve (inside EQ surface — no card wrapper)
  // ---------------------------------------------------------------------------

  Widget _buildCurve(
    AppController controller,
    List<double> gains,
    BandMapping mapping,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return GestureDetector(
          onPanStart: (details) {
            _curveDragBand = _findNearestBand(
              details.localPosition,
              gains,
              mapping.frequencies,
              width,
              height,
            );
            if (_curveDragBand >= 0) {
              _updateBandFromCurve(
                controller,
                _curveDragBand,
                details.localPosition,
                height,
              );
            }
          },
          onPanUpdate: (details) {
            if (_curveDragBand >= 0) {
              _updateBandFromCurve(
                controller,
                _curveDragBand,
                details.localPosition,
                height,
              );
            }
          },
          onPanEnd: (_) => _curveDragBand = -1,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _FrequencyCurvePainter(
                gains: gains,
                frequencies: mapping.frequencies,
                accent: _kAccent,
                activeBand: _curveDragBand,
              ),
              size: Size(width, height),
            ),
          ),
        );
      },
    );
  }

  int _findNearestBand(
    Offset pos,
    List<double> gains,
    List<double> frequencies,
    double width,
    double height,
  ) {
    const padLeft = 32.0;
    const padRight = 8.0;
    final plotW = width - padLeft - padRight;

    double bestDist = 40.0;
    int bestBand = -1;

    for (int i = 0; i < gains.length; i++) {
      final x =
          padLeft +
          _FrequencyCurvePainter._logNormalize(frequencies[i]) * plotW;
      final dist = (pos.dx - x).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestBand = i;
      }
    }
    return bestBand;
  }

  void _updateBandFromCurve(
    AppController controller,
    int band,
    Offset pos,
    double height,
  ) {
    const padTop = 12.0;
    const padBottom = 20.0;
    final plotH = height - padTop - padBottom;
    final normY = ((pos.dy - padTop) / plotH).clamp(0.0, 1.0);
    final gain = _kMaxGain - normY * (_kMaxGain - _kMinGain);
    final rounded = (gain * 10).roundToDouble() / 10;
    controller.setDisplayBandGain(band, rounded.clamp(_kMinGain, _kMaxGain));
    controller.activePresetName = 'Custom';
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Band sliders (inside EQ surface — no card wrapper)
  // ---------------------------------------------------------------------------

  Widget _buildBandSliders(
    AppController controller,
    List<double> displayGains,
    BandMapping mapping,
  ) {
    final bandCount = mapping.displayCount;
    final frequencies = mapping.frequencies;

    bool showLabel(int i) {
      if (bandCount <= 10) return true;
      if (bandCount <= 16) return i % 2 == 0 || i == bandCount - 1;
      return i % 4 == 0 || i == bandCount - 1;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        if (bandCount <= 10) {
          final bandWidth = availableWidth / bandCount;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(bandCount, (i) {
              return _BandSlider(
                frequency: frequencies[i],
                gain: displayGains[i],
                width: bandWidth,
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
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Presets with integrated save
  // ---------------------------------------------------------------------------

  Widget _buildPresetsRow(AppController controller) {
    final presetNames = BuiltInPresets.names;
    final savedNames = controller.savedPresets.keys
        .where((k) => !k.startsWith('_device_'))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            "Presets",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...presetNames.map((name) => _presetChip(name, controller)),
              ...savedNames.map(
                (name) => _presetChip(name, controller, isUser: true),
              ),
              // Inline save action
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: ActionChip(
                  avatar: Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  label: Text(
                    "Save",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  onPressed: () => _showSaveDialog(context, controller),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _presetChip(
    String name,
    AppController controller, {
    bool isUser = false,
  }) {
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
          fontSize: 12,
        ),
        side: BorderSide(color: isSelected ? _kAccent : Colors.white24),
        backgroundColor: Colors.transparent,
        visualDensity: VisualDensity.compact,
        avatar: isUser
            ? Icon(
                Icons.person,
                size: 16,
                color: isSelected ? _kAccent : Colors.white38,
              )
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
  // Save dialog
  // ---------------------------------------------------------------------------

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
// EQ Power Button
// =============================================================================

class _EqPowerButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;

  const _EqPowerButton({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? _kAccent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _kAccent.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : [],
          border: Border.all(
            color: enabled ? _kAccent : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.power_settings_new,
          size: 18,
          color: enabled ? _kAccent : Colors.white38,
        ),
      ),
    );
  }
}

// =============================================================================
// Band Slider
// =============================================================================

class _BandSlider extends StatelessWidget {
  final double frequency;
  final double gain;
  final double width;
  final bool isActive;
  final bool showLabel;
  final ValueChanged<double> onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _BandSlider({
    required this.frequency,
    required this.gain,
    required this.width,
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
    return frequency >= 100
        ? '${frequency.round()}'
        : frequency.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final normalized = (gain - _kMinGain) / (_kMaxGain - _kMinGain);
    final glowIntensity = (gain.abs() / _kMaxGain).clamp(0.0, 1.0);
    final trackColor = gain > 0
        ? _kAccent
        : gain < 0
        ? const Color(0xFF5EC4D4)
        : Colors.white38;

    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isActive)
            Text(
              '${gain.toStringAsFixed(1)} dB',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: trackColor,
              ),
            ),
          if (!isActive) const SizedBox(height: 14),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: trackColor.withValues(
                    alpha: 0.5 + glowIntensity * 0.5,
                  ),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                  thumbColor: isActive ? trackColor : Colors.white70,
                  overlayColor: trackColor.withValues(alpha: 0.12),
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
                    final newGain = _kMinGain + v * (_kMaxGain - _kMinGain);
                    final rounded = (newGain * 10).roundToDouble() / 10;
                    onChanged(rounded.clamp(_kMinGain, _kMaxGain));
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
  final int activeBand;

  _FrequencyCurvePainter({
    required this.gains,
    required this.frequencies,
    required this.accent,
    this.activeBand = -1,
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
      final y =
          padTop +
          plotH * (1.0 - (gains[i] - _kMinGain) / (_kMaxGain - _kMinGain));
      points.add(Offset(x, y));
    }

    final curvePath = _catmullRomPath(points);

    // Gradient fill under curve
    final fillPath = Path.from(curvePath)
      ..lineTo(points.last.dx, padTop + plotH)
      ..lineTo(points.first.dx, padTop + plotH)
      ..close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, padTop),
        Offset(size.width / 2, padTop + plotH),
        [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0.02)],
      );
    canvas.drawPath(fillPath, fillPaint);

    // Curve stroke
    final curvePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(curvePath, curvePaint);

    // Control dots
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final g = gains[i];
      final isActive = i == activeBand;
      final glowIntensity = (g.abs() / _kMaxGain).clamp(0.0, 1.0);

      if (glowIntensity > 0.05) {
        final glowColor = g > 0 ? accent : const Color(0xFF5EC4D4);
        canvas.drawCircle(
          pt,
          4 + glowIntensity * 4,
          Paint()..color = glowColor.withValues(alpha: 0.25 * glowIntensity),
        );
      }

      canvas.drawCircle(
        pt,
        isActive ? 4.0 : 2.5,
        Paint()..color = isActive ? accent : accent.withValues(alpha: 0.8),
      );
    }

    canvas.restore();

    _drawAxisLabels(
      canvas,
      size,
      padLeft,
      padRight,
      padTop,
      padBottom,
      plotW,
      plotH,
    );
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

    for (final dB in [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0]) {
      final y =
          padTop + plotH * (1.0 - (dB - _kMinGain) / (_kMaxGain - _kMinGain));
      _drawDashedLine(
        canvas,
        Offset(padLeft, y),
        Offset(padLeft + plotW, y),
        dB == 0
            ? (Paint()
                ..color = Colors.white.withValues(alpha: 0.2)
                ..strokeWidth = 1.0)
            : gridPaint,
        dashWidth: dB == 0 ? plotW : 4,
        gapWidth: dB == 0 ? 0 : 4,
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
    if (len == 0) return;
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

    for (final dB in [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0]) {
      final y =
          padTop + plotH * (1.0 - (dB - _kMinGain) / (_kMaxGain - _kMinGain));
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(textAlign: TextAlign.right, maxLines: 1),
            )
            ..pushStyle(labelStyle)
            ..addText(dB >= 0 ? '+${dB.round()}' : '${dB.round()}');
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 26));
      canvas.drawParagraph(paragraph, Offset(2, y - paragraph.height / 2));
    }

    final freqLabels = <double, String>{
      100.0: '100',
      1000.0: '1k',
      10000.0: '10k',
    };
    for (final entry in freqLabels.entries) {
      final x = padLeft + _logNormalize(entry.key) * plotW;
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 1),
            )
            ..pushStyle(labelStyle)
            ..addText(entry.value);
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 30));
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

        final x =
            0.5 *
            ((2 * p1.dx) +
                (-p0.dx + p2.dx) * t +
                (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * tt +
                (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * ttt);
        final y =
            0.5 *
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
    if (activeBand != oldDelegate.activeBand) return true;
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
