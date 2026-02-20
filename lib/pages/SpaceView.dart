import 'dart:ui';

import 'package:eq_app/Helpers/Channel.dart';
import 'package:eq_app/controllers/AppController.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/RoundSlider.dart';
import 'AudioFx.dart';

class SpaceView extends StatefulWidget {
  const SpaceView({super.key});

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  bool _effectsEnabled = false;
  bool _reverbEnabled = false;
  double _virtualizerStrength = 0;
  double _vocalBoost = 0;
  bool _loaded = false;

  final List<Map<String, dynamic>> _reverbPresets = [
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

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  Future<void> _loadInitialValues() async {
    final effectsOn = await Channel.getVirtualizerEnabled();
    final reverbOn = await Channel.isReverbEnabled();
    final vStrength = await Channel.getVirtualizerStrength();
    final tGain = await Channel.getTargetGain();
    if (mounted) {
      setState(() {
        _effectsEnabled = effectsOn;
        _reverbEnabled = reverbOn;
        _virtualizerStrength = vStrength.toDouble();
        _vocalBoost = tGain;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Effects section
        const SettingsHeader(title: "EFFECTS"),
        const SizedBox(height: 8),
        FancyCard(
          isFancy: controller.isFancy,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: const Text("Virtualizer & Loudness"),
                subtitle: Text(_effectsEnabled ? "Enabled" : "Disabled"),
                value: _effectsEnabled,
                onChanged: (value) {
                  setState(() => _effectsEnabled = value);
                  controller.enableEffects = value;
                  Channel.enableVirtualizer(value);
                  Channel.enableLoudnessEnhancer(value);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    RoundSlider(
                      title: "Virtualizer",
                      dB: double.parse(
                          (_virtualizerStrength / 1000 * 100).toStringAsFixed(1)),
                      value: _virtualizerStrength,
                      max: 1000,
                      width: 120,
                      height: 120,
                      min: 0,
                      onChanged: _effectsEnabled
                          ? (value) {
                              setState(() => _virtualizerStrength = value);
                              Channel.setVirtualizerStrength(value.toInt());
                            }
                          : (_) {},
                    ),
                    RoundSlider(
                      title: "Vocal Boost",
                      dB: double.parse(
                          (_vocalBoost / 1000 * 100).toStringAsFixed(1)),
                      value: _vocalBoost,
                      max: 1000,
                      width: 120,
                      height: 120,
                      min: 0,
                      onChanged: _effectsEnabled
                          ? (value) {
                              setState(() => _vocalBoost = value);
                              Channel.setTargetGain(value.toInt());
                            }
                          : (_) {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Room Effects section
        const SettingsHeader(title: "ROOM EFFECTS"),
        const SizedBox(height: 8),
        FancyCard(
          isFancy: controller.isFancy,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: const Text("Room Effects"),
                subtitle: Text(_reverbEnabled ? "Enabled" : "Disabled"),
                value: _reverbEnabled,
                onChanged: (value) {
                  setState(() => _reverbEnabled = value);
                  Channel.enableReverb(value);
                  if (value) {
                    Channel.setDecayTime(17882);
                    Channel.setDensity(995);
                    Channel.setReflectionsDelay(300);
                    Channel.setReflectionsDelayLevel(-392);
                    Channel.setRoomLevel(-1975);
                    Channel.setRoomHFLevel(-2038);
                    Channel.setReverbDelay(100);
                    Channel.setDecayHFRatio(1875);
                  }
                },
              ),
              const SizedBox(height: 8),
              _buildPresetsGrid(controller),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPresetsGrid(AppController controller) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: _reverbPresets.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.3,
      ),
      itemBuilder: (context, index) {
        final preset = _reverbPresets[index];
        bool isSelected = controller.selectedRoomPreset == index;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _reverbEnabled
              ? () {
                  controller.selectedRoomPreset = index;
                  Channel.setReverbPreset(preset["value"]);
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Center(
              child: Text(
                preset['name'],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}
