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
  int selected = -1;
  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, child) {
      return Container(
        margin: const EdgeInsets.only(left: 10, right: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // SwitchListTile.adaptive(
            //   title: const Text("DSP Engine"),
            //   subtitle: Text(controller.enableDSP ? "Enabled" : "Disabled"),
            //   value: controller.enableDSP,
            //   onChanged: (x) {
            //     controller.enableDSP = x;

            //   },
            // ),
            Card(
              child: SizedBox(
                height: 300,
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
                      max: 50,
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
                      title: "Vocal Boost",
                      onChanged: (x) {
                        controller.dspOutGain = x;
                        Channel.setOutGain(x);
                      },
                      value: controller.dspOutGain,
                      max: 30,
                      min: 0,
                      dB: controller.dspOutGain.dps,
                    ),
                  ],
                ),
              ),
            ),

            // const Divider(),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "DSP Speakers",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SizedBox(
              height: 300,
              child: Card(
                child: ListView(
                  children: List.generate(
                    DSPSpeakers.SPEAKERS.length,
                    (index) => ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: RadioListTile(
                        selected: selected == index,
                        selectedTileColor: Theme.of(context)
                            .primaryColorLight
                            .withOpacity(0.34),
                        secondary: const Icon(Icons.surround_sound_rounded),
                        title: Text(
                          DSPSpeakers.SPEAKERS[index].name,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        value: selected == index ? 1 : 0,
                        groupValue: 1,
                        onChanged: (value) {
                          setState(
                            () {
                              selected = index;
                              Channel.setDSPSpeakers(
                                DSPSpeakers.SPEAKERS[index].freq,
                                DSPSpeakers.SPEAKERS[index].gain,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      );
    });
  }
}
