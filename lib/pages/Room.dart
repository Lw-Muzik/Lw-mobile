import 'package:eq_app/Helpers/Channel.dart';
import 'package:flutter/material.dart';

import '../widgets/RoundSlider.dart';

class RoomEffects extends StatefulWidget {
  const RoomEffects({super.key});

  @override
  State<RoomEffects> createState() => _RoomEffectsState();
}

class _RoomEffectsState extends State<RoomEffects> {
  bool isEnabled = false;

  int _reverbLevel = 100;
  List<Map<String, dynamic>> p = [
    {"name": "Small Room", "value": PresetReverb.SMALL_ROOM},
    {"name": "Large Hall", "value": PresetReverb.LARGE_HALL},
    {"name": "Large Room", "value": PresetReverb.LARGE_ROOM},
    {"name": "Medium Hall", "value": PresetReverb.MEDIUM_HALL},
    {"name": "Medium Room", "value": PresetReverb.MEDIUM_ROOM},
    {"name": "Plate", "value": PresetReverb.PRESET_PLATE},
    {"name": "None", "value": PresetReverb.NONE},
  ];
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        StreamBuilder<bool>(
            stream: Stream.fromFuture(Channel.isReverbEnabled()),
            builder: (context, snapshot) {
              bool? enabled = snapshot.data;
              if (enabled != null) {
                isEnabled = enabled;
              }
              return SwitchListTile.adaptive(
                value: isEnabled,
                onChanged: (x) {
                  setState(() {
                    isEnabled = !isEnabled;
                  });
                  Channel.enableReverb(isEnabled);
                  Channel.enablePresetReverb(isEnabled);
                  Channel.setDecayTime(17882);
                  Channel.setDensity(995);
                  Channel.setReflectionsDelay(300);
                  Channel.setReflectionsDelayLevel(-392);
                  Channel.setRoomLevel(-1975);
                  Channel.setRoomHFLevel(-2038);
                  Channel.setReverbDelay(100);
                  Channel.setDecayHFRatio(1875);
                },
                title: const Text("Room Effects"),
                subtitle: Text(isEnabled ? "Enabled" : "Disabled"),
              );
            }),

        // reverb level
        StreamBuilder<int>(
            stream: Stream.fromFuture(Channel.getReverbLevel()),
            builder: (context, reverbLevel) {
              int? rL = reverbLevel.data;
              if (rL != null) {
                _reverbLevel = rL;
              }
              return RoundSlider(
                width: 150,
                height: 150,
                title: "Reverb mix",
                onChanged: (c) {
                  setState(() {
                    _reverbLevel = c.toInt();
                  });
                  Channel.setReverbLevel(c.toInt());
                },
                value: _reverbLevel.toDouble(),
                max: 20000,
                min: -9000,
                dB: _reverbLevel.toDouble(),
              );
            }),
        const SizedBox(
          height: 20,
        ),
        Row(
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
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.4)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(10.0),
                child: Text("Room Presets"),
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
        ),
        Container(
          height: MediaQuery.of(context).size.width,
          margin: const EdgeInsets.only(right: 10, top: 10, left: 10),
          child: GridView.count(
            mainAxisSpacing: 10,
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            children: List.generate(
              p.length,
              (index) => InkWell(
                onTap: () {
                  Channel.setReverbPreset(p[index]["value"]);
                },
                child: Card(
                  child: Center(
                    child: Text("${p[index]['name']}"),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
