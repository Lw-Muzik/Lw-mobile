/// The Stems tab: turn vocals, drums and instruments up or down while a song
/// plays.
///
/// Three channel strips — a level readout, a fader, and a big pad under it —
/// then three combo pads. Faders are *levels*, 0–100% with 100% the original,
/// so their fill rises from the bottom; the graphic EQ's centre-out fill is
/// for signed gain and would read wrong here. Everything else follows the EQ
/// tab's idiom: rail and cap, the whole column as the drag target, a haptic
/// detent at the ends, double-tap to go home.
///
/// Before the mixer there is the first-use path: a one-time model download,
/// a speed test, and a calm answer for phones too slow to keep up.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/stems_controller.dart';
import '../models/stems_engine_status.dart';
import '../models/stems_mix.dart';
import '../Themes/ember.dart';
import 'audio_fx.dart';

/// The app's one accent. Lit pads put it on [Ember.accentWash], never under
/// white text (1.63:1).
const Color _kAccent = Ember.accent;

/// The EQ's "doing nothing" cap grey, for a stem whose pad is off.
const Color _kIdle = Color(0xFF6E6E76);

/// Strips and combos while stems aren't live: visible, touchable — a change
/// made now applies the moment they are — but plainly not in effect yet.
const double _kDimmed = 0.42;

/// Past this a fader stops reading as something to grip.
const double _kMaxFaderHeight = 340;

/// Below this the mixer scrolls rather than crushing its faders. A 320×568
/// phone in portrait still clears it (faders of ~120 dp); a phone in
/// landscape, with about 100 dp under the tab strip, does not.
const double _kMinMixerHeight = 250;

class StemsView extends StatelessWidget {
  const StemsView({super.key, required this.controller, this.isFancy = false});

