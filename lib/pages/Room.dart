import 'package:flutter/material.dart';

/// Legacy Room Effects page - replaced by SpaceView in the Equalizer tabs.
/// Kept for backward compatibility but no longer used.
class RoomEffects extends StatelessWidget {
  const RoomEffects({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Room effects have moved to the Equalizer Space tab."),
    );
  }
}
