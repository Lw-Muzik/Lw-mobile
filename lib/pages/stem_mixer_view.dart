import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/AppController.dart';
import '../controllers/stem_controller.dart';
import '../models/stem_model.dart';

class StemMixerView extends StatelessWidget {
  const StemMixerView({super.key});

  static const _stemColors = {
    Stem.vocals: Color(0xFF9C27B0),
    Stem.drums: Color(0xFFFF9800),
    Stem.bass: Color(0xFF4CAF50),
    Stem.other: Color(0xFF2196F3),
  };

  static const _stemIcons = {
    Stem.vocals: Icons.mic_rounded,
    Stem.drums: Icons.album_rounded,
    Stem.bass: Icons.graphic_eq_rounded,
    Stem.other: Icons.piano_rounded,
  };

  static const _stemLabels = {
    Stem.vocals: 'Vocals',
    Stem.drums: 'Drums',
    Stem.bass: 'Bass',
    Stem.other: 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final stem = controller.stemController;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Stem Mixer', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: () => stem.resetAll(),
            child: const Text('Reset', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: stem,
        builder: (context, _) {
          return Column(
            children: [
              // Quick presets
              _PresetBar(stem: stem),
              const SizedBox(height: 16),
              // Mixer channels
              Expanded(child: _MixerChannels(stem: stem)),
              // Playback controls
              _PlaybackBar(controller: controller, stem: stem),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          );
        },
      ),
    );
  }
}

class _PresetBar extends StatelessWidget {
  final StemController stem;
  const _PresetBar({required this.stem});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _PresetChip(label: 'Karaoke', onTap: stem.applyKaraoke),
          const SizedBox(width: 8),
          _PresetChip(label: 'Acapella', onTap: stem.applyAcapella),
          const SizedBox(width: 8),
          _PresetChip(label: 'Instrumental', onTap: stem.applyInstrumental),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onTap,
    );
  }
}

class _MixerChannels extends StatelessWidget {
  final StemController stem;
  const _MixerChannels({required this.stem});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: Stem.values.map((s) => Expanded(
        child: _MixerChannel(
          stem: s,
          state: stem.stateFor(s),
          color: StemMixerView._stemColors[s]!,
          icon: StemMixerView._stemIcons[s]!,
          label: StemMixerView._stemLabels[s]!,
          onVolumeChanged: (v) => stem.setVolume(s, v),
          onMuteToggle: () => stem.toggleMute(s),
          onSoloToggle: () => stem.toggleSolo(s),
        ),
      )).toList(),
    );
  }
}

class _MixerChannel extends StatelessWidget {
  final Stem stem;
  final StemState state;
  final Color color;
  final IconData icon;
  final String label;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMuteToggle;
  final VoidCallback onSoloToggle;

  const _MixerChannel({
    required this.stem,
    required this.state,
    required this.color,
    required this.icon,
    required this.label,
    required this.onVolumeChanged,
    required this.onMuteToggle,
    required this.onSoloToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = !state.muted;
    final effectiveColor = isActive ? color : Colors.white24;

    return Column(
      children: [
        // Stem icon
        Icon(icon, color: effectiveColor, size: 28),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
          color: effectiveColor, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        // Volume fader
        Expanded(
          child: _VerticalFader(
            value: state.volume,
            color: effectiveColor,
            onChanged: onVolumeChanged,
          ),
        ),
        const SizedBox(height: 8),
        // Volume label
        Text(
          '${(state.volume * 100).round()}%',
          style: TextStyle(color: effectiveColor, fontSize: 10),
        ),
        const SizedBox(height: 8),
        // Mute / Solo buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MuteButton(
              active: state.muted,
              color: color,
              onTap: onMuteToggle,
            ),
            const SizedBox(width: 4),
            _SoloButton(
              active: state.soloed,
              color: color,
              onTap: onSoloToggle,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _VerticalFader extends StatelessWidget {
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _VerticalFader({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return GestureDetector(
          onVerticalDragUpdate: (details) {
            final newVal = 1.0 - (details.localPosition.dy / height);
            onChanged(newVal.clamp(0.0, 1.0));
          },
          onTapDown: (details) {
            final newVal = 1.0 - (details.localPosition.dy / height);
            onChanged(newVal.clamp(0.0, 1.0));
          },
          child: CustomPaint(
            size: Size(40, height),
            painter: _FaderPainter(value: value, color: color),
          ),
        );
      },
    );
  }
}

class _FaderPainter extends CustomPainter {
  final double value;
  final Color color;

  _FaderPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final trackTop = 8.0;
    final trackBottom = size.height - 8.0;
    final trackHeight = trackBottom - trackTop;

    // Track groove
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(centerX, trackTop),
      Offset(centerX, trackBottom),
      trackPaint,
    );

    // Active portion
    final thumbY = trackBottom - (value * trackHeight);
    final activePaint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(centerX, thumbY),
      Offset(centerX, trackBottom),
      activePaint,
    );

    // Glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(centerX, thumbY), 10, glowPaint);

    // Thumb knob
    final thumbPaint = Paint()..color = color;
    canvas.drawCircle(Offset(centerX, thumbY), 8, thumbPaint);

    // Inner dot
    final innerPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(Offset(centerX, thumbY), 3, innerPaint);
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.value != value || old.color != color;
}

class _MuteButton extends StatelessWidget {
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _MuteButton({required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.red : Colors.white.withValues(alpha: 0.1),
          border: Border.all(
            color: active ? Colors.red : Colors.white24,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text('M', style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _SoloButton extends StatelessWidget {
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _SoloButton({required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : Colors.white.withValues(alpha: 0.1),
          border: Border.all(
            color: active ? color : Colors.white24,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text('S', style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _PlaybackBar extends StatelessWidget {
  final AppController controller;
  final StemController stem;

  const _PlaybackBar({required this.controller, required this.stem});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          // Stem mode toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Stem Mode', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              Switch(
                value: stem.stemModeActive,
                onChanged: (v) {
                  if (v) {
                    stem.activateStemMode();
                  } else {
                    stem.deactivateStemMode();
                  }
                },
                activeColor: const Color(0xFF9C27B0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
