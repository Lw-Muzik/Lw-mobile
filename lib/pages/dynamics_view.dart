import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';
import 'audio_fx.dart';

class DynamicsView extends StatelessWidget {
  const DynamicsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<AppController>(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        const SettingsHeader(title: "COMPRESSOR"),
        const SizedBox(height: 8),
        FancyCard(
          isFancy: controller.isFancy,
          child: Column(
            children: [
              _buildSlider(
                title: "Knee Width",
                min: 0,
                max: 100,
                value: controller.kneeWidth,
                onChanged: (val) {
                  controller.kneeWidth = val;
                  Channel.setDspKneeWidth(val);
                },
                dB: controller.kneeWidth.dps,
              ),
              _buildSlider(
                title: "Expander Ratio",
                min: 0,
                max: 90,
                value: controller.expandRatio,
                onChanged: (val) {
                  controller.expandRatio = val;
                  Channel.setDspExpandRatio(val);
                },
                dB: controller.expandRatio.dps,
              ),
              _buildSlider(
                title: "Pre Gain",
                min: -50,
                max: 50,
                value: controller.preGain,
                onChanged: (val) {
                  controller.preGain = val;
                  Channel.setPreGain(val);
                },
                dB: controller.preGain.dps,
              ),
              _buildSlider(
                title: "Noise Gate",
                min: -100,
                max: 0,
                value: controller.dspNoise,
                onChanged: (val) {
                  controller.dspNoise = val;
                  Channel.setDspNoiseThreshold(val);
                },
                dB: "${controller.dspNoise.toStringAsFixed(1)} dB",
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FancyCard(
          isFancy: controller.isFancy,
          child: ListTile(
            title: const Text("Restore defaults"),
            leading: const Icon(Icons.restore),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _restoreDefaults(controller);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("Dynamics restored to defaults"),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 1800),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _restoreDefaults(AppController controller) {
    controller.kneeWidth = 0.4;
    Channel.setDspKneeWidth(0.4);

    controller.expandRatio = 15.0;
    Channel.setDspExpandRatio(15.0);

    controller.preGain = 20.0;
    Channel.setPreGain(20.0);

    controller.dspNoise = -10.0;
    Channel.setDspNoiseThreshold(-10.0);
  }

  Widget _buildSlider({
    required String title,
    required double min,
    required double max,
    required double value,
    required ValueChanged<double> onChanged,
    required String dB,
  }) {
    return HorizontalSlider(
      title: title,
      onChanged: onChanged,
      value: value.clamp(min, max),
      max: max,
      min: min,
      dB: dB,
    );
  }
}
