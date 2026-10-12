/// Hype Connect on this phone: the one object the rest of the app talks to.
///
/// # What lives where
///
/// The protocol, socket, executor, rpc handler, state publisher and presence
/// rules are each small and tested alone. This is the composition root that
/// plugs them into each other and into the app — and the only class the
/// settings page, the stream page and `main.dart` need to know.
///
/// # Off until the user says otherwise
///
/// The feature is **off by default**: a phone that never opened the Hype
/// Connect page opens no socket and mints no account. It turns itself on in one
/// situation only — the user approved a link, which is an unmistakable "yes, I
/// want this phone controlled from there" — and turns itself off when the hub
/// says the phone was unlinked (close 4003), since a revoked phone that keeps
/// trying only collects refusals.
///
/// # Remote commands never touch the screen
///
/// Commands and rpcs are answered by [ConnectExecutor] and
/// [ConnectRpcHandler], which only know the app through the ports in
/// `app_bindings.dart`. Nothing in this class navigates or shows a dialog; the
/// pages that talk to it do so in response to the user.
library;

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eq_app/config/app_config.dart';
import 'package:eq_app/controllers/app_controller.dart';
import 'package:eq_app/services/connect/app_bindings.dart';
import 'package:eq_app/services/connect/connect_account.dart';
import 'package:eq_app/services/connect/connect_api.dart';
import 'package:eq_app/services/connect/connect_client.dart';
import 'package:eq_app/services/connect/connect_executor.dart';
import 'package:eq_app/services/connect/connect_presence.dart';
import 'package:eq_app/services/connect/connect_protocol.dart';
import 'package:eq_app/services/connect/connect_rpc.dart';
import 'package:eq_app/services/connect/connect_state_publisher.dart';

/// The hub's WebSocket address for a REST base such as
/// `http://host:9400/api` — same host, same prefix, `/connect/ws`.
Uri connectWsUri(String apiBase) {
  final base = Uri.parse(apiBase);
  final path = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '$path/connect/ws',
  );
}

/// What this phone calls itself on other devices' lists.
///
/// Android: the name the user gave the phone in Settings, else "Samsung
/// SM-S921B". iOS: since iOS 16 `name` is only the generic model family
/// ("iPhone") unless the app holds a special entitlement, and a list of three
/// devices all called "iPhone" helps nobody, so the model's marketing name
/// is preferred when `name` is generic.
@visibleForTesting
String deviceDisplayName({
  required bool ios,
  String? name,
  String? manufacturer,
  String? model,
  String? modelName,
}) {
  final given = name?.trim() ?? '';
  if (ios) {
    const generic = {'iphone', 'ipad', 'ipod touch', 'ipod'};
    if (given.isNotEmpty && !generic.contains(given.toLowerCase())) {
      return given;
    }
    final marketing = modelName?.trim() ?? '';
    if (marketing.isNotEmpty) return marketing;
    return given.isNotEmpty ? given : 'iPhone';
  }
  if (given.isNotEmpty) return given;
  final make = manufacturer?.trim() ?? '';
  final type = model?.trim() ?? '';
  if (make.isEmpty && type.isEmpty) return 'Android phone';
  if (make.isEmpty) return type;
  final brand = make[0].toUpperCase() + make.substring(1);
  if (type.isEmpty) return brand;
  // "samsung" + "Samsung Galaxy" must not read "Samsung Samsung Galaxy".
  return type.toLowerCase().startsWith(make.toLowerCase())
      ? type
      : '$brand $type';
}

/// What to tell the user when linking a device failed.
///
/// One sentence each, saying what happened and what to do — the codes the hub
/// answers with (404 unknown or used, 409 two accounts, 429 too many guesses)
/// each have a different remedy.
String describeLinkError(Object error) {
  if (error is ConnectHttpException) {
    switch (error.statusCode) {
      case 404:
        return 'That code has expired or was already used. '
            'Ask the other device for a new one.';
      case 409:
        if (error.code == 'BOTH_HAVE_ACCOUNTS') {
          return 'Both devices are signed in to different HypeMuzik accounts, '
              'so they cannot be linked. Sign one of them out first.';
        }
        return 'That device changed accounts after the code was made. '
            'Ask it for a new code.';
      case 429:
        return 'Too many attempts. Wait a minute and try again.';
    }
    if (error.statusCode >= 500) {
      return 'HypeMuzik is having trouble right now. Try again in a moment.';
    }
    return 'Could not link that device (${error.statusCode}).';
  }
  if (error is TimeoutException || error is SocketException) {
    return 'Could not reach HypeMuzik. Check your connection and try again.';
  }
  return 'Could not link that device. Try again.';
}