  final StemsController controller;
  final bool isFancy;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final stage = controller.stage;
        final mixer = stage == StemsStage.mixer;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(controller: controller, showStatus: mixer),
              const SizedBox(height: 8),
              Expanded(
                child: FancyCard(
                  isFancy: isFancy,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: mixer
                        ? _Mixer(
                            key: const ValueKey('stems-mixer'),
                            controller: controller,
                          )
                        : _Setup(
                            key: ValueKey(stage),
                            controller: controller,
                            stage: stage,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _Footer(controller: controller, showReset: mixer),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// Header and footer
// =============================================================================

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.showStatus});

  final StemsController controller;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    // At least the height of the other tabs' header rows; taller only when a
    // long status needs a second line.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          Icon(
            Icons.layers_rounded,
            size: 18,
            color: controller.engaged
                ? _kAccent
                : Colors.white.withValues(alpha: 0.25),
          ),
          const SizedBox(width: 8),
          Text(
            'Stems',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: showStatus
                  ? _StatusChip(status: controller.status)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.showReset});

  final StemsController controller;
  final bool showReset;

  @override
  Widget build(BuildContext context) {
    final canReset = !controller.mix.isDefault;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (showReset)
            TextButton.icon(
              onPressed: canReset
                  ? () {
                      HapticFeedback.selectionClick();
                      controller.reset();
                    }
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: _kAccent,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
                textStyle: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.restart_alt_rounded, size: 17),
              label: const Text('Reset'),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stem separation: Spleeter by Deezer (MIT)',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Ember.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The engine's state in a few words, for the chip in the header.
@visibleForTesting
String stemsChipLabel(StemsEngineStatus status) => switch (status.state) {
  StemsEngineState.preparing =>
    status.progress >= 0.01
        ? 'Preparing… ${(status.progress * 100).round()}%'
        : 'Preparing…',
  StemsEngineState.ready => 'Ready',
  StemsEngineState.unavailable => switch (status.reason) {
    'stream' || 'youtube' => 'Stems work on songs saved on your phone',
    'protected' => 'This song is protected',
    'unsupported' || 'decode' => "Can't read this song",
    'model' => 'Stems model unavailable',
    _ => 'Not available for this song',
  },
  StemsEngineState.idle => 'Play a song',
  StemsEngineState.error =>
    status.reason == 'model'
        ? "Stems model didn't load"
        : "Couldn't split this song",
};

/// The same, as a sentence over the dimmed mixer — including what is heard
/// meanwhile, which is the question someone looking at greyed-out faders has.
@visibleForTesting
String stemsStatusNote(StemsEngineStatus status) => switch (status.state) {
  StemsEngineState.preparing =>
    "Getting stems ready. You'll hear the original until then.",
  StemsEngineState.ready => '',
  StemsEngineState.idle => 'Play a song saved on your phone to use stems.',
  StemsEngineState.unavailable => switch (status.reason) {
    'stream' =>
      'Streaming songs play as is. Stems work on songs saved on your phone.',
    'youtube' => "YouTube songs can't be split, even downloaded ones, so this plays as is.",
    'protected' => "This song is protected, so it can't be split.",
    'unsupported' ||
    'decode' => "Can't read this song's audio, so it plays as is.",
    'model' => "The stems model didn't load, so this plays as is.",
    _ => "Stems aren't available for this song, so it plays as is.",
  },
  StemsEngineState.error =>
    'Something went wrong splitting this song, so it plays as is.',
};

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final StemsEngineStatus status;

  @override
  Widget build(BuildContext context) {
    final label = stemsChipLabel(status);
    final ready = status.isReady;
    final preparing = status.state == StemsEngineState.preparing;
    final foreground = ready ? _kAccent : Colors.white.withValues(alpha: 0.72);

    final Widget lead;
    if (preparing) {
      lead = SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: _kAccent,
          backgroundColor: Colors.white.withValues(alpha: 0.10),
          value: status.progress >= 0.01 ? status.progress : null,
        ),
      );
    } else if (ready) {
      lead = Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: _kAccent,
          shape: BoxShape.circle,
        ),
      );
    } else {
      lead = Icon(
        status.state == StemsEngineState.error
            ? Icons.error_outline_rounded
            : Icons.info_outline_rounded,
        size: 13,
        color: foreground,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey('${status.state}/${status.reason}'),
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ready
              ? Ember.accentWash
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: ready
                ? _kAccent.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            lead,
            const SizedBox(width: 6),
            Flexible(
              // The longest status is a full sentence; on a narrow phone it
              // takes a second line rather than losing its end.
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Mixer
// =============================================================================

class _Mixer extends StatelessWidget {
  const _Mixer({super.key, required this.controller});

  final StemsController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final live = status.isReady;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final compact = height < 360;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: live
                    ? const SizedBox(width: double.infinity)
                    : _StatusNote(status: status),
              ),
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: live ? 1 : _kDimmed,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final stem in Stem.values) ...[
                        if (stem.index > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _StemStrip(
                            stem: stem,
                            controller: controller,
                            compact: compact,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: live ? 1 : _kDimmed,
                child: _ComboRow(controller: controller, compact: compact),
              ),
            ],
          );
          if (height >= _kMinMixerHeight) return content;
          return SingleChildScrollView(
            child: SizedBox(height: _kMinMixerHeight, child: content),
          );
        },
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.status});

  final StemsEngineStatus status;

  @override
  Widget build(BuildContext context) {
    final preparing = status.state == StemsEngineState.preparing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  preparing
                      ? Icons.hourglass_top_rounded
                      : Icons.info_outline_rounded,
                  size: 14,
                  color: preparing
                      ? _kAccent
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stemsStatusNote(status),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ),
            ],
          ),
          if (preparing) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: status.progress >= 0.01 ? status.progress : null,
                minHeight: 2,
                color: _kAccent,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StemStrip extends StatelessWidget {
  const _StemStrip({
    required this.stem,
    required this.controller,
    required this.compact,
  });

  final Stem stem;
  final StemsController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mix = controller.mix;
    final value = mix.fader(stem);
    final on = mix.padOn(stem);
    return Column(
      children: [
        _LevelReadout(value: value, on: on),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SizedBox(
                height: math.min(constraints.maxHeight, _kMaxFaderHeight),
                width: constraints.maxWidth,
                child: _StemFader(
                  stem: stem,
                  value: value,
                  on: on,
                  onChanged: (v) => controller.setFader(stem, v),
                  onChangeEnd: controller.commitFader,
                  onReset: () => controller.resetFader(stem),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        _StemPad(
          stem: stem,
          on: on,
          height: compact ? 54 : 64,
          onTap: () => controller.togglePad(stem),
        ),
      ],
    );
  }
}

class _LevelReadout extends StatelessWidget {
  const _LevelReadout({required this.value, required this.on});

  final double value;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final changed = on && value < StemsMix.unity;
    final color = !on
        ? Colors.white.withValues(alpha: 0.30)
        : changed
        ? _kAccent
        : Ember.textPrimary.withValues(alpha: 0.9);
    return SizedBox(
      height: 20,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          // Merged, not replaced: a bare TextStyle here would drop the
          // ambient font along with everything else the theme set.
          style: DefaultTextStyle.of(context).style.merge(
            TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
              // A muted stem keeps its level for when it comes back; struck
              // through, it reads as remembered rather than playing.
              decoration: on ? TextDecoration.none : TextDecoration.lineThrough,
              decorationColor: Colors.white.withValues(alpha: 0.30),
            ),
          ),
          child: Text('${(value * 100).round()}%'),
        ),
      ),
    );
  }
}

