import 'dart:io';

import '/Helpers/AudioVisualizer.dart';
import '/Routes/routes.dart';
import '/controllers/AppController.dart';
import '/widgets/Body.dart';
import '/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:wiredash/wiredash.dart';
//
import '/Helpers/AudioHandler.dart';
import '/widgets/BottomPlayer.dart';
//

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
                    ListTile(
                      leading: const Icon(Icons.my_library_music_rounded),
                      title: const Text("Library"),
                      subtitle: const Text(
                          "Tap to rescan assets incase of missing files"),
                      onTap: () => Navigator.pushNamed(context, Routes.loader),
                    ),
                    // ExpansionTile(
                    //   leading: const Icon(Icons.tonality_rounded),
                    //   title: const Text("App Theme"),
                    //   children: [
                    //     RadioListTile.adaptive(
                    //       value: controller.selectedTheme == "light" ? 1 : 0,
                    //       groupValue: 1,
                    //       onChanged: (theme) {
                    //         BlocProvider.of<ThemeController>(context)
                    //             .setTheme(1);
                    //         controller.selectedTheme = "light";
                    //       },
                    //       title: const Text("Light Theme"),
                    //     ),
                    //     RadioListTile.adaptive(
                    //       value: controller.selectedTheme == "dark" ? 1 : 0,
                    //       groupValue: 1,
                    //       onChanged: (theme) {
                    //         BlocProvider.of<ThemeController>(context)
                    //             .setTheme(1);
                    //         controller.selectedTheme = "dark";
                    //       },
                    //       title: const Text("Dark Theme"),
                    //     ),
                    //     RadioListTile.adaptive(
                    //       value: controller.selectedTheme == "fancy" ? 1 : 0,
                    //       groupValue: 1,
                    //       onChanged: (theme) {
                    //         BlocProvider.of<ThemeController>(context)
                    //             .setTheme(1);
                    //         controller.selectedTheme = "fancy";
                    //       },
                    //       title: const Text("Fancy Theme"),
                    //     )
                    //   ],
                    // ),

                    SwitchListTile.adaptive(
                      value: controller.isFancy,
                      secondary: const Icon(Icons.light_mode),
                      subtitle: Text(controller.isFancy
                          ? "Fancy enabled"
                          : "Fancy disabled"),
                      title: const Text("Fancy theme"),
                      onChanged: (x) => controller.isFancy = x,
                    ),
                    // ExpansionTile(
                    //   leading: const Icon(
                    //     Icons.mobile_friendly_rounded,
                    //   ),
                    //   title: const Text("Player Background"),
                    //   children: [
                    //     ListTile(
                    //       leading: const Icon(
                    //         Icons.color_lens,
                    //         size: 35,
                    //       ),
                    //       title: const Text("Background"),
                    //       subtitle: SizedBox(
                    //         width: 50,
                    //         height: 50,
                    //         child: HorizontalSlider(
                    //             title: "Quality",
                    //             onChanged: (x) {
                    //               controller.bgQuality = x;
                    //             },
                    //             value: controller.bgQuality,
                    //             max: 10,
                    //             min: 0,
                    //             dB: "${((controller.bgQuality / 10) * 100).toInt()} %"),
                    //       ),
                    //     )
                    //   ],
                    // ),
                    ExpansionTile(
                      leading: const Icon(Icons.phone_android),
                      title: const Text("Player Background"),
                      children: [
                        HorizontalSlider(
                          title: "Blur",
                          onChanged: (x) {
                            controller.blur = x;
                          },
                          value: controller.blur,
                          max: 500,
                          min: 0,
                          dB: "${((controller.blur / 500) * 100).toStringAsFixed(1)} %",
                        ),
                      ],
                    ),
                    ExpansionTile(
                      leading: const Icon(Icons.graphic_eq),
                      title: const Text("Visualizer"),
                      children: [
                        FutureBuilder<bool>(
                            future: Visualizers.getEnabled(),
                            builder: (context, snapshot) {
                              // bool? vSwitch = snapshot.data;
                              // if (vSwitch != null) {
                              //   controller.visuals = vSwitch;
                              // }
                              return SwitchListTile(
                                // secondary: const Icon(Icons.light_mode_outlined),
                                value: controller.visuals,
                                onChanged: (v) {
                                  controller.visuals = v;
                                  Visualizers.enableVisual(v);
                                },
                                subtitle: Text(controller.visuals
                                    ? "Enabled"
                                    : "Disabled"),
                                title: const Text(
                                  "Enable visualizer",
                                ),
                              );
                            }),
                        SwitchListTile(
                          // secondary: const Icon(Icons.light_mode_outlined),
                          value: controller.playerVisual,
                          onChanged: (v) {
                            controller.playerVisual = v;
                          },
                          subtitle: Text(
                              controller.playerVisual ? "Enabled" : "Disabled"),
                          title: const Text(
                            "Enable bottom visualizer in player",
                          ),
                        ),
                        SwitchListTile(
                          // secondary: const Icon(Icons.light_mode_outlined),
                          value: controller.isVisualInBackground,
                          onChanged: (enable) =>
                              controller.isVisualInBackground = enable,
                          subtitle: Text(controller.isVisualInBackground
                              ? "Enabled"
                              : "Disabled"),
                          title: const Text(
                            "Enable visualizer in background",
                          ),
                        )
                      ],
                    ),
                    ListTile(
                      title: const Text("Report a bug"),
                      leading: const Icon(Icons.bug_report_rounded),
                      onTap: () =>
                          Wiredash.of(context).show(inheritMaterialTheme: true),
                    ),
                    const ListTile(
                      leading: Icon(Icons.info_rounded),
                      title: Text("About Hype Music"),
                      subtitle: Text("All you need to know about Hype Muzik"),
                    ),
                    ListTile(
                      leading: const Icon(Icons.exit_to_app),
                      title: const Text("Exit"),
                      onTap: () => exit(0),
                    )
                  ],
                ),
                bottomNavigationBar: service.data ?? false
                    ? BottomPlayer(
                        controller: controller,
                      )
                    : null,
              ),
            );
          });
    });
  }
}
