import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/remote_link.dart';
import '../services/share_service.dart';
import '../services/stream_server.dart';

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
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'hypemuzik' || uri.host != 'pair') return;
    final ep = uri.queryParameters['ep'];
    final pin = uri.queryParameters['pin'];
    if (ep == null || ep.isEmpty || pin == null || pin.isEmpty) return;

    setState(() {
      _handling = true;
      _status = 'Linking…';
    });
    await _controller.stop();

    final name = await _pair(ep, pin);
    if (!mounted) return;
    if (name != null) {
      Navigator.of(context).pop(name);
      return;
    }
    setState(() {
      _handling = false;
      _status =
          'Couldn’t link. Make sure “Share my music” is on and the code is still showing, then try again.';
    });
    await _controller.start();
  }

  /// Mint a token, authorise it in the shelf, then run the iroh pairing dial.
  Future<String?> _pair(String desktopEp, String pin) async {
    // The iroh endpoint comes up with sharing — make sure it's running.
    if (!RemoteLink.instance.running) {
      await ShareService.instance.enable();
    }
    if (!RemoteLink.instance.running) {
      return null;
    }
    final server = StreamServerController.instance;
    final token = await server.registerDesktop(desktopEp, 'Desktop');
    final name = await RemoteLink.instance.pair(
      desktopEndpointId: desktopEp,
      pin: pin,
      phoneName: server.deviceName,
      token: token,
    );
    if (name == null) {
      // Roll back the optimistic registration.
      server.unpair(desktopEp);
    }
    return name;
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
