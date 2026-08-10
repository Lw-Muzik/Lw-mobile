import 'dart:io';
import 'dart:typed_data';

import '/Helpers/AudioVisualizer.dart';
import '/Helpers/Channel.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '/widgets/Body.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiredash/wiredash.dart';

import '../models/eq_models.dart';
import '../onboarding/coach_marks.dart';
import '../onboarding/interactions_guide.dart';
import '../services/streaming_data_guard.dart';
import '../services/share_service.dart';
import 'stream_server.dart';

import '/Helpers/AudioHandler.dart';
import '/widgets/BottomPlayer.dart';
import '../services/ytmusic/yt_playback.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool _scanning = false;
  int _scanCurrent = 0;
  int _scanTotal = 0;
  String _scanSongName = '';
  int? _scanResult;

  @override
  void initState() {
    super.initState();
    // The Autoplay switch below reads a field that starts at its default, so
    // without this it shows "on" to a user who turned it off in an earlier
    // session and never opened Discover this run.
    YtRadioQueue.instance.loadPreference().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, child) {
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    if (Platform.isAndroid) ...[
                      _buildAppModeSection(controller),
                      const SizedBox(height: 12),
                    ],
                    if (!controller.isEqMode) ...[
                      _buildPlaybackSection(controller),
                      const SizedBox(height: 12),
                      _buildAudioEnhancementSection(controller),
                      const SizedBox(height: 12),
                    ],
                    if (controller.globalEqAvailable) ...[
                      _buildGlobalEqSection(controller),
                      const SizedBox(height: 12),
                    ],
                    _buildEqualizerSection(controller),
                    const SizedBox(height: 12),
                    _buildToneSection(controller),
                    const SizedBox(height: 12),
                    if (!controller.isEqMode) ...[
                      _buildAppearanceSection(controller),
                      const SizedBox(height: 12),
                      _buildVisualizerSection(controller),
                      const SizedBox(height: 12),
                      _buildLibrarySection(),
                      const SizedBox(height: 12),
                      _buildCloudStorageSection(controller),
                      const SizedBox(height: 12),
                      _buildPhoneLinkSection(),
                      const SizedBox(height: 12),
                      _buildStreamingSection(),
                      const SizedBox(height: 12),
                    ],
                    _buildAboutSection(context),
                    const SizedBox(height: 24),
                  ],
                ),
                bottomNavigationBar:
                    !controller.isEqMode && (service.data ?? false)
                    ? BottomPlayer(controller: controller)
                    : null,
              ),
            );
          },
        );
      },
    );
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

  // -- App Mode Section --

  Widget _buildAppModeSection(AppController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.swap_horiz, "App Mode"),
        _buildSectionCard([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<AppMode>(
              segments: const [
                ButtonSegment<AppMode>(
                  value: AppMode.musicPlayer,
                  label: Text('Music Player'),
                  icon: Icon(Icons.headphones_rounded),
                ),
                ButtonSegment<AppMode>(
                  value: AppMode.equalizer,
                  label: Text('Equalizer'),
                  icon: Icon(Icons.equalizer_rounded),
                ),
              ],
              selected: {controller.appMode},
              onSelectionChanged: (values) {
                controller.appMode = values.first;
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.15),
                selectedForegroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Switch between full music player and EQ-only mode',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ]),
      ],
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
                    max: 30,
                    divisions: 30,
                    label: "${controller.crossfadeDuration}s",
                    onChanged: (value) =>
                        controller.crossfadeDuration = value.toInt(),
                  ),
                ),
                const Text("30s"),
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
          const Divider(height: 1, indent: 16, endIndent: 16),
          // Gates every radio request Discover would otherwise make — with this
          // off, no related-track fetching happens at all.
          SwitchListTile.adaptive(
            value: YtRadioQueue.instance.enabled,
            title: const Text("Autoplay"),
            subtitle: const Text(
              "Keep playing related tracks when a Discover queue ends",
            ),
            onChanged: (enabled) async {
              await YtRadioQueue.instance.setEnabled(enabled);
              if (mounted) setState(() {});
            },
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
            subtitle: const Text(
              "Bypasses system volume for higher fidelity audio output",
            ),
            onChanged: (enabled) {
              if (enabled && !controller.dvcEnabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("System volume will be set to maximum"),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
              controller.dvcEnabled = enabled;
            },
          ),
          if (controller.dvcEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: const Text("DVC Volume"),
              subtitle: Text(
                "${((controller.dvcGain + 30) / 30 * 100).round()}%",
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text("0%"),
                  Expanded(
                    child: Slider.adaptive(
                      value: controller.dvcGain,
                      min: -30,
                      max: 0,
                      divisions: 20,
                      label:
                          "${((controller.dvcGain + 30) / 30 * 100).round()}%",
                      onChanged: (value) => controller.dvcGain = value,
                    ),
                  ),
                  const Text("100%"),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "System volume set to MAX. Use hardware buttons or this slider to control volume.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile.adaptive(
              value: controller.dvcFineSteps,
              title: const Text("Fine volume steps"),
              subtitle: const Text("1% steps instead of 5% (hardware buttons)"),
              onChanged: (value) => controller.dvcFineSteps = value,
            ),
          ],
        ]),
      ],
    );
  }

  // -- Global EQ Section --

  Widget _buildGlobalEqSection(AppController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.public, "Global Equalizer"),
        _buildSectionCard([
          SwitchListTile.adaptive(
            value: controller.globalEqEnabled,
            title: const Text("System-wide EQ"),
            subtitle: Text(
              controller.globalEqEnabled
                  ? "Active — EQ applied to all apps"
                  : "Off",
            ),
            onChanged: (enabled) {
              if (enabled) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Enable Global EQ?"),
                    content: const Text(
                      "Your EQ, tone, and limiter settings will be applied to audio from other apps (Spotify, YouTube Music, etc.).\n\n"
                      "A persistent notification will appear while active.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Cancel"),
                      ),
                      FilledButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          controller.globalEqEnabled = true;
                          // Prompt for battery optimization if not already disabled
                          final isDisabled =
                              await Channel.isBatteryOptimizationDisabled();
                          if (!isDisabled && mounted) {
                            _showBatteryOptimizationPrompt();
                          }
                        },
                        child: const Text("Enable"),
                      ),
                    ],
                  ),
                );
              } else {
                controller.globalEqEnabled = false;
              }
            },
          ),
          if (controller.globalEqEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "EQ, tone, and limiter changes sync to other apps in real-time. "
                      "Parametric EQ, MBC, reverb, and stereo effects are not applied globally.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _buildPlayingAppsRow(controller),
          ],
        ]),
      ],
    );
  }

  void _showBatteryOptimizationPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Disable Battery Optimization"),
        content: const Text(
          "To prevent Android from stopping Hype in the background, "
          "please allow unrestricted battery usage.\n\n"
          "This keeps your EQ and music playing without interruption.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Later"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Channel.requestDisableBatteryOptimization();
            },
            child: const Text("Allow"),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayingAppsRow(AppController controller) {
    final apps = controller.playingApps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: Row(
            children: [
              Icon(
                Icons.apps,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Apps currently playing",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: "Refresh",
                visualDensity: VisualDensity.compact,
                onPressed: () => controller.refreshPlayingApps(),
              ),
            ],
          ),
        ),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              "None detected",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          )
        else
          ...apps.map(
            (app) => _AppIconTile(
              packageName: app['package'] ?? '',
              appName: app['name'] ?? app['package'] ?? '',
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  // -- Equalizer Section --

  Widget _buildEqualizerSection(AppController controller) {
    final bandCount = controller.eqBandCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.equalizer, "Equalizer"),
        _buildSectionCard([
          ListTile(
            title: const Text("Band count"),
            subtitle: Text("$bandCount bands"),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SegmentedButton<int>(
              segments: BandMapping.supportedCounts
                  .map((c) => ButtonSegment<int>(value: c, label: Text('$c')))
                  .toList(),
              selected: {bandCount},
              onSelectionChanged: (values) {
                controller.eqBandCount = values.first;
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.15),
                selectedForegroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ]),
      ],
    );
  }

  // -- Tone Settings Section --

  Widget _buildToneSection(AppController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.tune, "Tone Controls"),
        _buildSectionCard([
          SwitchListTile.adaptive(
            value: controller.toneEnabled,
            title: const Text("Tone controls"),
            subtitle: Text(
              controller.toneEnabled ? "Bass & treble active" : "Disabled",
            ),
            onChanged: (enabled) => controller.toneEnabled = enabled,
          ),
          if (controller.toneEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Bass settings
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12),
              child: Text(
                "Bass",
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              dense: true,
              title: const Text("Frequency"),
              subtitle: Text("${controller.bassFreq.round()} Hz"),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider.adaptive(
                value: controller.bassFreq,
                min: 20,
                max: 250,
                divisions: 23,
                onChanged: (v) => controller.bassFreq = v,
              ),
            ),
            ListTile(
              dense: true,
              title: const Text("Q Factor"),
              subtitle: Text(controller.bassQ.toStringAsFixed(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider.adaptive(
                value: controller.bassQ,
                min: 0.1,
                max: 2.0,
                divisions: 19,
                onChanged: (v) => controller.bassQ = v,
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Treble settings
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12),
              child: Text(
                "Treble",
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              dense: true,
              title: const Text("Frequency"),
              subtitle: Text("${controller.trebleFreq.round()} Hz"),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider.adaptive(
                value: controller.trebleFreq,
                min: 5000,
                max: 15000,
                divisions: 10,
                onChanged: (v) => controller.trebleFreq = v,
              ),
            ),
            ListTile(
              dense: true,
              title: const Text("Q Factor"),
              subtitle: Text(controller.trebleQ.toStringAsFixed(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Slider.adaptive(
                value: controller.trebleQ,
                min: 0.1,
                max: 2.0,
                divisions: 19,
                onChanged: (v) => controller.trebleQ = v,
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Output limiter
            SwitchListTile.adaptive(
              value: controller.limiterEnabled,
              title: const Text("Output limiter"),
              subtitle: const Text("Prevents distortion from EQ boosts"),
              onChanged: (enabled) => controller.limiterEnabled = enabled,
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
            subtitle: Text(
              controller.isFancy ? "Fancy enabled" : "Fancy disabled",
            ),
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

  static Map<String, (String, IconData)> get _visualizerStyles => {
    'radial': ('Radial', Icons.flare_rounded),
    'bars': ('Spectrum', Icons.bar_chart_rounded),
    'mirror_bars': ('Mirror', Icons.align_vertical_center_rounded),
    'line': ('Waveform', Icons.show_chart_rounded),
    'terrain': ('Terrain', Icons.terrain_rounded),
    'dots': ('Matrix', Icons.grid_on_rounded),
    'silk': ('Silk', Icons.animation_rounded),
    'lissajous': ('Lissajous', Icons.all_inclusive_rounded),
    'windmill': ('Windmill', Icons.rotate_right_rounded),
    if (!Platform.isIOS) 'milkdrop': ('MilkDrop', Icons.blur_on_rounded),
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
        // No master "Enable visualizer" switch: these two rows ARE the switch.
        // Turning either on starts the native capture, turning both off stops
        // it. A third control could only disagree with them.
        _buildSectionCard([
          SwitchListTile.adaptive(
            value: controller.playerVisual,
            title: const Text("Bottom player visualizer"),
            subtitle: Text(controller.playerVisual ? "Enabled" : "Disabled"),
            onChanged: (enabled) => controller.playerVisual = enabled,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile.adaptive(
            value: controller.isVisualInBackground,
            title: const Text("Background visualizer"),
            subtitle: Text(
              controller.isVisualInBackground ? "Enabled" : "Disabled",
            ),
            onChanged: (enabled) => controller.isVisualInBackground = enabled,
          ),
        ]),

        const SizedBox(height: 12),
        _buildSectionHeader(Icons.auto_awesome, "Visual Style"),
        _buildSectionCard([
          // Style selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              "Style",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _visualizerStyles.entries.map((entry) {
                final isSelected = controller.visualizerStyle == entry.key;
                return ChoiceChip(
                  avatar: Icon(
                    entry.value.$2,
                    size: 16,
                    color: isSelected ? accent : null,
                  ),
                  label: Text(entry.value.$1),
                  selected: isSelected,
                  onSelected: (_) => controller.visualizerStyle = entry.key,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Color picker
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              "Color",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
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
                                  color: Color(colorVal).withValues(alpha: 0.4),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text("Smooth"),
                Expanded(
                  child: Slider.adaptive(
                    value: controller.visualizerReactivity,
                    min: 0.05,
                    max: 0.35,
                    divisions: 6,
                    onChanged: (v) {
                      controller.visualizerReactivity = v;
                      // Sync to C++ FFT smoothing: attack = reactivity, decay = reactivity * 0.7
                      Visualizers.setSmoothing(v, v * 0.7);
                    },
                  ),
                ),
                const Text("Snappy"),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Beat sensitivity slider
          ListTile(
            title: const Text("Beat sensitivity"),
            subtitle: Text(
              _beatSensitivityLabel(controller.visualizerBeatSensitivity),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Text("Subtle"),
                Expanded(
                  child: Slider.adaptive(
                    value: controller.visualizerBeatSensitivity,
                    min: 0.5,
                    max: 3.0,
                    divisions: 10,
                    onChanged: (v) {
                      controller.visualizerBeatSensitivity = v;
                      Visualizers.setGain(v);
                    },
                  ),
                ),
                const Text("Intense"),
              ],
            ),
          ),
        ]),

        // MilkDrop settings (Android only, shown when milkdrop style is active)
        if (!Platform.isIOS && controller.visualizerStyle == 'milkdrop') ...[
          const SizedBox(height: 12),
          _buildSectionHeader(Icons.blur_on_rounded, "MilkDrop"),
          _buildSectionCard([
            ListTile(
              title: const Text("Render quality"),
              subtitle: Text(_milkdropQualityLabel(controller.milkdropQuality)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text("Low")),
                  ButtonSegment(value: 1, label: Text("Med")),
                  ButtonSegment(value: 2, label: Text("High")),
                  ButtonSegment(value: 3, label: Text("Ultra")),
                ],
                selected: {controller.milkdropQuality},
                onSelectionChanged: (s) {
                  controller.milkdropQuality = s.first;
                },
                showSelectedIcon: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                "Restart visualizer for changes to take effect",
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: const Text("Render FPS"),
              subtitle: Text("${controller.milkdropFps} fps"),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text("15"),
                  Expanded(
                    child: Slider.adaptive(
                      value: controller.milkdropFps.toDouble(),
                      min: 15,
                      max: 60,
                      divisions: 9,
                      label: "${controller.milkdropFps} fps",
                      onChanged: (v) {
                        controller.milkdropFps = v.toInt();
                      },
                    ),
                  ),
                  const Text("60"),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: const Text("Beat sensitivity"),
              subtitle: Text(
                _beatSensitivityLabel(controller.milkdropBeatSensitivity),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text("Low"),
                  Expanded(
                    child: Slider.adaptive(
                      value: controller.milkdropBeatSensitivity,
                      min: 0.2,
                      max: 3.0,
                      divisions: 14,
                      onChanged: (v) {
                        controller.milkdropBeatSensitivity = v;
                      },
                    ),
                  ),
                  const Text("High"),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: const Text("Preset auto-cycle"),
              subtitle: Text(
                controller.milkdropPresetDuration > 0
                    ? "${controller.milkdropPresetDuration.toInt()}s"
                    : "Manual only",
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Text("Off"),
                  Expanded(
                    child: Slider.adaptive(
                      value: controller.milkdropPresetDuration,
                      min: 0,
                      max: 120,
                      divisions: 12,
                      onChanged: (v) {
                        controller.milkdropPresetDuration = v;
                      },
                    ),
                  ),
                  const Text("120s"),
                ],
              ),
            ),
          ]),
        ],
      ],
    );
  }

  String _milkdropQualityLabel(int quality) {
    const labels = [
      "Low (480p)",
      "Medium (720p)",
      "High (1080p)",
      "Ultra (native)",
    ];
    return labels[quality.clamp(0, 3)];
  }

  String _beatSensitivityLabel(double value) {
    if (value <= 0.7) return "Subtle";
    if (value <= 1.1) return "Normal";
    if (value <= 1.7) return "Energetic";
    if (value <= 2.3) return "Punchy";
    return "Intense";
  }

  String _reactivityLabel(double value) {
    if (value <= 0.08) return "Very smooth";
    if (value <= 0.12) return "Smooth";
    if (value <= 0.18) return "Balanced";
    if (value <= 0.25) return "Responsive";
    return "Snappy";
  }

  // -- Streaming Section --

  Widget _buildStreamingSection() {
    final guard = StreamingDataGuard.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.wifi_rounded, "Streaming"),
        _buildSectionCard([
          SwitchListTile(
            secondary: const Icon(Icons.data_saver_on_rounded),
            title: const Text("Data Saver"),
            subtitle: const Text(
              "Skip background caching on cellular — only buffer what you listen to",
            ),
            value: guard.dataSaver,
            onChanged: (v) {
              setState(() => guard.dataSaver = v);
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.cell_tower_rounded),
            title: const Text("Stream on Cellular"),
            subtitle: const Text("Allow streaming when not on WiFi"),
            value: guard.streamOnCellular,
            onChanged: (v) {
              setState(() => guard.streamOnCellular = v);
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: const Text("Cellular Data Limit"),
            subtitle: Text(
              guard.cellularLimitMB > 0
                  ? "${guard.cellularLimitMB} MB per session"
                  : "Unlimited",
            ),
            trailing: DropdownButton<int>(
              value: guard.cellularLimitMB,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text("Unlimited")),
                DropdownMenuItem(value: 50, child: Text("50 MB")),
                DropdownMenuItem(value: 100, child: Text("100 MB")),
                DropdownMenuItem(value: 200, child: Text("200 MB")),
                DropdownMenuItem(value: 500, child: Text("500 MB")),
              ],
              onChanged: (v) {
                if (v != null) setState(() => guard.cellularLimitMB = v);
              },
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.download_rounded),
            title: const Text("Prefetch Next Track"),
            subtitle: Text(
              guard.prefetchOnlyOnWifi
                  ? "Pre-downloads next song on WiFi only"
                  : "Full file on WiFi, first 30s on cellular",
            ),
            value: guard.prefetchNextTrack,
            onChanged: (v) {
              setState(() => guard.prefetchNextTrack = v);
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_lock_rounded),
            title: const Text("Prefetch on WiFi Only"),
            subtitle: const Text("Only prefetch when connected to WiFi"),
            value: guard.prefetchOnlyOnWifi,
            onChanged: (v) {
              setState(() => guard.prefetchOnlyOnWifi = v);
            },
          ),
          if (guard.cellularBytesUsed > 0 || guard.totalCellularBytes > 0) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded),
              title: const Text("Cellular Data Used"),
              subtitle: Text(
                "Session: ${guard.cellularUsageFormatted} · Total: ${guard.totalCellularFormatted}",
              ),
            ),
          ],
        ]),
      ],
    );
  }

  // -- Cloud Storage Section --

  Widget _buildCloudStorageSection(AppController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.cloud_rounded, "Cloud Storage"),
        _buildSectionCard([
          ListTile(
            leading: const Icon(Icons.cloud_rounded),
            title: const Text("Google Drive"),
            subtitle: Text(
              controller.isGoogleConnected ? "Connected" : "Not connected",
            ),
            trailing: FilledButton.tonal(
              onPressed: () async {
                if (controller.isGoogleConnected) {
                  await controller.disconnectGoogle();
                } else {
                  await controller.connectGoogle();
                }
              },
              child: Text(
                controller.isGoogleConnected ? "Disconnect" : "Connect",
              ),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.cloud_circle_rounded),
            title: const Text("Dropbox"),
            subtitle: Text(
              controller.isDropboxConnected ? "Connected" : "Not connected",
            ),
            trailing: FilledButton.tonal(
              onPressed: () async {
                if (controller.isDropboxConnected) {
                  await controller.disconnectDropbox();
                } else {
                  await controller.connectDropbox();
                }
              },
              child: Text(
                controller.isDropboxConnected ? "Disconnect" : "Connect",
              ),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.storage_rounded),
            title: const Text("Audio cache"),
            subtitle: Text(controller.cloudCache.currentSizeFormatted),
            trailing: TextButton(
              onPressed: () async {
                await controller.cloudCache.clearCache();
                setState(() {});
              },
              child: const Text("Clear"),
            ),
          ),
        ]),
      ],
    );
  }

  // -- Phone Link Section --

  Widget _buildPhoneLinkSection() {
    final server = ShareService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.cast_rounded, "Stream to Desktop"),
        _buildSectionCard([
          ListTile(
            leading: const Icon(Icons.cast_rounded),
            title: const Text("Stream to desktop"),
            subtitle: Text(
              server.running
                  ? "Sharing — open the Phone tab on your computer"
                  : "Play this phone's music on the HypeMuzik desktop app",
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Routes.routeTo(const StreamServerPage(), context),
          ),
        ]),
      ],
    );
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
            subtitle: const Text(
              "Tap to rescan assets in case of missing files",
            ),
            trailing: const Icon(Icons.refresh),
            onTap: () => Navigator.pushNamed(context, Routes.loader),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          if (_scanning) ...[
            ListTile(
              leading: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
              title: Text("Identifying $_scanCurrent of $_scanTotal"),
              subtitle: Text(
                _scanSongName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LinearProgressIndicator(
                value: _scanTotal > 0 ? _scanCurrent / _scanTotal : 0,
              ),
            ),
          ] else if (_scanResult != null) ...[
            ListTile(
              leading: Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text("Identified $_scanResult tracks"),
              subtitle: const Text("Tap to scan again"),
              onTap: () {
                setState(() => _scanResult = null);
                _startBatchScan();
              },
            ),
          ] else ...[
            ListTile(
              title: const Text("Identify unknown tracks"),
              subtitle: const Text(
                "Fingerprint and tag songs with missing metadata",
              ),
              trailing: const Icon(Icons.fingerprint),
              onTap: _startBatchScan,
            ),
          ],
        ]),
      ],
    );
  }

  Future<void> _startBatchScan() async {
    final controller = context.read<AppController>();
    final songs = await controller.audioQuery.querySongs();
    if (songs.isEmpty) return;

    setState(() {
      _scanning = true;
      _scanCurrent = 0;
      _scanTotal = 0;
      _scanSongName = '';
      _scanResult = null;
    });

    final identified = await controller.fingerprintService.batchIdentify(
      songs,
      onProgress: (current, total, name) {
        if (mounted) {
          setState(() {
            _scanCurrent = current;
            _scanTotal = total;
            _scanSongName = name;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _scanning = false;
        _scanResult = identified;
      });
    }
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
            subtitle: const Text("All you need to know about Hype Music"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutAppDialog(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text("Interactions Guide"),
            subtitle: const Text("Gestures, shortcuts & tips"),
            trailing: const Icon(Icons.touch_app_rounded),
            onTap: () => Routes.routeTo(const InteractionsGuide(), context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text("Reset Guides"),
            subtitle: const Text("Show onboarding & tips again"),
            trailing: const Icon(Icons.restart_alt_rounded),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('onboarding_complete');
              await prefs.remove('home_guide_shown');
              await prefs.remove('interactions_guide_shown');
              await CoachMarkController.resetAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Guides will show on next launch'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              }
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text("Report a bug"),
            trailing: const Icon(Icons.bug_report_rounded),
            onTap: () => Wiredash.of(context).show(inheritMaterialTheme: true),
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
            TextButton(onPressed: () => exit(0), child: const Text("Exit")),
          ],
        );
      },
    );
  }
}

class _AppIconTile extends StatefulWidget {
  final String packageName;
  final String appName;

  const _AppIconTile({required this.packageName, required this.appName});

  @override
  State<_AppIconTile> createState() => _AppIconTileState();
}

class _AppIconTileState extends State<_AppIconTile> {
  Uint8List? _iconBytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  Future<void> _loadIcon() async {
    final bytes = await Channel.getAppIcon(widget.packageName);
    if (mounted)
      setState(() {
        _iconBytes = bytes;
        _loaded = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: _loaded
                ? (_iconBytes != null
                      ? Image.memory(_iconBytes!, fit: BoxFit.contain)
                      : Icon(
                          Icons.music_note,
                          size: 24,
                          color: Theme.of(context).colorScheme.primary,
                        ))
                : const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.appName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  widget.packageName,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
