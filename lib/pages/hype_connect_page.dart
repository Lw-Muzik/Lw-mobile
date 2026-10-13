import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:eq_app/Themes/app_fonts.dart';
import 'package:eq_app/services/connect/connect_client.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/hype_connect.dart';
import 'package:eq_app/themes/ember.dart';
import 'package:eq_app/player/remote/link_direction_sheet.dart';

/// The one sentence under the switch: where Hype Connect stands, in plain words.
///
/// Derived from facts rather than from the socket's state alone, because the
/// socket being closed means different things — switched off, resting in the
/// background, or the app being in equalizer-only mode — and the user's next
/// move differs for each.
@visibleForTesting
String connectStatusLine({
  required bool enabled,
  required bool musicMode,
  required bool wantsConnection,
  required ConnectClientState connection,
  String? notice,
}) {
  if (!enabled) {
    return notice ??
        'Off. Turn it on to play music here from your other devices.';
  }
  if (!musicMode) {
    return 'Waiting. Hype Connect needs the full player, not equalizer-only mode.';
  }
  switch (connection.status) {
    case ConnectStatus.online:
      return 'Ready. This phone is in the device list on your other screens.';
    case ConnectStatus.connecting:
      return 'Connecting…';
    case ConnectStatus.retrying:
      final wait = connection.retryIn;
      final when = wait == null ? '' : ' in ${wait.inSeconds.clamp(1, 60)} s';
      return 'Cannot reach HypeMuzik. Trying again$when.'
          '${connection.lastError == null ? '' : '\n${connection.lastError}'}';
    case ConnectStatus.replaced:
      return 'Another connection for this phone took over. '
          'Turn Hype Connect off and on to take it back.';
    case ConnectStatus.unlinked:
      return connection.lastError ?? 'This phone was unlinked.';
    case ConnectStatus.off:
      return wantsConnection
          ? 'Connecting…'
          : 'Resting. It reconnects when you open Hype or start playing music.';
  }
}

/// Hype Connect: link browsers and desktops to this account, and see them.
class HypeConnectPage extends StatefulWidget {
  const HypeConnectPage({super.key});

  /// How many copies are on the navigator right now. Settings, the sharing
  /// page and the notification all open this page; the notification checks
  /// this so a tap does not stack a second copy on the first.
  static int openCount = 0;

  @override
  State<HypeConnectPage> createState() => _HypeConnectPageState();
}

