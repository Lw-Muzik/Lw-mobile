import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import '../extensions/build_context_extension.dart';
import '../widgets/ToneKnob.dart';
import 'audio_fx.dart';

const Color _kAccent = Color(0xFFD4A825);

class ToneView extends StatelessWidget {
  const ToneView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderRow(context, controller),
              const SizedBox(height: 8),
              Expanded(
                child: FancyCard(
                  isFancy: controller.isFancy,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: controller.toneEnabled ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 250),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ToneKnob(
                            label: "BASS",
                            value: controller.bassGain,
                            activeColor: _kAccent,
                            size: context.isMobile ? 220 : 350,
                            onChanged: controller.toneEnabled
                                ? (v) => controller.bassGain = v
                                : (_) {},
                          ),
                          ToneKnob(
                            label: "TREBLE",
                            value: controller.trebleGain,
                            activeColor: const Color(0xFF5EC4D4),
                            size: context.isMobile ? 220 : 350,
                            onChanged: controller.toneEnabled
                                ? (v) => controller.trebleGain = v
                                : (_) {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(controller),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(BuildContext context, AppController controller) {
    return Row(
      children: [
        Icon(
          Icons.tune_rounded,
          size: 18,
          color: controller.toneEnabled
              ? _kAccent
              : Colors.white.withValues(alpha: 0.25),
        ),
        const SizedBox(width: 8),
        Text(
          "Tone Controls",
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        SizedBox(
          height: 28,
          child: Switch(
            value: controller.toneEnabled,
            activeTrackColor: _kAccent.withValues(alpha: 0.5),
            activeThumbColor: _kAccent,
            onChanged: (v) => controller.toneEnabled = v,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(AppController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _infoLabel(
          "Bass: ${controller.bassFreq.round()} Hz  Q ${controller.bassQ.toStringAsFixed(2)}",
        ),
        _infoLabel(
          "Treble: ${_formatFreq(controller.trebleFreq)}  Q ${controller.trebleQ.toStringAsFixed(2)}",
        ),
      ],
    );
  }

  Widget _infoLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: Colors.white.withValues(alpha: 0.35),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _formatFreq(double freq) {
    if (freq >= 1000) {
      final k = freq / 1000;
      return k == k.roundToDouble()
          ? '${k.round()} kHz'
          : '${k.toStringAsFixed(1)} kHz';
    }
    return '${freq.round()} Hz';
  }
}
