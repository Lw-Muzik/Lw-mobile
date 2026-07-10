import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/remote_link.dart';
import '../services/share_service.dart';

/// Scans the QR shown in the desktop app (Settings → Connect across networks)
/// and pairs with it over iroh, so the desktop can stream this phone's music
/// across *different* networks. Pops the desktop's name on success.
class ScanDesktopPage extends StatefulWidget {
  const ScanDesktopPage({super.key});

  @override
  State<ScanDesktopPage> createState() => _ScanDesktopPageState();
}

class _ScanDesktopPageState extends State<ScanDesktopPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handling = false;
  // After a failed attempt we leave the camera stopped and wait for an explicit
  // "Try again" tap. Auto-restarting here re-detects the same on-screen QR and
  // loops stop→fail→start forever — the camera "blinking" the user saw.
  bool _failed = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || _failed || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'hypemuzik' || uri.host != 'pair') return;
    final ep = uri.queryParameters['ep'];
    final pin = uri.queryParameters['pin'];
    if (ep == null || ep.isEmpty || pin == null || pin.isEmpty) return;

    // Keep the camera preview running during the attempt — stopping it blacks
    // out the screen, and the `_handling`/`_failed` guards already prevent
    // re-entry, so there's no need to tear the camera down.
    setState(() {
      _handling = true;
      _status = 'Linking…';
    });

    final result = await _pair(ep, pin);
    if (!mounted) return;
    if (result.name != null) {
      Navigator.of(context).pop(result.name);
      return;
    }
    // Leave the preview up and wait for an explicit retry (auto-retrying would
    // re-detect the same QR and loop — the earlier "blinking").
    setState(() {
      _handling = false;
      _failed = true;
      _status = result.message;
    });
  }

  Future<void> _retry() async {
    // Restart the scanner so its no-duplicate history clears and the same
    // on-screen QR can be read again.
    await _controller.stop();
    await _controller.start();
    if (!mounted) return;
    setState(() {
      _failed = false;
      _status = null;
    });
  }

  /// Mint a token, authorise it in the shelf, then run the iroh pairing dial.
  /// Returns the desktop's name on success, plus a stage-specific failure
  /// message otherwise — "the phone's link engine won't start" and "the dial
  /// to the desktop failed" need very different remedies.
  Future<({String? name, String message})> _pair(
    String desktopEp,
    String pin,
  ) async {
    // Make sure the shelf server AND this phone's iroh endpoint are up.
    // `enable()` alone won't (re)start the endpoint if sharing was already on,
    // so use `ensureRemoteLink()`.
    await ShareService.instance.ensureRemoteLink();
    if (!RemoteLink.instance.running) {
      return (
        name: null,
        message:
            'This phone couldn’t start its secure link engine, so it can’t pair across networks yet. '
            'LAN linking (same Wi-Fi) still works. Details: adb logcat -s hm-remote',
      );
    }
    final share = ShareService.instance;
    // Route pairing through the facade so, on Android, the running server
    // (foreground-service isolate) is told to reload and authorize this token.
    final token = await share.registerDesktop(desktopEp, 'Desktop');
    final name = await RemoteLink.instance.pair(
      desktopEndpointId: desktopEp,
      pin: pin,
      phoneName: share.deviceName,
      token: token,
    );
    if (name == null) {
      // Roll back the optimistic registration.
      share.unpair(desktopEp);
      return (
        name: null,
        message:
            'Couldn’t reach the desktop. Make sure both devices are online, keep the QR open '
            '(it expires after 5 minutes — reopen the card for a fresh one), then tap Try again.',
      );
    }
    return (name: name, message: '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan desktop code')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Framing reticle.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_handling)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: CircularProgressIndicator(),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _status ??
                        'Point at the QR in the desktop app:\nSettings → Connect across networks.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
