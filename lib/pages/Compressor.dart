import 'dart:ui';

import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class CompressorView extends StatelessWidget {
  const CompressorView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<AppController>(context);

    return Container(
      height: 300,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildSectionHeader(context, "Sound Limiter"),
          _buildCard(
            controller,
            context,
            child: Column(
              children: [
                _buildSlider(
                  title: "Threshold",
                  min: -50,
                  max: 0,
                  value: controller.threshold,
                  onChanged: (val) {
                    controller.threshold = val;
                    Channel.setDSPThreshold(val);
                  },
                  dB: "${controller.threshold.toStringAsFixed(2)} dB",
                ),
                _buildSlider(
                  title: "Attack",
                  min: -100,
                  max: 100,
                  value: controller.attackTime,
                  onChanged: (val) {
                    controller.attackTime = val;
                    Channel.setAttackTime(val);
                  },
                  dB: "${controller.attackTime.toStringAsFixed(2)} dB",
                ),
                _buildSlider(
                  title: "Ratio",
                  min: -100,
                  max: 100,
                  value: controller.ratio,
                  onChanged: (val) {
                    controller.ratio = val;
                    Channel.setRatio(val);
                  },
                  dB: controller.ratio.dps,
                ),
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
                  title: "Ratio Expander",
                  min: -100,
                  max: 90,
                  value: controller.expandRatio,
                  onChanged: (val) {
                    controller.expandRatio = val;
                    Channel.setDspExpandRatio(val);
                  },
                  dB: controller.expandRatio.dps,
                ),
              ],
            ),
          ),
          _buildSectionHeader(context, "Bass Tuner"),
          _buildCard(
            controller,
            context,
            child: Column(
              children: [
                _buildSlider(
                  title: "Bass Shaper",
                  min: -100,
                  max: 100,
                  value: controller.dspNoise,
                  onChanged: (val) {
                    controller.dspNoise = val;
                    Channel.setDspNoiseThreshold(val);
                  },
                  dB: controller.dspNoise.dps,
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
              ],
            ),
          ),
          _buildRestoreDefaultsButton(context, controller),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox()
          ],
        ),
      ),
    );
  }

  Widget _buildCard(AppController controller, BuildContext context,
      {required Widget child}) {
    return Card(
      clipBehavior: Clip.hardEdge,
      elevation: controller.isFancy ? 0 : 2,
      color:
          controller.isFancy ? Colors.transparent : Theme.of(context).cardColor,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: controller.isFancy ? 20 : 0,
          sigmaY: controller.isFancy ? 20 : 0,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: child,
        ),
      ),
    );
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
      value: value,
      max: max,
      min: min,
      dB: dB,
    );
  }

  Widget _buildRestoreDefaultsButton(
      BuildContext context, AppController controller) {
    return FittedBox(
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Card(
          color: controller.isFancy
              ? Colors.transparent
              : Theme.of(context).cardColor,
          clipBehavior: Clip.hardEdge,
          elevation: controller.isFancy ? 0 : 2,
          margin: const EdgeInsets.all(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: controller.isFancy ? 60 : 0,
              sigmaY: controller.isFancy ? 60 : 0,
            ),
            child: ListTile(
              title: const Text("Restore to default"),
              leading: const Icon(Icons.restore),
              trailing: const Icon(Icons.open_in_new),
              onTap: () {
                // controller.resetToDefault();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("Restored to defaults"),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(milliseconds: 1800),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