// =============================================================================
// Fader
// =============================================================================

class _StemFader extends StatefulWidget {
  const _StemFader({
    required this.stem,
    required this.value,
    required this.on,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
  });

  final Stem stem;
  final double value;
  final bool on;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final VoidCallback onReset;

  @override
  State<_StemFader> createState() => _StemFaderState();
}

class _StemFaderState extends State<_StemFader> {
  /// Height of the last laid-out track, so a touch can be turned into a level.
  double _trackHeight = 0;

  bool _active = false;

  /// The last level reported during this gesture, so the end detents fire
  /// once per arrival rather than on every pixel spent resting there.
  double? _last;

  double _valueAt(double localY) {
    final span = _trackHeight - _LevelFaderPainter.capHeight;
    if (span <= 0) return widget.value;
    final raw = 1 - (localY - _LevelFaderPainter.capHeight / 2) / span;
    return quantizeFader(raw);
  }

  void _report(double value) {
    final previous = _last ?? widget.value;
    _last = value;
    if (value == previous) return;
    // 100% is the original and 0% is gone: the two places people aim for.
    if (value == 0.0 || value == 1.0) HapticFeedback.selectionClick();
    widget.onChanged(value);
  }

  void _start(double localY) {
    setState(() => _active = true);
    _last = widget.value;
    _report(_valueAt(localY));
  }

  void _end() {
    if (!_active) return;
    setState(() => _active = false);
    _last = null;
    widget.onChangeEnd();
  }

