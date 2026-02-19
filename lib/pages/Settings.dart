import 'dart:io';

import '/Helpers/AudioVisualizer.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '/widgets/Body.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wiredash/wiredash.dart';

import '/Helpers/AudioHandler.dart';
import '/widgets/BottomPlayer.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(builder: (context, controller, child) {
      return StreamBuilder(
        stream: context.read<HypeAudioHandler>().player.playingStream,
        builder: (context, service) {
          return Body(
            child: Scaffold(
              backgroundColor: controller.isFancy
                  ? Colors.transparent
                  : Theme.of(context).scaffoldBackgroundColor,
              appBar: AppBar(
                forceMaterialTransparency: controller.isFancy,
                title: const Text("Settings"),
              ),
              body: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  _buildPlaybackSection(controller),
                  const SizedBox(height: 12),
                  _buildAudioEnhancementSection(controller),
                  const SizedBox(height: 12),
                  _buildAppearanceSection(controller),
                  const SizedBox(height: 12),
                  _buildVisualizerSection(controller),
                  const SizedBox(height: 12),
                  _buildLibrarySection(),
                  const SizedBox(height: 12),
                  _buildAboutSection(context),
                  const SizedBox(height: 24),
                ],
              ),
              bottomNavigationBar: service.data ?? false
                  ? BottomPlayer(controller: controller)
                  : null,
            ),
          );
        },
      );
    });
  }

  // -- Section builder helpers --

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  // -- Playback Section --

  Widget _buildPlaybackSection(AppController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.headphones, "Playback"),
        _buildSectionCard([
          SwitchListTile.adaptive(
            value: controller.gaplessPlayback,
            title: const Text("Gapless playback"),
            subtitle: Text(controller.gaplessPlayback ? "Enabled" : "Disabled"),
            onChanged: (enabled) => controller.gaplessPlayback = enabled,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text("Crossfade"),
            subtitle: Text(
              controller.crossfadeDuration == 0
                  ? "Off"
                  : "${controller.crossfadeDuration}s",
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text("0s"),
                Expanded(
                  child: Slider.adaptive(
                    value: controller.crossfadeDuration.toDouble(),
                    min: 0,
                    max: 12,
                    divisions: 12,
                    label: "${controller.crossfadeDuration}s",
                    onChanged: (value) =>
                        controller.crossfadeDuration = value.toInt(),
                  ),
                ),
                const Text("12s"),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile.adaptive(
            value: controller.replayGain,
            title: const Text("Replay gain"),
            subtitle: const Text("Volume normalization via ID3 tags"),
            onChanged: (enabled) => controller.replayGain = enabled,
          ),
        ]),
      ],
    );
  }

  // -- Audio Enhancement Section --

  Widget _buildAudioEnhancementSection(AppController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.tune, "Audio Enhancement"),
        _buildSectionCard([
          SwitchListTile.adaptive(
            value: controller.dvcEnabled,
            title: const Text("Direct volume control"),
            subtitle: const Text("Hardware loudness enhancer"),
            onChanged: (enabled) => controller.dvcEnabled = enabled,
          ),
          if (controller.dvcEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: const Text("DVC Gain"),
              subtitle: Text("${controller.dvcGain.toStringAsFixed(1)} dB"),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text("-30"),
                  Expanded(
                    child: Slider.adaptive(
                      value: controller.dvcGain,
                      min: -30,
                      max: 30,
                      divisions: 60,
                      label: "${controller.dvcGain.toStringAsFixed(1)} dB",
                      onChanged: (value) => controller.dvcGain = value,
                    ),
                  ),
                  const Text("+30"),
                ],
              ),
            ),
          ],
        ]),
      ],
    );
  }

  // -- Appearance Section --

  Widget _buildAppearanceSection(AppController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.palette, "Appearance"),
        _buildSectionCard([
          SwitchListTile.adaptive(
            value: controller.isFancy,
            title: const Text("Fancy theme"),
            subtitle:
                Text(controller.isFancy ? "Fancy enabled" : "Fancy disabled"),
            onChanged: (enabled) => controller.isFancy = enabled,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text("Player blur"),
            subtitle: Text(
              "${((controller.blur / 500) * 100).toStringAsFixed(0)}%",
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider.adaptive(
              value: controller.blur,
              min: 0,
              max: 500,
              onChanged: (value) => controller.blur = value,
            ),
          ),
        ]),
      ],
    );
  }

  // -- Visualizer Section --

  static const _visualizerStyles = {
    'circular': ('Circular', Icons.circle_outlined),
    'bars': ('Spectrum', Icons.bar_chart_rounded),
    'sphere': ('Sphere', Icons.radio_button_unchecked),
    'flower': ('Plasma', Icons.blur_circular),
    'fabric': ('Fabric', Icons.texture),
    'sea': ('Ocean', Icons.water),
    'cube': ('Cube', Icons.view_in_ar),
    'ripple': ('Ripple', Icons.waves),
  };

  static const _visualizerColors = [
    (0xFFFFFFFF, 'White'),
    (0xFFD4A825, 'Gold'),
    (0xFF2196F3, 'Blue'),
    (0xFF9C27B0, 'Purple'),
    (0xFF4CAF50, 'Green'),
    (0xFFE91E63, 'Pink'),
    (0xFFFF5722, 'Orange'),
    (0xFF00BCD4, 'Cyan'),
  ];

  Widget _buildVisualizerSection(AppController controller) {
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.graphic_eq, "Visualizer"),
        _buildSectionCard([
          FutureBuilder<bool>(
            future: Visualizers.getEnabled(),
            builder: (context, snapshot) {
              return SwitchListTile.adaptive(
                value: controller.visuals,
                title: const Text("Enable visualizer"),
                subtitle:
                    Text(controller.visuals ? "Enabled" : "Disabled"),
                onChanged: (enabled) {
                  controller.visuals = enabled;
                  Visualizers.enableVisual(enabled);
                },
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile.adaptive(
            value: controller.playerVisual,
            title: const Text("Bottom player visualizer"),
            subtitle:
                Text(controller.playerVisual ? "Enabled" : "Disabled"),
            onChanged: (enabled) => controller.playerVisual = enabled,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile.adaptive(
            value: controller.isVisualInBackground,
            title: const Text("Background visualizer"),
            subtitle: Text(
                controller.isVisualInBackground ? "Enabled" : "Disabled"),
            onChanged: (enabled) =>
                controller.isVisualInBackground = enabled,
          ),
        ]),

        const SizedBox(height: 12),
        _buildSectionHeader(Icons.auto_awesome, "Visual Style"),
        _buildSectionCard([
          // Style selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text("Style",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _visualizerStyles.entries.map((entry) {
                final isSelected = controller.visualizerStyle == entry.key;
                return ChoiceChip(
                  avatar: Icon(entry.value.$2,
                      size: 16,
                      color: isSelected ? accent : null),
                  label: Text(entry.value.$1),
                  selected: isSelected,
                  onSelected: (_) =>
                      controller.visualizerStyle = entry.key,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Color picker
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text("Color",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _visualizerColors.map((pair) {
                final colorVal = pair.$1;
                final isSelected = controller.visualizerColor == colorVal;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => controller.visualizerColor = colorVal,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? accent : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Color(colorVal)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Frame rate slider
          ListTile(
            title: const Text("Frame rate"),
            subtitle: Text("${controller.visualizerFrameRate} fps"),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text("15"),
                Expanded(
                  child: Slider.adaptive(
                    value: controller.visualizerFrameRate.toDouble(),
                    min: 15,
                    max: 60,
                    divisions: 9,
                    label: "${controller.visualizerFrameRate} fps",
                    onChanged: (v) {
                      controller.visualizerFrameRate = v.toInt();
                      Visualizers.setFrameRate(v.toInt());
                    },
                  ),
                ),
                const Text("60"),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Reactivity slider
          ListTile(
            title: const Text("Reactivity"),
            subtitle: Text(_reactivityLabel(controller.visualizerReactivity)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Text("Smooth"),
                Expanded(
                  child: Slider.adaptive(
                    value: controller.visualizerReactivity,
                    min: 0.05,
                    max: 0.35,
                    divisions: 6,
                    onChanged: (v) =>
                        controller.visualizerReactivity = v,
                  ),
                ),
                const Text("Snappy"),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  String _reactivityLabel(double value) {
    if (value <= 0.08) return "Very smooth";
    if (value <= 0.12) return "Smooth";
    if (value <= 0.18) return "Balanced";
    if (value <= 0.25) return "Responsive";
    return "Snappy";
  }

  // -- Library Section --

  Widget _buildLibrarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.library_music, "Library"),
        _buildSectionCard([
          ListTile(
            title: const Text("Rescan library"),
            subtitle:
                const Text("Tap to rescan assets in case of missing files"),
            trailing: const Icon(Icons.refresh),
            onTap: () => Navigator.pushNamed(context, Routes.loader),
          ),
        ]),
      ],
    );
  }

  // -- About & Support Section --

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.info_outline, "About & Support"),
        _buildSectionCard([
          ListTile(
            title: const Text("About Hype Music"),
            subtitle:
                const Text("All you need to know about Hype Music"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutAppDialog(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text("Report a bug"),
            trailing: const Icon(Icons.bug_report_rounded),
            onTap: () =>
                Wiredash.of(context).show(inheritMaterialTheme: true),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text("Exit"),
            trailing: const Icon(Icons.exit_to_app),
            onTap: () => _showExitConfirmationDialog(),
          ),
        ]),
      ],
    );
  }

  // -- Dialogs --

  void _showAboutAppDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("About Hype Music"),
          content: const Text(
            "Hype Music is your ultimate music app, bringing you the best tunes, personalized playlists, and immersive audio experiences. "
            "Discover new songs, follow your favorite artists, and enjoy seamless music streaming with high-quality sound and a user-friendly interface. "
            "Join the hype and elevate your music journey with Hype Music!",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void _showExitConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Exit Hype Music"),
          content: const Text("Are you sure you want to exit?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => exit(0),
              child: const Text("Exit"),
            ),
          ],
        );
      },
    );
  }
}
