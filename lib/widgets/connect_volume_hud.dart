import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connect/connect_volume.dart';
import '../services/connect/hype_connect.dart';
import 'volume_hud.dart';

/// "Volume on (device name)": the HUD for hardware volume keys pressed while this
/// phone remote-controls another player. The phone's own volume does not move,
/// so the system panel has nothing to show; this takes its place, for about two
/// seconds after the last press, with the same look as the DVC overlay.
class ConnectVolumeHud extends StatefulWidget {
  const ConnectVolumeHud({super.key, this.hold = const Duration(seconds: 2)});

  /// How long it stays after the last key press.
  final Duration hold;

  @override
  State<ConnectVolumeHud> createState() => _ConnectVolumeHudState();
}

class _ConnectVolumeHudState extends State<ConnectVolumeHud> {
  ValueNotifier<ConnectVolumeHudEvent?>? _source;
  ConnectVolumeHudEvent? _event;
  bool _show = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _source = HypeConnect.instanceOrNull?.volumeHud;
    _source?.addListener(_onEvent);
  }

  void _onEvent() {
    final event = _source?.value;
    if (event == null) return;
    setState(() {
      _event = event;
      _show = true;
    });
    _hide?.cancel();
    _hide = Timer(widget.hold, () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _source?.removeListener(_onEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    // Nothing to draw before the first press; keep the Positioned out of the
    // Stack's way.
    if (event == null) return const SizedBox.shrink();
    return VolumeHud(
      show: _show,
      percent: (event.volume * 100).round().clamp(0, 100),
      caption: 'Volume on ${event.deviceName}',
    );
  }
}
