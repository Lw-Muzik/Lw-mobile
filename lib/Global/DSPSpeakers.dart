// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Helpers/Channel.dart';
import '/models/DSPSpeakerModel.dart';
import 'package:flutter/material.dart';

class DSPSpeakerWidget extends StatefulWidget {
  final AppController controller;
  final ScrollController dspScrollController;

  const DSPSpeakerWidget({
    super.key,
    required this.controller,
    required this.dspScrollController,
  });

  @override
  State<DSPSpeakerWidget> createState() => _DSPSpeakerWidgetState();
}

class _DSPSpeakerWidgetState extends State<DSPSpeakerWidget> {
  @override
  void initState() {
    super.initState();
    _initializeScrollPosition();
    _loadSelectedSpeaker();
  }

  void _initializeScrollPosition() {
    if (widget.dspScrollController.hasClients) {
      final offset = widget.dspScrollController.offset < 1000
          ? widget.controller.selectSpeaker * 50
          : widget.controller.selectSpeaker * 55;
      widget.dspScrollController.animateTo(
        offset.toDouble(),
        duration: const Duration(milliseconds: 900),
        curve: Curves.decelerate,
      );
    }
  }

  void _loadSelectedSpeaker() async {
    final prefs = await SharedPreferences.getInstance();
    context.read<AppController>().selectSpeaker =
        prefs.getInt("selectedSpeaker") ?? 0;
  }

  void _toggleViewMode() {
    setState(() {
      widget.controller.dspSpeakerView = !widget.controller.dspSpeakerView;
    });
  }

  Widget _buildViewModeSwitch(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Routes.pop(context),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 15),
              Text(
                widget.controller.dspSpeakerView ? "Grid View" : "List View",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          IconButton(
            onPressed: _toggleViewMode,
            icon: Icon(
              widget.controller.dspSpeakerView
                  ? Icons.grid_view_rounded
                  : Icons.list_rounded,
            ),
          ),
        ],
      ),
    );
  }

  void _onSpeakerSelected(int index, DSPSpeaker speaker) {
    widget.controller.selectSpeaker = index;
    Channel.setDSPSpeakers(speaker.freq, speaker.gain);
    widget.controller.spkName = speaker.name;
    Routes.pop(context);
  }

  Widget _buildSpeakerListTile(int index, DSPSpeaker speaker) {
    return ListTile(
      selected: widget.controller.selectSpeaker == index,
      selectedTileColor: Theme.of(context).primaryColorLight.withValues(alpha: 0.34),
      trailing: const Icon(Icons.surround_sound_rounded),
      leading: Icon(
        widget.controller.selectSpeaker == index
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: widget.controller.selectSpeaker == index
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text(speaker.name, style: Theme.of(context).textTheme.bodyLarge),
      onTap: () => _onSpeakerSelected(index, speaker),
    );
  }

  Widget _buildSpeakerGridTile(int index, DSPSpeaker speaker) {
    return InkWell(
      onTap: () => _onSpeakerSelected(index, speaker),
      child: GridTile(
        child: Card(
          margin: const EdgeInsets.all(10),
          color: widget.controller.selectSpeaker == index
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.34)
              : Theme.of(context).primaryColorLight.withValues(alpha: .5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.surround_sound_rounded, size: 55),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  speaker.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<DSPSpeaker>> _loadSpeakers() async {
    final speakersJson = await DSPSpeaker.loadSpksFromAssets();
    if (speakersJson.isEmpty) return [];

    final List<dynamic> data = jsonDecode(speakersJson)["speakers"];
    return [
      DSPSpeaker(
        id: 0,
        name: "Sony MDR-SA5000",
        freq: [33, 303, 948, 1490, 2853, 4531, 5799, 8666, 11880, 22050],
        gain: [6.4, 3.0, -4.0, 3.9, -11.2, -2.4, 5.2, -1.0, -4.5, -2.8],
      ),
      // Other static DSPSpeakers here...
      ...data.map(
        (e) => DSPSpeaker(
          id: 0,
          name: e["spk"],
          freq: e["freq"],
          gain: [5.8, 1.6, 1.0, 5.0, 5, 3, 5, 8, 4, 7],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, child) {
        return Column(
          children: [
            const SizedBox(height: 20),
            _buildViewModeSwitch(context),
            Expanded(
              child: FutureBuilder<List<DSPSpeaker>>(
                future: _loadSpeakers(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const CircularProgressIndicator();
                  final speakers = snapshot.data!;
                  return widget.controller.dspSpeakerView
                      ? GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 140,
                              ),
                          itemCount: speakers.length,
                          itemBuilder: (context, index) =>
                              _buildSpeakerGridTile(index, speakers[index]),
                        )
                      : ListView.builder(
                          controller: widget.dspScrollController,
                          itemCount: speakers.length,
                          itemBuilder: (context, index) =>
                              _buildSpeakerListTile(index, speakers[index]),
                        );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