/// Keeps the last `seq` in preferences, so a restart continues after it.
class PrefsConnectSeqStore implements ConnectSeqStore {
  PrefsConnectSeqStore(this._prefs);

  static const key = 'hype_connect.last_seq';

  final SharedPreferences _prefs;

  @override
  int? read() => _prefs.getInt(key);

  @override
  void write(int seq) => unawaited(_prefs.setInt(key, seq));
}

class HypeConnect extends ChangeNotifier with WidgetsBindingObserver {
  /// For tests and for [attach]; the app uses [attach].
  @visibleForTesting
  HypeConnect({
    required this.prefs,
    required this.account,
    required this.api,
    required this.client,
    required this._player,
    required this._library,
    required this._catalog,
    required this._stateSource,
    required this.isMusicMode,
    required this.isPlaying,
    Duration presenceGrace = const Duration(minutes: 2),
  }) {
    _enabled = prefs.getBool(enabledKey) ?? false;
    _presence = ConnectPresence(onWanted: _onWanted, grace: presenceGrace);
    client.state.addListener(_onClientState);
  }

  static const enabledKey = 'hype_connect.enabled';

  static HypeConnect? _instance;
  static HypeConnect get instance => _instance!;
  static HypeConnect? get instanceOrNull => _instance;

  /// Builds the real thing against [app] and starts it. Call once, at startup.
  static HypeConnect attach(AppController app, SharedPreferences prefs) {
    final http0 = http.Client();
    final account = ConnectAccount(
      client: http0,
      apiBase: Uri.parse(AppConfig.hypeMuzikApiBase),
      store: const SecureConnectSecretStore(),
      installInfo: () async => ConnectInstallInfo(
        os: Platform.isIOS ? 'ios' : 'android',
        appVersion: await _appVersion(),
      ),
    );
    final client = ConnectClient(
      wsUri: connectWsUri(AppConfig.hypeMuzikApiBase),
      connect: IoConnectSocket.new,
      accessToken: account.accessToken,
      refreshToken: account.refresh,
      resetSession: account.resetSession,
      device: () => _deviceHello(account),
    );
    final connect = HypeConnect(
      prefs: prefs,
      account: account,
      api: ConnectApi(client: http0, account: account),
      client: client,
      player: AppConnectPlayer(app),
      library: RepositoryConnectLibrary(() => AppController.libraryRepo),
      catalog: YtConnectCatalog(app),
      stateSource: AppConnectStateSource(app),
      isMusicMode: () => !app.isEqMode,
      isPlaying: () => app.handler.playbackState.value.playing,
    );
    app.addListener(connect.inputsChanged);
    app.handler.playbackState.listen((_) => connect.inputsChanged());
    connect.start();
    return _instance = connect;
  }

  final SharedPreferences prefs;
  final ConnectAccount account;
  final ConnectApi api;
  final ConnectClient client;
  final bool Function() isMusicMode;
  final bool Function() isPlaying;

  final ConnectPlayer _player;
  final ConnectLibrary _library;
  final ConnectCatalog _catalog;
  final ConnectStateSource _stateSource;

  late final ConnectPresence _presence;
  ConnectExecutor? _executor;
  ConnectRpcHandler? _rpc;
  ConnectStatePublisher? _publisher;
  StreamSubscription<ConnectFrame>? _frames;
  bool _started = false;

  bool _enabled = false;
  String? _notice;
  List<DeviceInfo> _devices = const [];
  String? _activeDeviceId;
  String? _thisDeviceId;

  /// Whether the user has Hype Connect switched on.
  bool get enabled => _enabled;

  /// Why the feature switched itself off, e.g. "This phone was unlinked".
  /// Cleared when it is switched on again.
  String? get notice => _notice;

  /// Where the socket stands.
  ConnectClientState get connection => client.state.value;

  /// Whether the app is meant to be on the hub right now. Differs from
  /// [enabled] while the app sits in the background, or in equalizer mode.
  bool get wantsConnection => _presence.wanted;

  /// Every linked device of this account.
  List<DeviceInfo> get devices => _devices;
  String? get activeDeviceId => _activeDeviceId;

  /// This phone's id on the hub, once known.
  String? get thisDeviceId => _thisDeviceId;

