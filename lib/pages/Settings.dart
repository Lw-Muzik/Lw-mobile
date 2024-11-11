import 'dart:io';

import '/Helpers/AudioVisualizer.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '/widgets/Body.dart';
import '/widgets/HorizontalSlider.dart';
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
        stream: context.read<AudioHandler>().player.playingStream,
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
              body: Column(
                children: [
                  _buildLibraryTile(),
                  _buildFancyThemeSwitch(controller),
                  _buildPlayerBackgroundSettings(controller),
                  _buildVisualizerSettings(controller),
                  _buildBugReportTile(context),
                  ListTile(
                    leading: const Icon(Icons.info_rounded),
                    title: const Text("About Hype Music"),
                    subtitle:
                        const Text("All you need to know about Hype Music"),
                    onTap: () {
                      showAboutAppDialog(context);
                    },
                  ),
                  _buildExitTile(),
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
// import 'package:flutter/material.dart';

  void showAboutAppDialog(BuildContext context) {
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

  ListTile _buildLibraryTile() {
    return ListTile(
      leading: const Icon(Icons.my_library_music_rounded),
      title: const Text("Library"),
      subtitle: const Text("Tap to rescan assets in case of missing files"),
      onTap: () => Navigator.pushNamed(context, Routes.loader),
    );
  }

  SwitchListTile _buildFancyThemeSwitch(AppController controller) {
    return SwitchListTile.adaptive(
      value: controller.isFancy,
      secondary: const Icon(Icons.light_mode),
      subtitle: Text(controller.isFancy ? "Fancy enabled" : "Fancy disabled"),
      title: const Text("Fancy theme"),
      onChanged: (enabled) => controller.isFancy = enabled,
    );
  }

  ExpansionTile _buildPlayerBackgroundSettings(AppController controller) {
    return ExpansionTile(
      leading: const Icon(Icons.phone_android),
      title: const Text("Player Background"),
      children: [
        HorizontalSlider(
          title: "Blur",
          onChanged: (value) => controller.blur = value,
          value: controller.blur,
          max: 500,
          min: 0,
          dB: "${((controller.blur / 500) * 100).toStringAsFixed(1)} %",
        ),
      ],
    );
  }

  ExpansionTile _buildVisualizerSettings(AppController controller) {
    return ExpansionTile(
      leading: const Icon(Icons.graphic_eq),
      title: const Text("Visualizer"),
      children: [
        FutureBuilder<bool>(
          future: Visualizers.getEnabled(),
          builder: (context, snapshot) {
            return SwitchListTile(
              value: controller.visuals,
              onChanged: (enabled) {
                controller.visuals = enabled;
                Visualizers.enableVisual(enabled);
              },
              subtitle: Text(controller.visuals ? "Enabled" : "Disabled"),
              title: const Text("Enable visualizer"),
            );
          },
        ),
        SwitchListTile(
          value: controller.playerVisual,
          onChanged: (enabled) => controller.playerVisual = enabled,
          subtitle: Text(controller.playerVisual ? "Enabled" : "Disabled"),
          title: const Text("Enable bottom visualizer in player"),
        ),
        SwitchListTile(
          value: controller.isVisualInBackground,
          onChanged: (enabled) => controller.isVisualInBackground = enabled,
          subtitle:
              Text(controller.isVisualInBackground ? "Enabled" : "Disabled"),
          title: const Text("Enable visualizer in background"),
        ),
      ],
    );
  }

  ListTile _buildBugReportTile(BuildContext context) {
    return ListTile(
      title: const Text("Report a bug"),
      leading: const Icon(Icons.bug_report_rounded),
      onTap: () => Wiredash.of(context).show(inheritMaterialTheme: true),
    );
  }

  ListTile _buildExitTile() {
    return ListTile(
      leading: const Icon(Icons.exit_to_app),
      title: const Text("Exit"),
      onTap: () => _showExitConfirmationDialog(),
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
