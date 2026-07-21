import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cast_controller.dart';
import '../services/share_service.dart';
import 'scan_desktop.dart';

/// "Stream / Cast" — turn this phone into a media source the desktop app can
/// pair with and stream from over the local network.
class StreamServerPage extends StatefulWidget {
  const StreamServerPage({super.key});

  @override
  State<StreamServerPage> createState() => _StreamServerPageState();
}

class _StreamServerPageState extends State<StreamServerPage> {
  final ShareService _server = ShareService.instance;
  final CastController _cast = CastController.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _cast.startDiscovery();
  }

  @override
  void dispose() {
    // Keep the cast target (so taps still cast), but stop browsing.
    _cast.stopDiscovery();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      await _server.toggle(on);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stream to desktop')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_server, _cast]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Card(
                child: SwitchListTile.adaptive(
                  secondary: const Icon(Icons.cast_rounded),
                  title: const Text('Share my music'),
                  subtitle: Text(
                    _server.running
                        ? 'Visible to the desktop app on this Wi‑Fi'
                        : 'Off',
                  ),
                  value: _server.running,
                  onChanged: _busy ? null : _toggle,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile.adaptive(
                  secondary: const Icon(Icons.download_rounded),
                  title: const Text('Receive files from desktop'),
                  subtitle: Text(
                    _server.allowUploads
                        ? 'Paired computers can add songs to this phone'
                        : 'Off — paired computers can only listen',
                  ),
                  value: _server.allowUploads,
                  onChanged: _server.setAllowUploads,
                ),
              ),
              const SizedBox(height: 12),
              if (_server.running) _buildPairingCard(theme),
              if (_server.running) ...[
                const SizedBox(height: 12),
                _buildRemoteCard(theme),
              ],
              if (_server.running && _server.pairedDesktops.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildPairedCard(theme),
              ],
              const SizedBox(height: 12),
              _buildCastCard(theme),
              const SizedBox(height: 16),
              _buildHelp(theme),
            ],
          );
        },
      ),
    );
  }

  /// Entry point for linking a desktop on a *different* network (over iroh).
  Widget _buildRemoteCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.public_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Link a desktop on another network',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Scan the QR in the desktop app (Settings → Connect across networks) '
              'to stream over the internet — securely, peer-to-peer.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _scanDesktop,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan desktop code'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanDesktop() async {
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanDesktopPage()),
    );
    if (name != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Linked to $name')),
      );
    }
  }

  Widget _buildPairingCard(ThemeData theme) {
    final pin = _server.pin ?? '------';
    final address = _server.ip == null
        ? null
        : '${_server.ip}:${_server.port}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PAIRING CODE',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              pin,
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'On your desktop, open the Phone tab, pick "${_server.deviceName}", '
              'and enter this code.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (address != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: address)),
                icon: const Icon(Icons.wifi_rounded, size: 18),
                label: Text(address),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPairedCard(ThemeData theme) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'Paired computers',
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final d in _server.pairedDesktops)
            ListTile(
              leading: const Icon(Icons.computer_rounded),
              title: Text(d.name),
              trailing: IconButton(
                icon: const Icon(Icons.link_off_rounded),
                tooltip: 'Unpair',
                onPressed: () => _server.unpair(d.id),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(int ms) {
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildCastCard(ThemeData theme) {
    final desktops = _cast.desktops;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.computer_rounded, size: 20),
                const SizedBox(width: 8),
                Text('Cast to a computer', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          if (desktops.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                _cast.isCasting
                    ? 'Casting to ${_cast.target!.name}.'
                    : 'Looking for computers… open the HypeMuzik desktop app '
                          'on the same Wi‑Fi (and pair it once from its Phone tab).',
                style: muted,
              ),
            ),
          for (final d in desktops)
            ListTile(
              leading: Icon(
                _cast.target?.id == d.id
                    ? Icons.cast_connected_rounded
                    : Icons.computer_rounded,
                color: _cast.target?.id == d.id
                    ? theme.colorScheme.primary
                    : null,
              ),
              title: Text(d.name),
              subtitle: Text(
                !_cast.isPaired(d.id)
                    ? 'Pair from the computer first'
                    : _cast.target?.id == d.id
                    ? 'Casting — tap a song to play it here'
                    : 'Tap to cast',
              ),
              enabled: _cast.isPaired(d.id),
              selected: _cast.target?.id == d.id,
              onTap: _cast.isPaired(d.id)
                  ? () => _cast.setTarget(_cast.target?.id == d.id ? null : d)
                  : null,
            ),
          if (_cast.isCasting) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(
                    _cast.castPlaying
                        ? Icons.graphic_eq_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _cast.castPlaying ? 'Playing on desktop' : 'Paused',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  Text(
                    _fmt(_cast.castPositionMs),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.pause_rounded),
                    tooltip: 'Pause',
                    onPressed: () => _cast.transport('pause'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_arrow_rounded),
                    tooltip: 'Resume',
                    onPressed: () => _cast.transport('resume'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop_rounded),
                    tooltip: 'Stop',
                    onPressed: () => _cast.transport('stop'),
                  ),
                  TextButton(
                    onPressed: () => _cast.setTarget(null),
                    child: const Text('Stop casting'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHelp(ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• Both devices must be on the same Wi‑Fi network.', style: style),
          const SizedBox(height: 4),
          Text(
            '• Your music streams to the computer and plays through its '
            'enhancement chain — nothing is uploaded to the internet.',
            style: style,
          ),
          const SizedBox(height: 4),
          Text(
            '• Sharing keeps running in the background (with a notification) '
            'while Hype Muzik is running. Turn it off here or from the '
            'notification.',
            style: style,
          ),
          const SizedBox(height: 4),
          Text(
            '• Songs a computer sends you are saved to Music/HypeMuzik and join '
            'your library. Pairing alone never allows this — leave "Receive '
            'files from desktop" off if you only want to stream.',
            style: style,
          ),
        ],
      ),
    );
  }
}