  void _nudge(double delta) {
    widget.onChanged(quantizeFader(widget.value + delta));
    widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (widget.value * 100).round();
    return Semantics(
      label: '${widget.stem.label} level',
      value: widget.on ? '$percent%' : '$percent%, muted',
      increasedValue: '${(quantizeFader(widget.value + 0.05) * 100).round()}%',
      decreasedValue: '${(quantizeFader(widget.value - 0.05) * 100).round()}%',
      onIncrease: () => _nudge(0.05),
      onDecrease: () => _nudge(-0.05),
      slider: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _trackHeight = constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The whole column is the target, not a 6px rail. Dragging only:
            // a stray tap on a fader shouldn't drop the vocals to wherever the
            // finger happened to land.
            onVerticalDragStart: (d) => _start(d.localPosition.dy),
            onVerticalDragUpdate: (d) => _report(_valueAt(d.localPosition.dy)),
            onVerticalDragEnd: (_) => _end(),
            onVerticalDragCancel: _end,
            // The original level is a destination; give it its own gesture.
            onDoubleTap: () {
              HapticFeedback.mediumImpact();
              widget.onReset();
            },
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _LevelFaderPainter(
                value: widget.value,
                on: widget.on,
                active: _active,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Rail, a 0–100% scale, a fill rising from silence, and the cap.
class _LevelFaderPainter extends CustomPainter {
  const _LevelFaderPainter({
    required this.value,
    required this.on,
    required this.active,
  });

  final double value;
  final bool on;
  final bool active;

  static const double capHeight = 16;
  static const double _railWidth = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final top = capHeight / 2;
    final bottom = size.height - capHeight / 2;
    final span = math.max(0.0, bottom - top);
    final capWidth = math.min(size.width - 16, 50.0);

    // Rail.
    canvas.drawRRect(
      RRect.fromLTRBR(
        cx - _railWidth / 2,
        top,
        cx + _railWidth / 2,
        bottom,
        const Radius.circular(_railWidth / 2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );

    // Scale, outside the cap so it never hides under it. The top mark is the
    // original level, the datum everything else is measured against.
    final tickInner = capWidth / 2 + 4;
    final room = size.width / 2 - tickInner - 1;
    if (room > 2) {
      for (final t in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final y = bottom - t * span;
        final original = t == 1.0;
        final major = original || t == 0.0 || t == 0.5;
        final length = math.min(major ? 7.0 : 4.0, room);
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: original ? 0.34 : 0.12)
          ..strokeWidth = original ? 1.4 : 1;
        canvas.drawLine(
          Offset(cx - tickInner - length, y),
          Offset(cx - tickInner, y),
          paint,
        );
        canvas.drawLine(
          Offset(cx + tickInner, y),
          Offset(cx + tickInner + length, y),
          paint,
        );
      }
    }

    final y = bottom - value.clamp(0.0, 1.0) * span;
    final fill = on ? _kAccent : _kIdle;

    // A level, measured from silence: the fill rises from the bottom.
    if (value > 0.004) {
      final rect = Rect.fromLTRB(
        cx - _railWidth / 2,
        y,
        cx + _railWidth / 2,
        bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(_railWidth / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              fill.withValues(alpha: on ? 1.0 : 0.55),
              fill.withValues(alpha: on ? 0.45 : 0.25),
            ],
          ).createShader(rect),
      );
    }

    // Cap: a wide flat bar across the slot, as on the EQ.
    final capRect = RRect.fromLTRBR(
      cx - capWidth / 2,
      y - capHeight / 2,
      cx + capWidth / 2,
      y + capHeight / 2,
      const Radius.circular(4),
    );
    if (active) {
      canvas.drawRRect(
        capRect.inflate(3),
        Paint()
          ..color = fill.withValues(alpha: 0.30)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
      );
    }
    final capColor = !on
        ? const Color(0xFF4A4A52)
        : value > 0.004
        ? _kAccent
        : _kIdle;
    canvas.drawRRect(capRect, Paint()..color = capColor);
    // A notch, so the cap has a readable centre line at a glance.
    canvas.drawLine(
      Offset(cx - capWidth / 4, y),
      Offset(cx + capWidth / 4, y),
      Paint()
        ..color = Ember.ground.withValues(alpha: 0.55)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_LevelFaderPainter old) =>
      old.value != value || old.on != on || old.active != active;
}

// =============================================================================
// Pads
// =============================================================================

class _StemPad extends StatefulWidget {
  const _StemPad({
    required this.stem,
    required this.on,
    required this.height,
    required this.onTap,
  });

  final Stem stem;
  final bool on;
  final double height;
  final VoidCallback onTap;

  @override
  State<_StemPad> createState() => _StemPadState();
}

class _StemPadState extends State<_StemPad> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.on;
    final content = on ? _kAccent : Colors.white.withValues(alpha: 0.5);
    return Semantics(
      button: true,
      toggled: on,
      label: widget.stem.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: on
                  ? Ember.accentWash
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(Ember.radiusTile),
              border: Border.all(
                color: on
                    ? _kAccent.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.10),
                width: on ? 1.4 : 1,
              ),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.14),
                        blurRadius: 14,
                      ),
                    ]
                  : const [],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StemIcon(
                    stem: widget.stem,
                    on: on,
                    size: 18,
                    color: content,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.stem.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: content,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    on ? 'ON' : 'OFF',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: on
                          ? _kAccent.withValues(alpha: 0.75)
                          : Colors.white.withValues(alpha: 0.32),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComboRow extends StatelessWidget {
  const _ComboRow({required this.controller, required this.compact});

  final StemsController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = controller.mix.activeCombo;
    return Row(
      children: [
        for (final combo in StemCombo.values) ...[
          if (combo.index > 0) const SizedBox(width: 8),
          Expanded(
            child: _ComboPad(
              combo: combo,
              lit: combo == active,
              height: compact ? 40 : 44,
              onTap: () => controller.tapCombo(combo),
            ),
          ),
        ],
      ],
    );
  }
}

class _ComboPad extends StatelessWidget {
  const _ComboPad({
    required this.combo,
    required this.lit,
    required this.height,
    required this.onTap,
  });