  /// Prepares the executor and rpc handler (they need this install's id, which
  /// comes from secure storage) and then applies the stored switch.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final deviceId = await account.installId();
    _thisDeviceId = deviceId;
    _executor = ConnectExecutor(
      player: _player,
      library: _library,
      deviceId: deviceId,
    );
    _rpc = ConnectRpcHandler(
      catalog: _catalog,
      library: _library,
      deviceId: deviceId,
    );
    _publisher = ConnectStatePublisher(
      source: _stateSource,
      send: client.send,
      deviceId: deviceId,
      seqStore: PrefsConnectSeqStore(prefs),
    );
    _frames = client.frames.listen(_onFrame);
    final state = WidgetsBinding.instance.lifecycleState;
    _presence
      ..foreground = state == null || state == AppLifecycleState.resumed
      ..musicMode = isMusicMode()
      ..playing = isPlaying()
      ..enabled = _enabled;
    notifyListeners();
  }

  /// The app's mode or playback changed.
  void inputsChanged() {
    if (!_started) return;
    _presence
      ..musicMode = isMusicMode()
      ..playing = isPlaying();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _presence.foreground = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    if (value) _notice = null;
    await prefs.setBool(enabledKey, value);
    if (_started) _presence.enabled = value;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Linking
  // -------------------------------------------------------------------------

  /// Who is asking to be linked by [code]. Throws [ConnectHttpException].
  Future<LinkPreview> previewLink(String code) => api.previewLink(code);

  /// Approves [code], then switches Hype Connect on and refreshes the list —
  /// approving is the user asking for this phone to be reachable.
  Future<void> approveLink(String code) async {
    await api.approveLink(code);
    await setEnabled(true);
    unawaited(refreshDevices());
  }

  Future<void> denyLink(String code) => api.denyLink(code);

  // -------------------------------------------------------------------------
  // Devices
  // -------------------------------------------------------------------------

  /// Reads the linked devices over REST — the list is also pushed over the
  /// socket while connected, but the page has to show it when it is not.
  Future<void> refreshDevices() async {
    try {
      final response = await api.devices();
      _devices = response.devices;
      _activeDeviceId = response.activeDeviceId;
      notifyListeners();
    } catch (e) {
      debugPrint('Hype Connect: could not list devices: $e');
      rethrow;
    }
  }

  Future<void> revokeDevice(String id) async {
    await api.revokeDevice(id);
    _devices = [
      for (final device in _devices)
        if (device.id != id) device,
    ];
    notifyListeners();
  }

  // -------------------------------------------------------------------------

  void _onWanted(bool wanted) {
    if (wanted) {
      client.start();
    } else {
      unawaited(client.stop());
    }
    notifyListeners();
  }

  void _onClientState() {
    final state = client.state.value;
    if (state.status == ConnectStatus.online) {
      _publisher?.start();
    } else {
      _publisher?.stop();
    }
    if (state.status == ConnectStatus.unlinked) {
      _notice = state.lastError;
      unawaited(setEnabled(false));
    }
    notifyListeners();
  }

  void _onFrame(ConnectFrame frame) {
    switch (frame) {
      case WelcomeFrame():
        _devices = frame.devices;
        _activeDeviceId = frame.activeDeviceId;
        _publisher?.sendNow();
        notifyListeners();
      case DevicesFrame():
        _devices = frame.devices;
        _activeDeviceId = frame.activeDeviceId;
        notifyListeners();
      case CmdFrame():
        final executor = _executor;
        if (executor == null) return;
        unawaited(executor.execute(frame).then(client.send));
      case RpcFrame():
        final rpc = _rpc;
        if (rpc == null) return;
        unawaited(rpc.handle(frame).then(client.send));
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------

  static Future<String> _appVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return 'unknown';
    }
  }

  static Future<DeviceHello> _deviceHello(ConnectAccount account) async {
    final plugin = DeviceInfoPlugin();
    final String name;
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      name = deviceDisplayName(
        ios: true,
        name: info.name,
        modelName: info.modelName,
      );
    } else {
      final info = await plugin.androidInfo;
      name = deviceDisplayName(
        ios: false,
        name: info.name,
        manufacturer: info.manufacturer,
        model: info.model,
      );
    }
    return DeviceHello(
      id: await account.installId(),
      kind: DeviceKind.mobile,
      name: name,
      platform: Platform.isIOS ? 'ios' : 'android',
      appVersion: await _appVersion(),
      caps: const [ConnectCap.player, ConnectCap.yt, ConnectCap.local],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_frames?.cancel());
    _presence.dispose();
    _publisher?.stop();
    client.state.removeListener(_onClientState);
    super.dispose();
  }
}
