import 'package:eq_app/Routes/routes.dart';
import 'package:eq_app/widgets/HorizontalSlider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/AppController.dart';
import '../../widgets/PlayListWidget.dart';

class PlayerSettings extends StatefulWidget {
  final AppController controller;
  const PlayerSettings({super.key, required this.controller});

  @override
  State<PlayerSettings> createState() => _PlayerSettingsState();
}

class _PlayerSettingsState extends State<PlayerSettings> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.width,
      child: Consumer<AppController>(builder: (context, control, child) {
        return ListView(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Text(
                  "More Options",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            // controls

            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text("Add to playlist"),
            )
          ],
        );
      }),
    );
  }
}
