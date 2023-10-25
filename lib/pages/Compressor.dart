import 'dart:ui';

import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class CompressorView extends StatefulWidget {
  const CompressorView({super.key});

  @override
  State<CompressorView> createState() => _CompressorViewState();
}

class _CompressorViewState extends State<CompressorView> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(
          Radius.circular(20),
        ),
      ),
      child: Consumer<AppController>(builder: (context, controller, x) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Column(
            children: [
              Card(
                clipBehavior: Clip.hardEdge,
                elevation: controller.isFancy ? 0 : 2,
                color: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).cardColor,
                child: SizedBox(
                  height: 300,
                  child: BackdropFilter(
                    filter: controller.isFancy
                        ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
                        : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: Column(
                      children: [
                        HorizontalSlider(
                          title: "Threshold",
                          onChanged: (threshold) {
                            controller.threshold = threshold;
                            Channel.setDSPThreshold(threshold);
                          },
                          value: controller.threshold,
                          max: 0,
                          min: -50,
                          dB: "${controller.threshold.toStringAsFixed(2)} dB",
                        ),
                        HorizontalSlider(
                          title: "Attack",
                          onChanged: (attack) {
                            controller.attackTime = attack;
                            Channel.setAttackTime(attack);
                          },
                          value: controller.attackTime,
                          max: 100,
                          min: -40,
                          dB: "${controller.attackTime.toStringAsFixed(2)} ms",
                        ),
                        HorizontalSlider(
                          title: "Ratio",
                          onChanged: (ratio) {
                            controller.ratio = ratio;
                            Channel.setRatio(controller.ratio);
                          },
                          value: controller.ratio,
                          max: 100,
                          min: -20,
                          dB: controller.ratio.dps,
                        ),
                        HorizontalSlider(
                          title: "Release\n Time",
                          onChanged: (releaseTime) {
                            controller.releaseTime = releaseTime;
                            Channel.setReleaseTime(controller.releaseTime);
                          },
                          value: controller.releaseTime,
                          max: 150,
                          min: -20,
                          dB: "${controller.releaseTime.toStringAsFixed(2)} dB",
                        ),
                        HorizontalSlider(
                          title: "Noise \nThreshold",
                          onChanged: (x) {
                            controller.dspNoise = x;
                            Channel.setDspNoiseThreshold(x);
                          },
                          value: controller.dspNoise,
                          max: 50,
                          min: -100,
                          dB: controller.dspNoise.dps,
                        ),
                        HorizontalSlider(
                          title: "Knee Width",
                          onChanged: (x) {
                            controller.kneeWidth = x;
                            Channel.setDspKneeWidth(x);
                          },
                          value: controller.kneeWidth,
                          max: 15,
                          min: 0,
                          dB: controller.kneeWidth.dps,
                        ),
                        HorizontalSlider(
                          title: "Ratio Expander",
                          onChanged: (x) {
                            controller.expandRatio = x;
                            Channel.setDspExpandRatio(x);
                          },
                          value: controller.expandRatio,
                          max: 50,
                          min: -100,
                          dB: controller.expandRatio.dps,
                        ),
                        HorizontalSlider(
                          title: "Pre Gain",
                          onChanged: (x) {
                            controller.preGain = x;
                            Channel.setPreGain(x);
                          },
                          value: controller.dspNoise,
                          max: 30,
                          min: -20,
                          dB: controller.preGain.dps,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Card(
                color: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).cardColor,
                clipBehavior: Clip.hardEdge,
                elevation: controller.isFancy ? 0 : 2,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                child: BackdropFilter(
                  filter: controller.isFancy
                      ? ImageFilter.blur(sigmaX: 60, sigmaY: 60)
                      : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: ListTile(
                    title: const Text("Restore to default"),
                    leading: const Icon(Icons.restore),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      controller.threshold = -2.0;
                      controller.attackTime = 1.0;
                      controller.releaseTime = 60.0;
                      controller.ratio = 10.0;
                      controller.dspNoise = 0.0;
                      controller.expandRatio = 15.0;
                      controller.preGain = 20.0;
                      controller.kneeWidth = 0.4;

                      // config the system to default
                      Channel.setDSPThreshold(controller.threshold);
                      Channel.setAttackTime(controller.attackTime);
                      Channel.setReleaseTime(controller.releaseTime);
                      Channel.setRatio(controller.ratio);
                      Channel.setDspNoiseThreshold(controller.dspNoise);
                      Channel.setDspExpandRatio(controller.expandRatio);
                      Channel.setPreGain(controller.preGain);
                      Channel.setDspKneeWidth(controller.kneeWidth);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text("Restored to defaults"),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 1800),
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
