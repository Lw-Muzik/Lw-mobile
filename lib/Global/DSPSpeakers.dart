// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:eq_app/controllers/AppController.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Helpers/Channel.dart';
import '/models/DSPSpeakerModel.dart';
import 'package:flutter/material.dart';

class DSPSpeakerWidget extends StatefulWidget {
  final AppController controller;
  final ScrollController dspScrollController;

  const DSPSpeakerWidget(
      {super.key, required this.controller, required this.dspScrollController});

  @override
  State<DSPSpeakerWidget> createState() => _DSPSpeakerWidgetState();
}

class _DSPSpeakerWidgetState extends State<DSPSpeakerWidget> {
  @override
  void initState() {
    if (widget.dspScrollController.hasClients) {
      widget.dspScrollController.animateTo(
          widget.dspScrollController.offset < 1000
              ? widget.controller.selectSpeaker * 50
              : widget.controller.selectSpeaker * 55,
          duration: const Duration(milliseconds: 900),
          curve: Curves.decelerate);
    }
    SharedPreferences.getInstance().asStream().listen((event) {
      context.read<AppController>().selectSpeaker =
          event.getInt("selectedSpeaker") ?? 0;
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, x) {
      return FutureBuilder(
          future: DSPSpeaker.loadSpksFromAssets(),
          builder: (context, snapshot) {
            List<dynamic> tt = [];
            var st = snapshot.data;
            if (st != null) {
              tt = jsonDecode(st)["speakers"];
            }
            List<DSPSpeaker> SPEAKERS = [
              DSPSpeaker(
                freq: [
                  33,
                  303,
                  948,
                  1490,
                  2853,
                  4531,
                  5799,
                  8666,
                  11880,
                  22050
                ],
                gain: [6.4, 3.0, -4.0, 3.9, -11.2, -2.4, 5.2, -1.0, -4.5, -2.8],
                name: "Sony MDR-SA5000",
                id: 0,
              ),
              DSPSpeaker(
                freq: [19, 219, 892, 1160, 2115, 2643, 4920, 5256, 6539, 7492],
                gain: [6, 7, -12, 5, 6, -1, 0, 0, -2, 1],
                name: "BGVP DM6",
                id: 0,
              ),
              DSPSpeaker(
                freq: [11, 70, 195, 657, 1896, 2510, 2869, 3342, 6864, 16546],
                gain: [-9.6, 5.9, -4.8, 7.5, -5.7, 1.6, -1.7, 1.8, -3.0, 2.3],
                name: "Bang & Olufsen Beoplay H9",
                id: 0,
              ),
              DSPSpeaker(
                freq: [47, 162, 832, 2182, 4214, 5081, 6411, 7369, 9515, 16000],
                gain: [-4.5, -4.6, 4.4, 5.2, 3.9, 1.7, -5.1, 0.4, 1.7, 2.4],
                name: "JBL E25BT",
                id: 0,
              ),
              DSPSpeaker(
                freq: [31, 62, 125, 250, 916, 1000, 2000, 4000, 8000, 16000],
                gain: [10, 9, 3, 1, 1, 3, 5, 8, 4, 7],
                name: "Beats by Dr",
                id: 0,
              ),
              if (st != null)
                ...List.generate(
                  tt.length,
                  (index) => DSPSpeaker(
                    id: index,
                    freq: tt[index]["freq"],
                    gain: [8, 6, 1, 5, 5, 3, 5, 8, 4, 7],
                    name: tt[index]["spk"],
                  ),
                )
            ];

            return widget.controller.dspSpeakerView == false
                ? GridView.count(
                    // controller: widget.dspScrollController,
                    crossAxisCount: 3,
                    children: [
                      ...List.generate(
                        SPEAKERS.length,
                        (index) => InkWell(
                          onTap: () {
                            widget.controller.selectSpeaker = index;
                            Channel.setDSPSpeakers(
                              SPEAKERS[index].freq,
                              SPEAKERS[index].gain,
                            );
                          },
                          child: GridTile(
                            child: Card(
                              margin: const EdgeInsets.all(10),
                              color: widget.controller.selectSpeaker == index
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.34)
                                  : Theme.of(context)
                                      .primaryColorLight
                                      .withOpacity(0.5),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.surround_sound_rounded,
                                    size: 55,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      SPEAKERS[index].name,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    controller: widget.dspScrollController,
                    children: [
                      ...List.generate(
                        SPEAKERS.length,
                        (index) => RadioListTile(
                          selected: widget.controller.selectSpeaker == index,
                          selectedTileColor: Theme.of(context)
                              .primaryColorLight
                              .withOpacity(0.34),
                          secondary: const Icon(
                            Icons.surround_sound_rounded,
                          ),
                          title: Text(
                            SPEAKERS[index].name,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          value:
                              widget.controller.selectSpeaker == index ? 1 : 0,
                          groupValue: 1,
                          onChanged: (value) {
                            widget.controller.selectSpeaker = index;
                            Channel.setDSPSpeakers(
                              SPEAKERS[index].freq,
                              SPEAKERS[index].gain,
                            );
                            if (widget.dspScrollController.hasClients) {
                              // log("Scroll Offset ${widget.dspScrollController.offset}");
                              widget.dspScrollController.animateTo(
                                  widget.dspScrollController.offset < 1000
                                      ? index * 50
                                      : index * 55,
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.decelerate);
                            }
                          },
                        ),
                      ),
                    ],
                  );
          });
    });
  }
}