  final StemCombo combo;
  final bool lit;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = lit ? _kAccent : Colors.white.withValues(alpha: 0.75);
    return Semantics(
      button: true,
      selected: lit,
      label: combo.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(Ember.radiusControl),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: lit
                  ? Ember.accentWash
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(Ember.radiusControl),
              border: Border.all(
                color: lit
                    ? _kAccent.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.09),
              ),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ComboIcon(combo: combo, color: content),
                    const SizedBox(width: 6),
                    Text(
                      combo.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: content,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StemIcon extends StatelessWidget {
  const _StemIcon({
    required this.stem,
    required this.on,
    required this.size,
    required this.color,
  });

  final Stem stem;
  final bool on;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => switch (stem) {
    Stem.vocals => Icon(
      on ? Icons.mic_rounded : Icons.mic_off_rounded,
      size: size,
      color: color,
    ),
    Stem.drums => _DrumGlyph(size: size, color: color, crossed: !on),
    Stem.instruments => Icon(
      on ? Icons.piano_rounded : Icons.piano_off_rounded,
      size: size,
      color: color,
    ),
  };
}

class _ComboIcon extends StatelessWidget {
  const _ComboIcon({required this.combo, required this.color});

  final StemCombo combo;
  final Color color;

  @override
  Widget build(BuildContext context) => switch (combo) {
    StemCombo.acapella => Icon(
      Icons.record_voice_over_rounded,
      size: 16,
      color: color,
    ),
    StemCombo.karaoke => Icon(
      Icons.mic_external_on_rounded,
      size: 16,
      color: color,
    ),
    StemCombo.drumsOnly => _DrumGlyph(size: 16, color: color),
  };
}

/// A snare and two sticks — Material has no drum. Drawn on the same 24-unit
/// grid and 2-unit stroke as the rounded icon set beside it.
class _DrumGlyph extends StatelessWidget {
  const _DrumGlyph({
    required this.size,
    required this.color,
    this.crossed = false,
  });

  final double size;
  final Color color;
  final bool crossed;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _DrumGlyphPainter(color: color, crossed: crossed),
  );
}

class _DrumGlyphPainter extends CustomPainter {
  const _DrumGlyphPainter({required this.color, required this.crossed});

  final Color color;
  final bool crossed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Head.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(12, 11), width: 16, height: 5.5),
      stroke,
    );
    // Shell and bottom rim.
    canvas.drawPath(
      Path()
        ..moveTo(4, 11)
        ..lineTo(4, 17.5)
        ..arcToPoint(
          const Offset(20, 17.5),
          radius: const Radius.elliptical(8, 2.75),
          clockwise: false,
        )
        ..lineTo(20, 11),
      stroke,
    );
    // Sticks, resting on the head.
    canvas.drawLine(const Offset(6.5, 3), const Offset(11, 7.6), stroke);
    canvas.drawLine(const Offset(17.5, 3), const Offset(13, 7.6), stroke);
    if (crossed) {
      canvas.drawLine(const Offset(3, 3), const Offset(21, 21), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DrumGlyphPainter old) =>
      old.color != color || old.crossed != crossed;
}

// =============================================================================
// First use: download, speed test, and the answers in between
// =============================================================================

class _Setup extends StatelessWidget {
  const _Setup({super.key, required this.controller, required this.stage});

