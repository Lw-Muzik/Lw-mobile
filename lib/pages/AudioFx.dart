import 'dart:ui';

import 'package:eq_app/Global/DSPSpeakers.dart';
import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/extensions/index.dart';
import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Routes/routes.dart';
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
              SizedBox(
                height: 50,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("AUDIOFX TUNE",
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox()
                    ],
                  ),
                ),
              ),

              const SizedBox.square(
                dimension: 20,
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
                    height: MediaQuery.of(context).size.width / 1.2,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox.square(
                            dimension: 20,
                          ),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // const Divider(),
              SizedBox(
                height: 50,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("DSP SPEAKERS",
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox()
                    ],
                  ),
                ),
              ),

              Card(
                color: controller.isFancy
                    ? Colors.transparent
                    : Theme.of(context).cardColor,
                clipBehavior: Clip.hardEdge,
                child: BackdropFilter(
                  filter: controller.isFancy
                      ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
                      : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Routes.animateTo(
                      closedWidget: ListTile(
                        title: Text(controller.spkName),
                        leading: const Icon(Icons.speaker),
                        trailing: const Icon(Icons.open_in_new),
                      ),
                      openWidget: DSPSpeakerWidget(
                          controller: controller,
                          dspScrollController: _controller),
                    ),
                  ),
                ),
              ),
              const SizedBox.square(
                dimension: 20,
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
                      Channel.showNativeMessage("Restored to defaults");
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
