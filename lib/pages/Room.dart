import 'dart:ui';

import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/RoundSlider.dart';

class RoomEffects extends StatefulWidget {
  const RoomEffects({super.key});

  @override
  State<RoomEffects> createState() => _RoomEffectsState();
}

class _RoomEffectsState extends State<RoomEffects> {
  bool isEnabled = false;
  int _reverbLevel = 100;

  final List<Map<String, dynamic>> presets = [
    {"name": "Small Room", "value": PresetReverb.SMALL_ROOM},
    {"name": "Large Hall", "value": PresetReverb.LARGE_HALL},
    {"name": "Large Room", "value": PresetReverb.LARGE_ROOM},
    {"name": "Medium Hall", "value": PresetReverb.MEDIUM_HALL},
    {"name": "Medium Room", "value": PresetReverb.MEDIUM_ROOM},
    {"name": "Plate", "value": PresetReverb.PRESET_PLATE},
    {"name": "Concert", "value": PresetReverb.CONCERT},
    {"name": "Arena", "value": PresetReverb.PRESET_ARENA},
    {"name": "Scene", "value": PresetReverb.SCENE},
  ];

  void _toggleReverb(bool value) {
    setState(() {
      isEnabled = value;
    });
    Channel.enableReverb(value);
    // Channel.enablePresetReverb(value);

    // Apply default reverb settings
    Channel.setDecayTime(17882);
    Channel.setDensity(995);
    Channel.setReflectionsDelay(300);
    Channel.setReflectionsDelayLevel(-392);
    Channel.setRoomLevel(-1975);
    Channel.setRoomHFLevel(-2038);
    Channel.setReverbDelay(100);
    Channel.setDecayHFRatio(1875);
  }

  @override
  Widget build(BuildContext context) {
    var controller = Provider.of<AppController>(context);
    return ListView(
      children: [
        _buildReverbSwitch(),
        // _buildReverbLevelSlider(),
        _buildDividerWithLabel(context, "Room Presets"),
        _buildPresetsGrid(controller),
      ],
    );
  }

  Widget _buildReverbSwitch() {
    return FittedBox(
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: FutureBuilder<bool>(
          future: Channel.isReverbEnabled(),
          builder: (context, snapshot) {
            isEnabled = snapshot.data ?? isEnabled;
            return SwitchListTile.adaptive(
              value: isEnabled,
              onChanged: _toggleReverb,
              title: const Text("Room Effects"),
              subtitle: Text(isEnabled ? "Enabled" : "Disabled"),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReverbLevelSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 120, vertical: 10),
      child: StreamBuilder<int>(
        stream: Stream.fromFuture(Channel.getReverbLevel()),
        builder: (context, reverbLevel) {
          int? level = reverbLevel.data;
          if (level != null) {
            _reverbLevel = level;
          }
          return RoundSlider(
            width: 150,
            height: 150,
            title: "Reverb Mix",
            value: _reverbLevel.toDouble(),
            max: 20000,
            min: -9000,
            dB: ((_reverbLevel / 20000) * 100).toDouble(),
            onChanged: (c) {
              setState(() {
                _reverbLevel = c.toInt();
              });
              Channel.setReverbLevel(c.toInt());
            },
          );
        },
      ),
    );
  }

  Widget _buildDividerWithLabel(BuildContext context, String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Divider(
            thickness: 2,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
          ),
        ),
        Card(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Text(label),
          ),
        ),
        SizedBox(
          width: 120,
          child: Divider(
            thickness: 2,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsGrid(AppController controller) {
    return FittedBox(
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width,
        child: Card(
          clipBehavior: Clip.hardEdge,
          color: controller.isFancy
              ? Colors.transparent
              : Theme.of(context).cardColor,
          margin: const EdgeInsets.all(10),
          child: BackdropFilter(
            filter: controller.isFancy
                ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: presets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final preset = presets[index];
                bool isSelected = controller.selectedRoomPreset == index;
                return InkWell(
                  onTap: () {
                    controller.selectedRoomPreset = index;
                    Channel.setReverbPreset(preset["value"]);
                  },
                  child: Card(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).primaryColorLight.withOpacity(0.4),
                    child: Center(
                      child: Text(
                        preset['name'],
                        style: Theme.of(context).textTheme.labelLarge!.apply(
                              color: isSelected ? Colors.black : Colors.white,
                            ),
                      ),
                    ),
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