  final StemsController controller;
  final StemsStage stage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: _content(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _size => '≈${(controller.totalBytes / 1e6).round()} MB';

  Widget _content(BuildContext context) {
    switch (stage) {
      case StemsStage.checking:
        return const Center(child: _Spinner());
      case StemsStage.needsDownload:
        return _SetupBlock(
          art: const _StemsArt(),
          title: 'Stems need a one-time download ($_size)',
          body:
              'Turn vocals, drums and instruments up or down while a song '
              'plays. It all runs on your phone; nothing is uploaded.',
          hint: const _Hint(icon: Icons.wifi_rounded, text: 'Best on Wi-Fi'),
          primary: _PrimaryButton(
            icon: Icons.download_rounded,
            label: 'Download',
            onPressed: controller.downloadModel,
          ),
        );
      case StemsStage.downloading:
      case StemsStage.verifying:
        return _SetupBlock(
          art: const _StemsArt(),
          title: stage == StemsStage.verifying
              ? 'Checking files…'
              : 'Downloading stems…',
          body:
              'You can keep listening, or leave this screen; it carries on '
              'while the app is open.',
          extra: _DownloadProgress(controller: controller, stage: stage),
          secondary: [
            TextButton(
              onPressed: controller.cancellingDownload
                  ? null
                  : controller.cancelDownload,
              style: _quietButtonStyle(context),
              child: Text(
                controller.cancellingDownload ? 'Cancelling…' : 'Cancel',
              ),
            ),
          ],
        );
      case StemsStage.downloadFailed:
        return _SetupBlock(
          art: const _HeroIcon(icon: Icons.cloud_off_rounded),
          title: "Download didn't finish",
          body: controller.modelError ?? 'Try again.',
          hint: const _Hint(icon: Icons.wifi_rounded, text: 'Best on Wi-Fi'),
          primary: _PrimaryButton(
            icon: Icons.refresh_rounded,
            label: 'Retry',
            onPressed: controller.downloadModel,
          ),
        );
      case StemsStage.testingDevice:
        return const _SetupBlock(
          art: _Spinner(),
          title: "Checking this phone's speed…",
          body: 'A few seconds, and only this once.',
        );
      case StemsStage.unsupported:
        final present = controller.modelPhase == StemsModelPhase.ready;
        return _SetupBlock(
          art: const _HeroIcon(icon: Icons.speed_rounded),
          title: "This phone isn't fast enough for live stems",
          body:
              'Splitting a song while it plays needs more processing power '
              'than this phone can spare. Everything else in Sound Effects '
              'works as usual.',
          secondary: [
            if (present)
              TextButton(
                onPressed: controller.deleteModel,
                style: _quietButtonStyle(context),
                child: Text(
                  'Free up ${(controller.totalBytes / 1e6).round()} MB',
                ),
              ),
            TextButton(
              onPressed: controller.retestDevice,
              style: _quietButtonStyle(context),
              child: const Text('Test again'),
            ),
          ],
        );
      case StemsStage.startFailed:
        return _SetupBlock(
          art: const _HeroIcon(icon: Icons.error_outline_rounded),
          title: "Stems couldn't start",
          body: controller.engineError ?? 'Something went wrong.',
          primary: _PrimaryButton(
            icon: Icons.refresh_rounded,
            label: 'Try again',
            onPressed: controller.retryEngine,
          ),
        );
      case StemsStage.mixer:
        return const SizedBox.shrink();
    }
  }
}

ButtonStyle _quietButtonStyle(BuildContext context) => TextButton.styleFrom(
  foregroundColor: _kAccent,
  disabledForegroundColor: Colors.white.withValues(alpha: 0.3),
  textStyle: Theme.of(context).textTheme.labelLarge
      ?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
);

class _SetupBlock extends StatelessWidget {
  const _SetupBlock({
    required this.art,
    required this.title,
    required this.body,
    this.extra,
    this.hint,
    this.primary,
    this.secondary = const [],
  });

