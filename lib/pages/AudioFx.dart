import 'dart:ui';

import 'package:eq_app/Global/DSPSpeakers.dart';
import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/AppController.dart';

class AudioFx extends StatefulWidget {
  const AudioFx({super.key});

  @override
  State<AudioFx> createState() => _AudioFxState();
}

class _AudioFxState extends State<AudioFx> {
  @override
  void initState() {
    super.initState();
  }

  int selected = -1;
  final ScrollController _controller = ScrollController();
  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, child) {
      return SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.only(left: 10, right: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                color: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).cardColor,
                clipBehavior: Clip.hardEdge,
                elevation: 0,
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
                      controller.dspOutGain = 3.0;
                      controller.dspPowerBass = 8.0;
                      controller.dspXTreble = 3.0;
                      controller.dspVolume = -6.0;
                      controller.dspXBass = 11.0;
                      // config the system to default
                      Channel.setDSPVolume(controller.dspVolume);
                      Channel.setDSPTreble(controller.dspXTreble);
                      Channel.setDSPPowerBass(controller.dspPowerBass);
                      Channel.setDSPXBass(controller.dspXBass);
                      Channel.setOutGain(controller.dspOutGain);
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
              Card(
                elevation: controller.isFancy ? 0 : 2,
                clipBehavior: Clip.hardEdge,
                color: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).cardColor,
                child: BackdropFilter(
                  filter: controller.isFancy
                      ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
                      : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: SizedBox(
                    height: 300,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          HorizontalSlider(
                            title: "Preamp",
                            onChanged: (x) {
                              controller.dspVolume = x;
                              Channel.setDSPVolume(x);
                            },
                            value: controller.dspVolume,
                            max: 20,
                            min: -20,
                            dB: controller.dspVolume.dps,
                          ),
                          // Xtreble
                          HorizontalSlider(
                            title: "XTreble",
                            onChanged: (x) {
                              controller.dspXTreble = x;
                              Channel.setDSPTreble(x);
                            },
                            value: controller.dspXTreble,
                            max: 20,
                            min: 0,
                            dB: controller.dspXTreble.dps,
                          ),
                          // power gain slider
                          HorizontalSlider(
                            title: "Power Bass",
                            onChanged: (x) {
                              controller.dspPowerBass = x;
                              Channel.setDSPPowerBass(x);
                            },
                            value: controller.dspPowerBass,
                            max: 30,
                            min: 0,
                            dB: controller.dspPowerBass.dps,
                          ),
                          // Xbass
                          HorizontalSlider(
                            title: "XBass",
                            onChanged: (x) {
                              controller.dspXBass = x;
                              Channel.setDSPXBass(x);
                            },
                            value: controller.dspXBass,
                            max: 25,
                            min: 0,
                            dB: controller.dspXBass.dps,
                          ),

                          // out gain
                          HorizontalSlider(
                            title: "Power Gain",
                            onChanged: (x) {
                              controller.dspOutGain = x;
                              Channel.setOutGain(x);
                            },
                            value: controller.dspOutGain,
                            max: 15,
                            min: 0,
                            dB: controller.dspOutGain.dps,
                          ),
                          HorizontalSlider(
                            title: "Noise \nThreshold",
                            onChanged: (x) {
                              controller.dspNoise = x;
                              Channel.setDspNoiseThreshold(x);
                            },
                            value: controller.dspNoise,
                            max: 30,
                            min: -20,
                            dB: controller.dspNoise.dps,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // const Divider(),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "DSP Speakers",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                          onPressed: () {
                            controller.dspSpeakerView =
                                !controller.dspSpeakerView;
                          },
                          icon: Icon(controller.dspSpeakerView
                              ? Icons.grid_view_rounded
                              : Icons
                                  .list_rounded)) //const Icon(Icons.grid_view_rounded))
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 300,
                child: Card(
                  color: controller.isFancy
                      ? Colors.transparent
                      : Theme.of(context).cardColor,
                  clipBehavior: Clip.hardEdge,
                  child: BackdropFilter(
                    filter: controller.isFancy
                        ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
                        : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: Scrollbar(
                        trackVisibility: true,
                        controller: _controller,
                        child: DSPSpeakerWidget(
                          controller: controller,
                          dspScrollController: _controller,
                        )),
                  ),
                ),
              )
            ],
          ),
        ),
      );
    });
  }
}
