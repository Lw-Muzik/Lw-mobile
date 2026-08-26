import '/controllers/app_controller.dart';
import 'package:eq_app/models/room_preset.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio_fx.dart';

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
                  value: controller.dspRoomSize,
                  min: 0.0,
                  max: 1.0,
                  displayValue:
                      "${(controller.dspRoomSize * 100).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.dspRoomSize = v;
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Decay",
                  leftLabel: "Short",
                  rightLabel: "Long",
                  value: controller.dspDecay,
                  min: 0.0,
                  max: 1.0,
                  displayValue:
                      "${(controller.dspDecay * 100).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.dspDecay = v;
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Damping",
                  leftLabel: "Bright",
                  rightLabel: "Dark",
                  value: controller.dspDamping,
                  min: 0.0,
                  max: 1.0,
                  displayValue:
                      "${(controller.dspDamping * 100).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.dspDamping = v;
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Pre-Delay",
                  leftLabel: "0 ms",
                  rightLabel: "200 ms",
                  value: controller.dspPreDelay,
                  min: 0.0,
                  max: 200.0,
                  displayValue:
                      "${controller.dspPreDelay.toStringAsFixed(0)} ms",
                  onChanged: (v) {
                    controller.dspPreDelay = v;
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Diffusion",
                  leftLabel: "Sparse",
                  rightLabel: "Dense",
                  value: controller.dspDiffusion,
                  min: 0.0,
                  max: 1.0,
                  displayValue:
                      "${(controller.dspDiffusion * 100).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.dspDiffusion = v;
                    _markCustomPreset(controller);
                  },
                ),
                _buildReverbSlider(
                  context,
                  label: "Wet/Dry",
                  leftLabel: "Dry",
                  rightLabel: "Wet",
                  value: controller.dspWetDry,
                  min: 0.0,
                  max: 1.0,
                  displayValue:
                      "${(controller.dspWetDry * 100).toStringAsFixed(0)}%",
                  onChanged: (v) {
                    controller.dspWetDry = v;
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
                      ? _stereoWidthLabel(controller.stereoWidth)
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
                      Text(
                        "Mono",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: controller.stereoWidth,
                          min: 0.0,
                          max: 2.0,
                          divisions: 40,
                          label: _stereoWidthLabel(controller.stereoWidth),
                          onChanged: (v) => controller.stereoWidth = v,
                        ),
                      ),
                      Text(
                        "Wide",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _StereoFieldIndicator(
                    width: controller.stereoWidth / 2.0,
                  ),
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
                      ? _crossfeedLabel(controller.crossfeedFeed)
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
                        cutoff: 700,
                        feed: 4.5,
                        currentFeed: controller.crossfeedFeed,
                        onTap: () {
                          controller.crossfeedCutoff = 700;
                          controller.crossfeedFeed = 4.5;
                        },
                      ),
                      _CrossfeedPresetChip(
                        label: "Normal",
                        cutoff: 700,
                        feed: 6.0,
                        currentFeed: controller.crossfeedFeed,
                        onTap: () {
                          controller.crossfeedCutoff = 700;
                          controller.crossfeedFeed = 6.0;
                        },
                      ),
                      _CrossfeedPresetChip(
                        label: "Strong",
                        cutoff: 650,
                        feed: 9.5,
                        currentFeed: controller.crossfeedFeed,
                        onTap: () {
                          controller.crossfeedCutoff = 650;
                          controller.crossfeedFeed = 9.5;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildReverbSlider(
                  context,
                  label: "Feed Level",
                  leftLabel: "Subtle",
                  rightLabel: "Strong",
                  value: controller.crossfeedFeed,
                  min: 1.0,
                  max: 15.0,
                  displayValue:
                      "${controller.crossfeedFeed.toStringAsFixed(1)} dB",
                  onChanged: (v) => controller.crossfeedFeed = v,
                ),
                _buildReverbSlider(
                  context,
                  label: "Cutoff",
                  leftLabel: "100 Hz",
                  rightLabel: "2000 Hz",
                  value: controller.crossfeedCutoff,
                  min: 100.0,
                  max: 2000.0,
                  displayValue:
                      "${controller.crossfeedCutoff.toStringAsFixed(0)} Hz",
                  onChanged: (v) => controller.crossfeedCutoff = v,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    "Crossfeed blends a filtered portion of each stereo channel into the other, "
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
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: () => _openRoomPresetSheet(context, controller),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.spatial_audio_rounded,
                size: 18,
                color: accent.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Preset",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      controller.activeRoomPresetName.isEmpty
                          ? 'Custom'
                          : controller.activeRoomPresetName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRoomPresetSheet(BuildContext context, AppController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoomPresetBottomSheet(controller: controller),
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
              Text(
                displayValue,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                leftLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ),
              Text(
                rightLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _markCustomPreset(AppController controller) {
    final presets = RoomPreset.builtIn;
    for (final p in presets) {
      if ((p.roomSize - controller.dspRoomSize).abs() < 0.01 &&
          (p.decay - controller.dspDecay).abs() < 0.01 &&
          (p.damping - controller.dspDamping).abs() < 0.01 &&
          (p.preDelay - controller.dspPreDelay).abs() < 0.5 &&
          (p.diffusion - controller.dspDiffusion).abs() < 0.01 &&
          (p.wetDry - controller.dspWetDry).abs() < 0.01) {
        controller.activeRoomPresetName = p.name;
        return;
      }
    }
    controller.activeRoomPresetName = 'Custom';
  }

  String _stereoWidthLabel(double width) {
    if (width < 0.1) return "Mono";
    if (width < 0.5) return "Narrow";
    if (width < 1.1) return "Normal";
    if (width < 1.5) return "Wide";
    return "Extra Wide";
  }

  String _crossfeedLabel(double feedDb) {
    if (feedDb < 3.0) return "Very Light";
    if (feedDb < 5.5) return "Light";
    if (feedDb < 8.0) return "Normal";
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

// =============================================================================
// Room Preset Bottom Sheet
// =============================================================================

class _RoomPresetBottomSheet extends StatelessWidget {
  final AppController controller;
  const _RoomPresetBottomSheet({required this.controller});

  static const _accent = Color(0xFFD4A825);

  IconData _iconForPreset(String name) {
    final lower = name.toLowerCase();
    if (lower == 'off') return Icons.volume_off_rounded;
    if (lower.contains('small')) return Icons.weekend_rounded;
    if (lower.contains('medium')) return Icons.living_rounded;
    if (lower.contains('large')) return Icons.home_rounded;
    if (lower.contains('hall')) return Icons.account_balance_rounded;
    if (lower.contains('cathedral')) return Icons.church_rounded;
    if (lower.contains('plate')) return Icons.rectangle_rounded;
    if (lower.contains('studio')) return Icons.headphones_rounded;
    if (lower.contains('chamber')) return Icons.door_sliding_rounded;
    if (lower.contains('arena')) return Icons.stadium_rounded;
    if (lower.contains('concert')) return Icons.theater_comedy_rounded;
    return Icons.spatial_audio_rounded;
  }

  String _description(RoomPreset p) {
    if (p.name == 'Off') return 'No reverb';
    final sizeLabel = p.roomSize < 0.3
        ? 'Tight'
        : p.roomSize < 0.6
        ? 'Medium'
        : 'Spacious';
    final decayLabel = p.decay < 0.3
        ? 'short decay'
        : p.decay < 0.6
        ? 'moderate decay'
        : 'long decay';
    return '$sizeLabel, $decayLabel, ${(p.wetDry * 100).round()}% wet';
  }

  @override
  Widget build(BuildContext context) {
    final presets = RoomPreset.builtIn;
    final active = controller.activeRoomPresetName;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.spatial_audio_rounded,
                  color: _accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Room Presets",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  "${presets.length} presets",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          // Preset list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              itemCount: presets.length,
              itemBuilder: (context, index) {
                final preset = presets[index];
                final isActive = preset.name == active;
                return InkWell(
                  onTap: () {
                    controller.applyRoomPreset(preset);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    color: isActive ? _accent.withValues(alpha: 0.1) : null,
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isActive
                                ? _accent.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _iconForPreset(preset.name),
                            size: 18,
                            color: isActive
                                ? _accent
                                : Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                preset.name,
                                style: TextStyle(
                                  color: isActive
                                      ? _accent
                                      : Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              Text(
                                _description(preset),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isActive)
                          const Icon(
                            Icons.check_rounded,
                            color: _accent,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, centerY - 4, size.width, 8),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    final spread = (size.width / 2) * width.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - spread, centerY - 6, spread * 2, 12),
        const Radius.circular(6),
      ),
      fgPaint,
    );

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
    rPainter.paint(
      canvas,
      Offset(size.width - rPainter.width - 4, centerY - rPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_StereoFieldPainter old) =>
      old.width != width || old.color != color;
}

/// Crossfeed intensity preset chip (BS2B standard presets).
class _CrossfeedPresetChip extends StatelessWidget {
  final String label;
  final double cutoff;
  final double feed;
  final double currentFeed;
  final VoidCallback onTap;

  const _CrossfeedPresetChip({
    required this.label,
    required this.cutoff,
    required this.feed,
    required this.currentFeed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = (currentFeed - feed).abs() < 0.3;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
