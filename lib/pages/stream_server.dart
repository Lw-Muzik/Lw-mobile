import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/stream_server.dart';

/// "Stream / Cast" — turn this phone into a media source the desktop app can
/// pair with and stream from over the local network.
class StreamServerPage extends StatefulWidget {
  const StreamServerPage({super.key});

  @override
  State<StreamServerPage> createState() => _StreamServerPageState();
}

class _StreamServerPageState extends State<StreamServerPage> {
  final StreamServerController _server = StreamServerController.instance;
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        await _server.start();
      } else {
        await _server.stop();
      }
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
        listenable: _server,
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
              if (_server.running) _buildPairingCard(theme),
              if (_server.running && _server.pairedDesktops.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildPairedCard(theme),
              ],
              const SizedBox(height: 16),
              _buildHelp(theme),
            ],
          );
        },
      ),
    );
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
            '• Sharing stays on while Hype Muzik is open.',
            style: style,
          ),
        ],
      ),
    );
  }
}
