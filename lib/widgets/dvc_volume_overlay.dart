import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import 'volume_hud.dart';

/// The Direct Volume Control HUD: shown for ~2 s after a hardware key press
/// while DVC owns the volume keys. The visual is [VolumeHud].
class DvcVolumeOverlay extends StatelessWidget {
  const DvcVolumeOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return VolumeHud(
      show: controller.showDvcOverlay,
      percent: controller.dvcVolumePercent,
    );
  }
}