  final Widget art;
  final String title;
  final String body;
  final Widget? extra;
  final Widget? hint;
  final Widget? primary;
  final List<Widget> secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        art,
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: Ember.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Ember.textSecondary,
          ),
        ),
        if (extra != null) ...[const SizedBox(height: 18), extra!],
        if (primary != null) ...[const SizedBox(height: 20), primary!],
        if (hint != null) ...[const SizedBox(height: 12), hint!],
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: secondary,
          ),
        ],
      ],
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.controller, required this.stage});

  final StemsController controller;
  final StemsStage stage;

  @override
  Widget build(BuildContext context) {
    final verifying = stage == StemsStage.verifying;
    final fraction = controller.downloadProgress;
    String mb(int bytes) => (bytes / 1e6).toStringAsFixed(1);
    final numbers = TextStyle(
      fontSize: 12,
      color: Colors.white.withValues(alpha: 0.6),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: verifying && fraction <= 0 ? null : fraction,
            minHeight: 6,
            color: _kAccent,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${mb(controller.downloadedBytes)} of '
                '${mb(controller.totalBytes)} MB',
                style: numbers,
              ),
            ),
            Text(
              '${(fraction * 100).floor()}%',
              style: numbers.copyWith(
                color: _kAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton.icon(
        onPressed: onPressed,
        // Gold carries dark content, never white.
        style: FilledButton.styleFrom(
          backgroundColor: _kAccent,
          foregroundColor: Ember.ground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ember.radiusControl + 2),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        icon: Icon(icon, size: 19),
        label: Text(label),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Ember.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 30,
    height: 30,
    child: CircularProgressIndicator(strokeWidth: 2.4, color: _kAccent),
  );
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Icon(icon, size: 28, color: Colors.white.withValues(alpha: 0.55)),
    );
  }
}

/// Three small faders at three levels: what the tab does, before it can.
class _StemsArt extends StatelessWidget {
  const _StemsArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Ember.accentWash,
        border: Border.all(color: _kAccent.withValues(alpha: 0.30)),
      ),
      child: const CustomPaint(painter: _StemsArtPainter()),
    );
  }
}

class _StemsArtPainter extends CustomPainter {
  const _StemsArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const levels = [0.85, 0.45, 0.65];
    const railW = 4.0;
    const gap = 10.0;
    const capW = 10.0;
    const capH = 3.5;
    final top = size.height * 0.27;
    final bottom = size.height * 0.73;
    final span = bottom - top;
    final left = size.width / 2 - gap;
    for (var i = 0; i < levels.length; i++) {
      final cx = left + i * gap;
      final y = bottom - levels[i] * span;
      canvas.drawRRect(
        RRect.fromLTRBR(
          cx - railW / 2,
          top,
          cx + railW / 2,
          bottom,
          const Radius.circular(railW / 2),
        ),
        Paint()..color = _kAccent.withValues(alpha: 0.18),
      );
      canvas.drawRRect(
        RRect.fromLTRBR(
          cx - railW / 2,
          y,
          cx + railW / 2,
          bottom,
          const Radius.circular(railW / 2),
        ),
        Paint()..color = _kAccent.withValues(alpha: 0.7),
      );
      canvas.drawRRect(
        RRect.fromLTRBR(
          cx - capW / 2,
          y - capH / 2,
          cx + capW / 2,
          y + capH / 2,
          const Radius.circular(1.5),
        ),
        Paint()..color = _kAccent,
      );
    }
  }

  @override
  bool shouldRepaint(_StemsArtPainter old) => false;
}