class _HypeConnectPageState extends State<HypeConnectPage>
    with WidgetsBindingObserver {
  final HypeConnect _connect = HypeConnect.instance;
  bool _busy = false;
  bool _loadingDevices = true;
  String? _devicesError;

  /// Whether the system may still stop the app in the background. Unknown
  /// (and so hidden) until asked.
  bool _batteryRestricted = false;

  @override
  void initState() {
    super.initState();
    HypeConnectPage.openCount++;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadDevices());
    unawaited(_checkBattery());
  }

  @override
  void dispose() {
    HypeConnectPage.openCount--;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the system's battery page is how the row learns it was
  /// answered, so it is checked again on every resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkBattery());
  }

  Future<void> _checkBattery() async {
    if (!_connect.hasBackgroundService) return;
    final exempt = await _connect.isIgnoringBatteryOptimizations();
    if (mounted && _batteryRestricted == exempt) {
      setState(() => _batteryRestricted = !exempt);
    }
  }

  Future<void> _loadDevices() async {
    try {
      await _connect.refreshDevices();
      if (mounted) setState(() => _devicesError = null);
    } catch (_) {
      if (mounted) {
        setState(() => _devicesError = 'Could not load your devices.');
      }
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // -- Linking ---------------------------------------------------------------

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScanLinkCodePage()),
    );
    if (code != null && mounted) await _link(code);
  }

  Future<void> _typeCode() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Ember.surface,
      builder: (_) => const _EnterCodeSheet(),
    );
    if (code != null && mounted) await _link(code);
  }

  /// Looks the code up, asks, and acts on the answer.
  Future<void> _link(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    LinkPreview preview;
    try {
      preview = await _connect.previewLink(code);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _say(describeLinkError(e));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final approve = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Ember.surface,
      builder: (_) => _ConfirmLinkSheet(preview: preview),
    );
    if (!mounted || approve == null) return;

    setState(() => _busy = true);
    try {
      if (approve) {
        await _connect.approveLink(code);
        if (mounted) _say('Linked ${preview.name}.');
        // A desktop can be a speaker or a remote: ask which (re-linking an
        // already linked desktop asks again).
        if (mounted && preview.kind == DeviceKind.desktop) {
          await showLinkDirectionSheet(context, preview);
        }
      } else {
        await _connect.denyLink(code);
        if (mounted) _say('Refused ${preview.name}.');
      }
    } catch (e) {
      if (mounted) _say(describeLinkError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- Devices ---------------------------------------------------------------

  Future<void> _revoke(DeviceInfo device) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revoke ${device.name}?'),
        content: const Text(
          'It will be signed out of your account and will need a new code to '
          'link again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await _connect.revokeDevice(device.id);
    } catch (_) {
      if (mounted) _say('Could not revoke ${device.name}. Try again.');
    }
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ember.ground,
      appBar: AppBar(
        title: Text(
          'Hype Connect',
          style: AppFonts.displayStyle(fontSize: 22, weight: AppFonts.medium),
        ),
        backgroundColor: Ember.ground,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_connect, _connect.client.state]),
        builder: (context, _) {
          final devices = _connect.devices;
          return RefreshIndicator(
            color: Ember.accent,
            onRefresh: _loadDevices,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Ember.gutter,
                8,
                Ember.gutter,
                32,
              ),
              children: [
                _StatusCard(connect: _connect),
                if (_connect.enabled &&
                    _connect.hasBackgroundService &&
                    _batteryRestricted) ...[
                  const SizedBox(height: 12),
                  _BackgroundRow(onTap: _connect.openBatterySettings),
                ],
                const SizedBox(height: 16),
                _LinkActions(
                  busy: _busy,
                  onScan: _scan,
                  onType: _typeCode,
                ),
                const SizedBox(height: Ember.shelfGap),
                Text('LINKED DEVICES', style: Ember.shelfTitle(context)),
                const SizedBox(height: 12),
                if (_loadingDevices && devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else if (devices.isEmpty)
                  _EmptyDevices(error: _devicesError)
                else ...[
                  for (final device in devices)
                    _DeviceTile(
                      device: device,
                      isThisPhone: device.id == _connect.thisDeviceId,
                      isActive: device.id == _connect.activeDeviceId,
                      onRevoke: () => _revoke(device),
                    ),
                  if (_devicesError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _devicesError!,
                        style: TextStyle(color: Ember.textTertiary),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.connect});

  final HypeConnect connect;

  @override
  Widget build(BuildContext context) {
    final connection = connect.connection;
    final online = connect.enabled && connection.status == ConnectStatus.online;
    final line = connectStatusLine(
      enabled: connect.enabled,
      musicMode: connect.isMusicMode(),
      wantsConnection: connect.wantsConnection,
      connection: connection,
      notice: connect.notice,
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Ember.surface,
        borderRadius: BorderRadius.circular(Ember.radiusCard),
        border: Border.all(
          color: online ? Ember.accent.withValues(alpha: 0.5) : Ember.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? Ember.accentWash : Ember.surfaceHigh,
                ),
                child: Icon(
                  Icons.cast_connected_rounded,
                  color: online ? Ember.accent : Ember.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Play on this phone from anywhere',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Ember.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Switch.adaptive(
                value: connect.enabled,
                activeTrackColor: Ember.accent,
                activeThumbColor: Ember.ground,
                onChanged: (on) => connect.setEnabled(on),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            line,
            style: TextStyle(color: Ember.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Some phone makers stop background apps however well they behave; the
/// system's battery page is where the user can say "not this one".
class _BackgroundRow extends StatelessWidget {
  const _BackgroundRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ember.surface,
      borderRadius: BorderRadius.circular(Ember.radiusTile),
      child: InkWell(
        borderRadius: BorderRadius.circular(Ember.radiusTile),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ember.radiusTile),
            border: Border.all(color: Ember.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.battery_saver_rounded, color: Ember.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Let Hype run in the background',
                      style: TextStyle(
                        color: Ember.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Some phones stop apps in the background otherwise, '
                      'and this phone would drop off your other screens.',
                      style: TextStyle(
                        color: Ember.textTertiary,
                        height: 1.3,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Ember.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkActions extends StatelessWidget {
  const _LinkActions({
    required this.busy,
    required this.onScan,
    required this.onType,
  });

  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Link a browser or a computer by scanning the code it shows, '
          'or typing the six digits.',
          style: TextStyle(color: Ember.textTertiary, height: 1.35),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onScan,
                style: FilledButton.styleFrom(
                  backgroundColor: Ember.accent,
                  foregroundColor: Ember.ground,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan a code'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onType,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Ember.textPrimary,
                  side: BorderSide(color: Ember.outline),
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.pin_outlined),
                label: const Text('Enter a code'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Ember.surface,
        borderRadius: BorderRadius.circular(Ember.radiusTile),
        border: Border.all(color: Ember.outline),
      ),
      child: Text(
        error ??
            'Nothing is linked yet. Open HypeMuzik on the web or the desktop '
            'app, choose Link a device, and scan the code it shows.',
        style: TextStyle(color: Ember.textSecondary, height: 1.4),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isThisPhone,
    required this.isActive,
    required this.onRevoke,
  });

  final DeviceInfo device;
  final bool isThisPhone;
  final bool isActive;
  final VoidCallback onRevoke;

  static IconData _iconFor(DeviceKind kind) => switch (kind) {
        DeviceKind.web => Icons.language_rounded,
        DeviceKind.desktop => Icons.desktop_mac_rounded,
        DeviceKind.mobile => Icons.smartphone_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (isThisPhone) 'This phone',
      // The active device is the player; "here" only when that is this phone.
      if (isActive)
        isThisPhone ? 'Playing here' : 'Plays the music'
      else if (device.online)
        'Online'
      else
        'Offline',
      if (device.platform != null && device.platform!.isNotEmpty) device.platform!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Ember.surface,
        borderRadius: BorderRadius.circular(Ember.radiusTile),
        border: Border.all(color: Ember.outline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 16, right: 4),
        leading: Icon(
          _iconFor(device.kind),
          color: device.online ? Ember.accent : Ember.textTertiary,
        ),
        title: Text(
          device.name,
          style: TextStyle(
            color: device.online ? Ember.textPrimary : Ember.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(detail, style: TextStyle(color: Ember.textTertiary)),
        trailing: isThisPhone
            ? null
            : IconButton(
                tooltip: 'Revoke ${device.name}',
                icon: Icon(Icons.link_off_rounded, color: Ember.textSecondary),
                onPressed: onRevoke,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConfirmLinkSheet extends StatelessWidget {
  const _ConfirmLinkSheet({required this.preview});

  final LinkPreview preview;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Ember.gutter, 0, Ember.gutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Link ${preview.name} to your account?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Ember.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'It will be able to play music on this phone and see what is '
              'playing. Only approve a code you asked for yourself.',
              style: TextStyle(color: Ember.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Ember.accent,
                foregroundColor: Ember.ground,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Approve'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: Ember.textSecondary,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Deny'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnterCodeSheet extends StatefulWidget {
  const _EnterCodeSheet();

  @override
  State<_EnterCodeSheet> createState() => _EnterCodeSheetState();
}

class _EnterCodeSheetState extends State<_EnterCodeSheet> {
  final TextEditingController _text = TextEditingController();
  String? _code;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) =>
      setState(() => _code = parseLinkCode(value));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Ember.gutter, 0, Ember.gutter, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the code',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Ember.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Six digits, shown under the QR code.',
                style: TextStyle(color: Ember.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 -]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  filled: true,
                  fillColor: Ember.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Ember.radiusControl),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _changed,
                onSubmitted: (_) {
                  if (_code != null) Navigator.pop(context, _code);
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    _code == null ? null : () => Navigator.pop(context, _code),
                style: FilledButton.styleFrom(
                  backgroundColor: Ember.accent,
                  foregroundColor: Ember.ground,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reads a link code from a QR. Pops the six digits, or nothing if backed out.
class _ScanLinkCodePage extends StatefulWidget {
  const _ScanLinkCodePage();

  @override
  State<_ScanLinkCodePage> createState() => _ScanLinkCodePageState();
}

class _ScanLinkCodePageState extends State<_ScanLinkCodePage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      final code = raw == null ? null : parseLinkCode(raw);
      // A QR that is not a link code (a poster, a Wi-Fi sticker) is ignored
      // rather than reported: the camera sees all of them on the way.
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Scan a code',
          style: AppFonts.displayStyle(fontSize: 22, weight: AppFonts.medium),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Ember.accent.withValues(alpha: 0.9),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Point at the QR code on the web app or the desktop app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
