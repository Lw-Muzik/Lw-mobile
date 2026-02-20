import 'package:eq_app/controllers/AppController.dart';
import 'package:eq_app/models/room_preset.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'AudioFx.dart';

class SpaceView extends StatefulWidget {
  const SpaceView({super.key});

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // =============== ROOM REVERB ===============
        const SettingsHeader(title: "ROOM REVERB"),
        const SizedBox(height: 8),
        FancyCard(
          isFancy: controller.isFancy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                title: const Text("Room Reverb"),
                subtitle: Text(
                  controller.reverbEnabled
                      ? controller.activeRoomPresetName
                      : "Disabled",
                ),
                value: controller.reverbEnabled,
                onChanged: (v) => controller.reverbEnabled = v,
              ),
              if (controller.reverbEnabled) ...[
                const SizedBox(height: 8),
                _buildPresetChips(controller, theme),
                const Divider(height: 24),
                _buildReverbSlider(
                  context,
                  label: "Room Size",
                  leftLabel: "Tiny",
                  rightLabel: "Cathedral",
                  value: controller.reverbDecayTime.toDouble(),
                  min: 100,
                  max: 20000,
                  displayValue: "${(controller.reverbDecayTime / 1000).toStringAsFixed(1)}s",
                  onChanged: (v) {
                    controller.reverbDecayTime = v.toInt();
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Damping",
                  leftLabel: "Bright",
                  rightLabel: "Warm",
                  value: controller.reverbDecayHFRatio.toDouble(),
                  min: 100,
                  max: 2000,
                  displayValue: "${(controller.reverbDecayHFRatio / 10).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.reverbDecayHFRatio = v.toInt();
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Wet Level",
                  leftLabel: "Dry",
                  rightLabel: "Wet",
                  value: controller.reverbLevel.toDouble(),
                  min: -9000,
                  max: 2000,
                  displayValue: "${(controller.reverbLevel / 100).toStringAsFixed(1)} dB",
                  onChanged: (v) {
                    controller.reverbLevel = v.toInt();
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Pre-Delay",
                  leftLabel: "0 ms",
                  rightLabel: "300 ms",
                  value: controller.reverbReflectionsDelay.toDouble(),
                  min: 0,
                  max: 300,
                  displayValue: "${controller.reverbReflectionsDelay} ms",
                  onChanged: (v) {
                    controller.reverbReflectionsDelay = v.toInt();
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Density",
                  leftLabel: "Sparse",
                  rightLabel: "Dense",
                  value: controller.reverbDensity.toDouble(),
                  min: 0,
                  max: 1000,
                  displayValue: "${(controller.reverbDensity / 10).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.reverbDensity = v.toInt();
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Diffusion",
                  leftLabel: "Focused",
                  rightLabel: "Diffuse",
                  value: controller.reverbDiffusion.toDouble(),
                  min: 0,
                  max: 1000,
                  displayValue: "${(controller.reverbDiffusion / 10).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.reverbDiffusion = v.toInt();
                    _markCustomPreset(controller);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // =============== STEREO ENHANCEMENT ===============
        const SettingsHeader(title: "STEREO ENHANCEMENT"),
        const SizedBox(height: 8),
        FancyCard(
          isFancy: controller.isFancy,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: const Text("Stereo Expand"),
                subtitle: Text(
                  controller.stereoExpandEnabled
                      ? "${(controller.stereoWidth / 10).toStringAsFixed(0)}% width"
                      : "Disabled",
                ),
                value: controller.stereoExpandEnabled,
                onChanged: (v) {
                  controller.stereoExpandEnabled = v;
                  if (v && controller.crossfeedEnabled) {
                    _showMutualExclusiveToast("Crossfeed disabled");
                  }
                },
              ),
              if (controller.stereoExpandEnabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text("Narrow", style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      )),
                      Expanded(
                        child: Slider(
                          value: controller.stereoWidth.toDouble(),
                          min: 0,
                          max: 1000,
                          divisions: 100,
                          label: "${(controller.stereoWidth / 10).toStringAsFixed(0)}%",
                          onChanged: (v) => controller.stereoWidth = v.toInt(),
                        ),
                      ),
                      Text("Wide", style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      )),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _StereoFieldIndicator(width: controller.stereoWidth / 1000),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // =============== CROSSFEED ===============
        const SettingsHeader(title: "CROSSFEED"),
        const SizedBox(height: 8),
        FancyCard(
          isFancy: controller.isFancy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                title: const Text("Crossfeed"),
                subtitle: Text(
                  controller.crossfeedEnabled
                      ? _crossfeedLabel(controller.crossfeedStrength)
                      : "Disabled",
                ),
                value: controller.crossfeedEnabled,
                onChanged: (v) {
                  controller.crossfeedEnabled = v;
                  if (v && controller.stereoExpandEnabled) {
                    _showMutualExclusiveToast("Stereo Expand disabled");
                  }
                },
              ),
              if (controller.crossfeedEnabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CrossfeedPresetChip(
                        label: "Light",
                        value: 300,
                        current: controller.crossfeedStrength,
                        onTap: () => controller.crossfeedStrength = 300,
                      ),
                      _CrossfeedPresetChip(
                        label: "Normal",
                        value: 600,
                        current: controller.crossfeedStrength,
                        onTap: () => controller.crossfeedStrength = 600,
                      ),
                      _CrossfeedPresetChip(
                        label: "Strong",
                        value: 900,
                        current: controller.crossfeedStrength,
                        onTap: () => controller.crossfeedStrength = 900,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Slider(
                    value: controller.crossfeedStrength.toDouble(),
                    min: 0,
                    max: 1000,
                    divisions: 100,
                    label: "${(controller.crossfeedStrength / 10).toStringAsFixed(0)}%",
                    onChanged: (v) => controller.crossfeedStrength = v.toInt(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    "Crossfeed blends a portion of each stereo channel into the other, "
                    "reducing the exaggerated separation heard in headphones for a more "
                    "natural, speaker-like presentation.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPresetChips(AppController controller, ThemeData theme) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: RoomPreset.builtIn.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final preset = RoomPreset.builtIn[index];
          final isSelected = controller.activeRoomPresetName == preset.name;
          return FilterChip(
            label: Text(preset.name),
            selected: isSelected,
            onSelected: (_) => controller.applyRoomPreset(preset),
            selectedColor: theme.colorScheme.primary,
            labelStyle: TextStyle(
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
              fontSize: 13,
            ),
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReverbSlider(
    BuildContext context, {
    required String label,
    required String leftLabel,
    required String rightLabel,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(displayValue, style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              )),
            ],
          ),
          Row(
            children: [
              Text(leftLabel, style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 11,
              )),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ),
              Text(rightLabel, style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 11,
              )),
            ],
          ),
        ],
      ),
    );
  }

  void _markCustomPreset(AppController controller) {
    // When user manually adjusts a slider, check if it still matches any preset
    final presets = RoomPreset.builtIn;
    for (final p in presets) {
      if (p.decayTime == controller.reverbDecayTime &&
          p.roomLevel == controller.reverbRoomLevel &&
          p.roomHFLevel == controller.reverbRoomHFLevel &&
          p.decayHFRatio == controller.reverbDecayHFRatio &&
          p.reflectionsLevel == controller.reverbReflectionsLevel &&
          p.reflectionsDelay == controller.reverbReflectionsDelay &&
          p.reverbLevel == controller.reverbLevel &&
          p.reverbDelay == controller.reverbDelay &&
          p.density == controller.reverbDensity &&
          p.diffusion == controller.reverbDiffusion) {
        controller.activeRoomPresetName = p.name;
        return;
      }
    }
    controller.activeRoomPresetName = 'Custom';
  }

  String _crossfeedLabel(int strength) {
    if (strength <= 200) return "Very Light";
    if (strength <= 400) return "Light";
    if (strength <= 700) return "Normal";
    return "Strong";
  }

  void _showMutualExclusiveToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Visual indicator showing the stereo field width.
class _StereoFieldIndicator extends StatelessWidget {
  final double width; // 0.0 to 1.0

  const _StereoFieldIndicator({required this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 32,
      child: CustomPaint(
        size: const Size(double.infinity, 32),
        painter: _StereoFieldPainter(
          width: width,
          color: theme.colorScheme.primary,
          bgColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _StereoFieldPainter extends CustomPainter {
  final double width;
  final Color color;
  final Color bgColor;

  _StereoFieldPainter({
    required this.width,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;
    final fgPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Background bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, centerY - 4, size.width, 8),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    // Active stereo field region
    final spread = (size.width / 2) * width.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - spread, centerY - 6, spread * 2, 12),
        const Radius.circular(6),
      ),
      fgPaint,
    );

    // L / R labels
    final textStyle = TextStyle(
      color: color,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    final lPainter = TextPainter(
      text: TextSpan(text: 'L', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final rPainter = TextPainter(
      text: TextSpan(text: 'R', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    lPainter.paint(canvas, Offset(4, centerY - lPainter.height / 2));
    rPainter.paint(canvas, Offset(size.width - rPainter.width - 4, centerY - rPainter.height / 2));
  }

  @override
  bool shouldRepaint(_StereoFieldPainter old) =>
      old.width != width || old.color != color;
}

/// Crossfeed intensity preset chip.
class _CrossfeedPresetChip extends StatelessWidget {
  final String label;
  final int value;
  final int current;
  final VoidCallback onTap;

  const _CrossfeedPresetChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = (current - value).abs() < 50;
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: isSelected
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerLow,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
