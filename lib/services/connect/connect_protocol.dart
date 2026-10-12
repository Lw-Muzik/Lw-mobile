/// Hype Connect, protocol v1: every frame and REST body this phone exchanges
/// with the hub, as typed values.
///
/// # Where the contract lives
///
/// Not here. The contract is `hypemuzik-management/backend/docs/hype-connect.md`
/// plus the normative example frames beside it, copied into
/// `test/fixtures/connect/`. Four codebases implement it at once — the hub, the
/// web controller, the desktop and this app — so this file follows that
/// document rather than the other way round, and `connect_protocol_test.dart`
/// proves every fixture parses here and re-serialises to the same JSON.
///
/// # Absent is not the same as null
///
/// The contract distinguishes the two. A `TrackRef`'s `artist` is always
/// present and may be `null`; a `play` command's `positionMs` may be missing
/// altogether. Re-emitting a missing key as `null` would be a different frame,
/// and a strict reader on the other end is entitled to treat it as one. So
/// optional fields are nullable here and written only when set, while nullable
/// fields are always written.
///
/// # Reading is strict, but forward-compatible where it can afford to be
///
/// A frame of a known type with a missing or mistyped field throws
/// [FormatException]: guessing a default would hide a peer that is out of step
/// with the contract. Things a newer peer might reasonably add — a frame type,
/// a command type, a capability — are carried rather than rejected, so an older
/// phone answers "unsupported" instead of dropping the request on the floor.
library;

import 'dart:convert';

/// The protocol version this app speaks, sent in `hello`.
const int kConnectProtocolVersion = 1;

// ---------------------------------------------------------------------------
// Reading helpers
// ---------------------------------------------------------------------------

typedef JsonMap = Map<String, Object?>;

JsonMap _asMap(Object? value, String what) {
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('$what: expected an object, got ${value.runtimeType}');
}

String _str(JsonMap json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('"$key": expected a string, got ${value.runtimeType}');
}

String? _strOrNull(JsonMap json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('"$key": expected a string or null');
}

bool _bool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('"$key": expected a boolean, got ${value.runtimeType}');
}

/// An integer field. JavaScript has one number type, so a whole number that
/// arrives as `61250.0` is accepted; a fractional one is rounded rather than
/// rejected, because every integer in this protocol is a count of milliseconds
/// or items where a fraction carries no meaning.
int _int(JsonMap json, String key) {
  final value = json[key];
  if (value is num) return value.round();
  throw FormatException('"$key": expected a number, got ${value.runtimeType}');
}

int? _intOrNull(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.round();
  throw FormatException('"$key": expected a number or null');
}

double _double(JsonMap json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('"$key": expected a number, got ${value.runtimeType}');
}

List<T> _list<T>(JsonMap json, String key, T Function(Object? raw) read) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('"$key": expected an array, got ${value.runtimeType}');
  }
  return [for (final entry in value) read(entry)];
}

T _enum<T extends Enum>(List<T> values, String wire, String what) {
  for (final value in values) {
    if (_wireOf(value) == wire) return value;
  }
  throw FormatException('$what: unknown value "$wire"');
}

T? _enumOrNull<T extends Enum>(List<T> values, String wire) {
  for (final value in values) {
    if (_wireOf(value) == wire) return value;
  }
  return null;
}

String _wireOf(Enum value) =>
    value is WireEnum ? (value as WireEnum).wire : value.name;

/// An enum whose JSON spelling differs from its Dart name (`not_a_player`).
abstract interface class WireEnum {
  String get wire;
}

// ---------------------------------------------------------------------------
// Enumerations
// ---------------------------------------------------------------------------

enum DeviceKind { web, mobile, desktop }

/// What a device can do. `player` obeys commands and publishes state; `yt` can
/// play and search YouTube Music; `local` has an on-device library and answers
/// the `library` rpc.
enum ConnectCap { player, yt, local }

enum ConnectRepeat { off, all, one }

enum EnqueueMode { next, end }

enum AckError implements WireEnum {
  offline('offline'),
  notAPlayer('not_a_player'),
  nothingPlayable('nothing_playable'),
  unsupported('unsupported'),
  failed('failed'),
  timeout('timeout');

  const AckError(this.wire);
  @override
  final String wire;
}

enum RpcError implements WireEnum {
  offline('offline'),
  unsupported('unsupported'),
  notSignedIn('not_signed_in'),
  failed('failed'),
  timeout('timeout');

  const RpcError(this.wire);
  @override
  final String wire;
}

enum RpcMethod { search, suggest, open, artist, library }

/// The search filters a controller may ask for.
enum ConnectSearchFilter { all, songs, videos, albums, artists, playlists }

enum ItemKind { song, video, album, playlist, artist }

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

/// A track as every Hype Connect device names it.
///
/// Three kinds, because three different things can play it: any `yt` player
/// for a YouTube track, only the owning device for a `local` one, and nobody
/// for `other` (a drive file, a radio stream) — which therefore appears in
/// state and never in commands.
sealed class TrackRef {
  const TrackRef();

  String get src;
  String get title;
  String? get artist;
  String? get album;
  int? get durationMs;
  String? get artUrl;

  JsonMap toJson();

  static TrackRef fromJson(Object? raw) {
    final json = _asMap(raw, 'track');
    final src = _str(json, 'src');
    switch (src) {
      case 'yt':
        return YtTrackRef(
          videoId: _str(json, 'videoId'),
          title: _str(json, 'title'),
          artist: _strOrNull(json, 'artist'),
          album: _strOrNull(json, 'album'),
          durationMs: _intOrNull(json, 'durationMs'),
          artUrl: _strOrNull(json, 'artUrl'),
        );
      case 'local':
        return LocalTrackRef(
          deviceId: _str(json, 'deviceId'),
          id: _str(json, 'id'),
          title: _str(json, 'title'),
          artist: _strOrNull(json, 'artist'),
          album: _strOrNull(json, 'album'),
          durationMs: _intOrNull(json, 'durationMs'),
        );
      case 'other':
        return OtherTrackRef(
          title: _str(json, 'title'),
          artist: _strOrNull(json, 'artist'),
          album: _strOrNull(json, 'album'),
          durationMs: _intOrNull(json, 'durationMs'),
          artUrl: _strOrNull(json, 'artUrl'),
        );
    }
    throw FormatException('track: unknown src "$src"');
  }
}

final class YtTrackRef extends TrackRef {
  const YtTrackRef({
    required this.videoId,
    required this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.artUrl,
  });

  final String videoId;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final String? album;
  @override
  final int? durationMs;
  @override
  final String? artUrl;

  @override
  String get src => 'yt';

  @override
  JsonMap toJson() => {
        'src': src,
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'artUrl': artUrl,
      };
}

/// A track in one device's own library. [id] is that device's library id —
/// on this phone, the media-store song id written as a string.
final class LocalTrackRef extends TrackRef {
  const LocalTrackRef({
    required this.deviceId,
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  final String deviceId;
  final String id;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final String? album;
  @override
  final int? durationMs;

  /// Always null: a browser cannot reach on-device artwork.
  @override
  String? get artUrl => null;

  @override
  String get src => 'local';

  @override
  JsonMap toJson() => {
        'src': src,
        'deviceId': deviceId,
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'artUrl': null,
      };
}

final class OtherTrackRef extends TrackRef {
  const OtherTrackRef({
    required this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.artUrl,
  });

  @override
  final String title;
  @override
  final String? artist;
  @override
  final String? album;
  @override
  final int? durationMs;
  @override
  final String? artUrl;

  @override
  String get src => 'other';

  @override
  JsonMap toJson() => {
        'src': src,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'artUrl': artUrl,
      };
}

// ---------------------------------------------------------------------------
// Player state
// ---------------------------------------------------------------------------

/// One upcoming queue entry. [uid] is what a `jump` command names.
class QueueEntry {
  const QueueEntry({required this.uid, required this.track});

  final String uid;
  final TrackRef track;

  factory QueueEntry.fromJson(Object? raw) {
    final json = _asMap(raw, 'queue entry');
    return QueueEntry(
      uid: _str(json, 'uid'),
      track: TrackRef.fromJson(json['track']),
    );
  }

  JsonMap toJson() => {'uid': uid, 'track': track.toJson()};
}

class PlayerState {
  const PlayerState({
    required this.seq,
    required this.track,
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.volume,
    required this.shuffle,
    required this.repeat,
    required this.queue,
  });

  /// Per-device and monotonic: receivers drop anything older than what they
  /// already hold.
  final int seq;
  final TrackRef? track;
  final bool playing;

  /// Where playback was at the moment this frame was sent.
  final int positionMs;
  final int? durationMs;

  /// 0..1.
  final double volume;
  final bool shuffle;
  final ConnectRepeat repeat;

  /// Upcoming items only — never the playing track — at most 50.
  final List<QueueEntry> queue;

  static const maxQueue = 50;

  factory PlayerState.fromJson(Object? raw) {
    final json = _asMap(raw, 'state');
    final track = json['track'];
    return PlayerState(
      seq: _int(json, 'seq'),
      track: track == null ? null : TrackRef.fromJson(track),
      playing: _bool(json, 'playing'),
      positionMs: _int(json, 'positionMs'),
      durationMs: _intOrNull(json, 'durationMs'),
      volume: _double(json, 'volume'),
      shuffle: _bool(json, 'shuffle'),
      repeat: _enum(ConnectRepeat.values, _str(json, 'repeat'), 'repeat'),
      queue: _list(json, 'queue', QueueEntry.fromJson),
    );
  }

  JsonMap toJson() => {
        'seq': seq,
        'track': track?.toJson(),
        'playing': playing,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'volume': volume,
        'shuffle': shuffle,
        'repeat': repeat.name,
        'queue': [for (final entry in queue) entry.toJson()],
      };

  PlayerState withSeq(int seq) => PlayerState(
        seq: seq,
        track: track,
        playing: playing,
        positionMs: positionMs,
        durationMs: durationMs,
        volume: volume,
        shuffle: shuffle,
        repeat: repeat,
        queue: queue,
      );
}

/// A [PlayerState] as the hub fans it out: stamped with the hub's own clock at
/// arrival, so controllers can extrapolate the position without trusting the
/// player's clock.
class StampedState {
  const StampedState({required this.state, required this.at});

  final PlayerState state;

  /// Hub epoch milliseconds.
  final int at;

  factory StampedState.fromJson(Object? raw) {
    final json = _asMap(raw, 'stamped state');
    return StampedState(state: PlayerState.fromJson(json), at: _int(json, 'at'));
  }

  JsonMap toJson() => {...state.toJson(), 'at': at};
}

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------

List<ConnectCap> _caps(JsonMap json) => [
      // A capability this version does not know is one it cannot use, not a
      // reason to reject the device that has it.
      for (final raw in _list(json, 'caps', (v) => v))
        if (raw is String) ?_enumOrNull(ConnectCap.values, raw),
    ];

/// How a device introduces itself in `hello`.
class DeviceHello {
  const DeviceHello({
    required this.id,
    required this.kind,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.caps,
  });

  final String id;
  final DeviceKind kind;
  final String name;
  final String platform;
  final String appVersion;
  final List<ConnectCap> caps;

  factory DeviceHello.fromJson(Object? raw) {
    final json = _asMap(raw, 'device');
    return DeviceHello(
      id: _str(json, 'id'),
      kind: _enum(DeviceKind.values, _str(json, 'kind'), 'kind'),
      name: _str(json, 'name'),
      platform: _str(json, 'platform'),
      appVersion: _str(json, 'appVersion'),
      caps: _caps(json),
    );
  }

  JsonMap toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'platform': platform,
        'appVersion': appVersion,
        'caps': [for (final cap in caps) cap.name],
      };
}

/// A linked device as the hub lists it — online or not, so offline ones can be
/// shown greyed out and revoked.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.kind,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.caps,
    required this.online,
    required this.lastSeenAt,
  });

  final String id;
  final DeviceKind kind;
  final String name;
  final String? platform;
  final String? appVersion;
  final List<ConnectCap> caps;
  final bool online;

  /// ISO-8601, kept as the hub wrote it.
  final String lastSeenAt;

  bool get isPlayer => caps.contains(ConnectCap.player);

  factory DeviceInfo.fromJson(Object? raw) {
    final json = _asMap(raw, 'device');
    return DeviceInfo(
      id: _str(json, 'id'),
      kind: _enum(DeviceKind.values, _str(json, 'kind'), 'kind'),
      name: _str(json, 'name'),
      platform: _strOrNull(json, 'platform'),
      appVersion: _strOrNull(json, 'appVersion'),
      caps: _caps(json),
      online: _bool(json, 'online'),
      lastSeenAt: _str(json, 'lastSeenAt'),
    );
  }

  JsonMap toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'platform': platform,
        'appVersion': appVersion,
        'caps': [for (final cap in caps) cap.name],
        'online': online,
        'lastSeenAt': lastSeenAt,
      };
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// What a controller asks a player to do.
sealed class Command {
  const Command();

  String get type;

  JsonMap toJson();

  /// Throws [FormatException] for a known command with bad fields. An unknown
  /// `type` is not an error here: it becomes an [UnknownCommand], which the
  /// player answers with `unsupported`.
  static Command fromJson(Object? raw) {
    final json = _asMap(raw, 'cmd');
    final type = _str(json, 'type');
    switch (type) {
      case 'play':
        return PlayCommand(
          items: _list(json, 'items', TrackRef.fromJson),
          index: _int(json, 'index'),
          positionMs: _intOrNull(json, 'positionMs'),
          radio: json.containsKey('radio') ? _bool(json, 'radio') : null,
        );
      case 'enqueue':
        return EnqueueCommand(
          items: _list(json, 'items', TrackRef.fromJson),
          mode: _enum(EnqueueMode.values, _str(json, 'mode'), 'mode'),
        );
      case 'pause':
        return const PauseCommand();
      case 'resume':
        return const ResumeCommand();
      case 'stop':
        return const StopCommand();
      case 'next':
        return const NextCommand();
      case 'prev':
        return const PrevCommand();
      case 'seek':
        return SeekCommand(_int(json, 'positionMs'));
      case 'jump':
        return JumpCommand(_str(json, 'uid'));
      case 'volume':
        return VolumeCommand(_double(json, 'value'));
      case 'shuffle':
        return ShuffleCommand(_bool(json, 'on'));
      case 'repeat':
        return RepeatCommand(
          _enum(ConnectRepeat.values, _str(json, 'mode'), 'mode'),
        );
    }
    return UnknownCommand(type, json);
  }
}

/// Replaces the queue and starts at `items[index]`.
final class PlayCommand extends Command {
  const PlayCommand({
    required this.items,
    required this.index,
    this.positionMs,
    this.radio,
  });

  final List<TrackRef> items;
  final int index;

  /// Optional: where to start `items[index]`.
  final int? positionMs;

  /// Optional: "the user tapped one search result" — play it and let the app's
  /// own radio carry on, as tapping a result in the app does.
  final bool? radio;

  @override
  String get type => 'play';

  @override
  JsonMap toJson() => {
        'type': type,
        'items': [for (final item in items) item.toJson()],
        'index': index,
        if (positionMs != null) 'positionMs': positionMs,
        if (radio != null) 'radio': radio,
      };
}

final class EnqueueCommand extends Command {
  const EnqueueCommand({required this.items, required this.mode});

  final List<TrackRef> items;
  final EnqueueMode mode;

  @override
  String get type => 'enqueue';

  @override
  JsonMap toJson() => {
        'type': type,
        'items': [for (final item in items) item.toJson()],
        'mode': mode.name,
      };
}

final class PauseCommand extends Command {
  const PauseCommand();
  @override
  String get type => 'pause';
  @override
  JsonMap toJson() => {'type': type};
}

final class ResumeCommand extends Command {
  const ResumeCommand();
  @override
  String get type => 'resume';
  @override
  JsonMap toJson() => {'type': type};
}

final class StopCommand extends Command {
  const StopCommand();
  @override
  String get type => 'stop';
  @override
  JsonMap toJson() => {'type': type};
}

final class NextCommand extends Command {
  const NextCommand();
  @override
  String get type => 'next';
  @override
  JsonMap toJson() => {'type': type};
}

final class PrevCommand extends Command {
  const PrevCommand();
  @override
  String get type => 'prev';
  @override
  JsonMap toJson() => {'type': type};
}

final class SeekCommand extends Command {
  const SeekCommand(this.positionMs);
  final int positionMs;
  @override
  String get type => 'seek';
  @override
  JsonMap toJson() => {'type': type, 'positionMs': positionMs};
}

/// Plays the queue entry whose `uid` came from this player's own state.
final class JumpCommand extends Command {
  const JumpCommand(this.uid);
  final String uid;
  @override
  String get type => 'jump';
  @override
  JsonMap toJson() => {'type': type, 'uid': uid};
}

final class VolumeCommand extends Command {
  const VolumeCommand(this.value);

  /// 0..1, the app's player volume.
  final double value;
  @override
  String get type => 'volume';
  @override
  JsonMap toJson() => {'type': type, 'value': value};
}

final class ShuffleCommand extends Command {
  const ShuffleCommand(this.on);
  final bool on;
  @override
  String get type => 'shuffle';
  @override
  JsonMap toJson() => {'type': type, 'on': on};
}

final class RepeatCommand extends Command {
  const RepeatCommand(this.mode);
  final ConnectRepeat mode;
  @override
  String get type => 'repeat';
  @override
  JsonMap toJson() => {'type': type, 'mode': mode.name};
}

/// A command type this version does not know, kept verbatim.
final class UnknownCommand extends Command {
  const UnknownCommand(this.type, this.raw);
  @override
  final String type;
  final JsonMap raw;
  @override
  JsonMap toJson() => raw;
}

// ---------------------------------------------------------------------------
// Catalogue (rpc results)
// ---------------------------------------------------------------------------

/// A browsable thing — the wire twin of the app's `ExploreItem`, with the
/// duration in milliseconds. For songs and videos [id] is the video id, so a
/// controller can turn one into a `yt` [TrackRef] without asking again.
class Item {
  const Item({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.hasVideo,
  });

  final ItemKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? thumbnail;
  final String? artist;
  final String? album;
  final int? durationMs;
  final bool hasVideo;

  factory Item.fromJson(Object? raw) {
    final json = _asMap(raw, 'item');
    return Item(
      kind: _enum(ItemKind.values, _str(json, 'kind'), 'kind'),
      id: _str(json, 'id'),
      title: _str(json, 'title'),
      subtitle: _strOrNull(json, 'subtitle'),
      thumbnail: _strOrNull(json, 'thumbnail'),
      artist: _strOrNull(json, 'artist'),
      album: _strOrNull(json, 'album'),
      durationMs: _intOrNull(json, 'durationMs'),
      hasVideo: _bool(json, 'hasVideo'),
    );
  }

  JsonMap toJson() => {
        'kind': kind.name,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'thumbnail': thumbnail,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'hasVideo': hasVideo,
      };
}

class Shelf {
  const Shelf({required this.title, required this.items});

  final String title;
  final List<Item> items;

  factory Shelf.fromJson(Object? raw) {
    final json = _asMap(raw, 'shelf');
    return Shelf(
      title: _str(json, 'title'),
      items: _list(json, 'items', Item.fromJson),
    );
  }

  JsonMap toJson() => {
        'title': title,
        'items': [for (final item in items) item.toJson()],
      };
}

// --- rpc params ---

class SearchParams {
  const SearchParams({required this.query, required this.filter});
  final String query;
  final ConnectSearchFilter filter;

  factory SearchParams.fromJson(Object? raw) {
    final json = _asMap(raw, 'params');
    return SearchParams(
      query: _str(json, 'query'),
      filter: _enum(ConnectSearchFilter.values, _str(json, 'filter'), 'filter'),
    );
  }

  JsonMap toJson() => {'query': query, 'filter': filter.name};
}

class SuggestParams {
  const SuggestParams({required this.query});
  final String query;

  factory SuggestParams.fromJson(Object? raw) =>
      SuggestParams(query: _str(_asMap(raw, 'params'), 'query'));

  JsonMap toJson() => {'query': query};
}

class OpenParams {
  const OpenParams({required this.item});
  final Item item;

  factory OpenParams.fromJson(Object? raw) =>
      OpenParams(item: Item.fromJson(_asMap(raw, 'params')['item']));

  JsonMap toJson() => {'item': item.toJson()};
}

class ArtistParams {
  const ArtistParams({required this.id});
  final String id;

  factory ArtistParams.fromJson(Object? raw) =>
      ArtistParams(id: _str(_asMap(raw, 'params'), 'id'));

  JsonMap toJson() => {'id': id};
}

class LibraryParams {
  const LibraryParams({required this.offset, required this.limit, this.query});

  /// The most a controller may ask for in one page.
  static const maxLimit = 200;

  final int offset;
  final int limit;
  final String? query;

  factory LibraryParams.fromJson(Object? raw) {
    final json = _asMap(raw, 'params');
    return LibraryParams(
      offset: _int(json, 'offset'),
      limit: _int(json, 'limit'),
      query: _strOrNull(json, 'query'),
    );
  }

  JsonMap toJson() => {
        'offset': offset,
        'limit': limit,
        if (query != null) 'query': query,
      };
}

// --- rpc results ---

/// The result of `search` and of `artist`.
class ShelvesResult {
  const ShelvesResult(this.shelves);
  final List<Shelf> shelves;

  factory ShelvesResult.fromJson(Object? raw) =>
      ShelvesResult(_list(_asMap(raw, 'result'), 'shelves', Shelf.fromJson));

  JsonMap toJson() => {
        'shelves': [for (final shelf in shelves) shelf.toJson()],
      };
}

class SuggestResult {
  const SuggestResult(this.suggestions);
  final List<String> suggestions;

  factory SuggestResult.fromJson(Object? raw) => SuggestResult(
        _list(_asMap(raw, 'result'), 'suggestions', (v) {
          if (v is String) return v;
          throw const FormatException('suggestion: expected a string');
        }),
      );

  JsonMap toJson() => {'suggestions': suggestions};
}

class OpenResult {
  const OpenResult({required this.title, required this.tracks});
  final String title;
  final List<TrackRef> tracks;

  factory OpenResult.fromJson(Object? raw) {
    final json = _asMap(raw, 'result');
    return OpenResult(
      title: _str(json, 'title'),
      tracks: _list(json, 'tracks', TrackRef.fromJson),
    );
  }

  JsonMap toJson() => {
        'title': title,
        'tracks': [for (final track in tracks) track.toJson()],
      };
}

class LibraryResult {
  const LibraryResult({required this.total, required this.tracks});
  final int total;
  final List<TrackRef> tracks;

  factory LibraryResult.fromJson(Object? raw) {
    final json = _asMap(raw, 'result');
    return LibraryResult(
      total: _int(json, 'total'),
      tracks: _list(json, 'tracks', TrackRef.fromJson),
    );
  }

  JsonMap toJson() => {
        'total': total,
        'tracks': [for (final track in tracks) track.toJson()],
      };
}

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

/// One WebSocket message: a JSON object whose `t` names its type.
sealed class ConnectFrame {
  const ConnectFrame();

  String get t;

  JsonMap toJson();

  String encode() => jsonEncode(toJson());

  static ConnectFrame decode(String text) => fromJson(jsonDecode(text));

  /// Throws [FormatException] for a known frame type with bad fields. An
  /// unknown `t` becomes an [UnknownFrame].
  static ConnectFrame fromJson(Object? raw) {
    final json = _asMap(raw, 'frame');
    final t = _str(json, 't');
    switch (t) {
      case 'hello':
        return HelloFrame(
          v: _int(json, 'v'),
          token: _str(json, 'token'),
          device: DeviceHello.fromJson(json['device']),
        );
      case 'welcome':
        final states = _asMap(json['states'], 'states');
        return WelcomeFrame(
          v: _int(json, 'v'),
          deviceId: _str(json, 'deviceId'),
          serverTime: _int(json, 'serverTime'),
          devices: _list(json, 'devices', DeviceInfo.fromJson),
          activeDeviceId: _strOrNull(json, 'activeDeviceId'),
          states: {
            for (final entry in states.entries)
              entry.key: StampedState.fromJson(entry.value),
          },
        );
      case 'devices':
        return DevicesFrame(
          devices: _list(json, 'devices', DeviceInfo.fromJson),
          activeDeviceId: _strOrNull(json, 'activeDeviceId'),
        );
      case 'state':
        // The same `t` travels both ways: a player sends its bare state, the
        // hub fans it out stamped and attributed. The `deviceId` is what tells
        // them apart.
        if (json.containsKey('deviceId')) {
          return StampedStateFrame(
            deviceId: _str(json, 'deviceId'),
            state: StampedState.fromJson(json['state']),
          );
        }
        return StateFrame(PlayerState.fromJson(json['state']));
      case 'error':
        return ErrorFrame(
          code: _str(json, 'code'),
          message: _str(json, 'message'),
        );
      case 'select':
        return SelectFrame(_strOrNull(json, 'deviceId'));
      case 'cmd':
        return CmdFrame(
          id: _str(json, 'id'),
          to: _strOrNull(json, 'to'),
          from: _strOrNull(json, 'from'),
          cmd: Command.fromJson(json['cmd']),
        );
      case 'ack':
        final error = _strOrNull(json, 'error');
        return AckFrame(
          id: _str(json, 'id'),
          ok: _bool(json, 'ok'),
          error: error == null ? null : _enum(AckError.values, error, 'error'),
        );
      case 'ping':
        return PingFrame(_str(json, 'id'));
      case 'pong':
        return PongFrame(id: _str(json, 'id'), serverTime: _int(json, 'serverTime'));
      case 'rpc':
        return RpcFrame(
          id: _str(json, 'id'),
          to: _strOrNull(json, 'to'),
          from: _strOrNull(json, 'from'),
          method: _str(json, 'method'),
          params: _asMap(json['params'], 'params'),
        );
      case 'rpc_result':
        final ok = _bool(json, 'ok');
        if (ok) {
          return RpcResultFrame.ok(
            id: _str(json, 'id'),
            result: _asMap(json['result'], 'result'),
          );
        }
        return RpcResultFrame.error(
          id: _str(json, 'id'),
          error: _enum(RpcError.values, _str(json, 'error'), 'error'),
        );
    }
    return UnknownFrame(t, json);
  }
}

/// client → hub, the first frame on every socket.
final class HelloFrame extends ConnectFrame {
  const HelloFrame({
    this.v = kConnectProtocolVersion,
    required this.token,
    required this.device,
  });

  final int v;
  final String token;
  final DeviceHello device;

  @override
  String get t => 'hello';

  @override
  JsonMap toJson() => {'t': t, 'v': v, 'token': token, 'device': device.toJson()};
}

final class WelcomeFrame extends ConnectFrame {
  const WelcomeFrame({
    required this.v,
    required this.deviceId,
    required this.serverTime,
    required this.devices,
    required this.activeDeviceId,
    required this.states,
  });

  final int v;
  final String deviceId;
  final int serverTime;

  /// Every linked, non-revoked device of the user, online or not.
  final List<DeviceInfo> devices;
  final String? activeDeviceId;
  final Map<String, StampedState> states;

  @override
  String get t => 'welcome';

  @override
  JsonMap toJson() => {
        't': t,
        'v': v,
        'deviceId': deviceId,
        'serverTime': serverTime,
        'devices': [for (final device in devices) device.toJson()],
        'activeDeviceId': activeDeviceId,
        'states': {
          for (final entry in states.entries) entry.key: entry.value.toJson(),
        },
      };
}

final class DevicesFrame extends ConnectFrame {
  const DevicesFrame({required this.devices, required this.activeDeviceId});

  final List<DeviceInfo> devices;
  final String? activeDeviceId;

  @override
  String get t => 'devices';

  @override
  JsonMap toJson() => {
        't': t,
        'devices': [for (final device in devices) device.toJson()],
        'activeDeviceId': activeDeviceId,
      };
}

/// player → hub.
final class StateFrame extends ConnectFrame {
  const StateFrame(this.state);
  final PlayerState state;

  @override
  String get t => 'state';

  @override
  JsonMap toJson() => {'t': t, 'state': state.toJson()};
}

/// hub → controllers: another device's state, stamped on arrival.
final class StampedStateFrame extends ConnectFrame {
  const StampedStateFrame({required this.deviceId, required this.state});

  final String deviceId;
  final StampedState state;

  @override
  String get t => 'state';

  @override
  JsonMap toJson() => {'t': t, 'deviceId': deviceId, 'state': state.toJson()};
}

final class ErrorFrame extends ConnectFrame {
  const ErrorFrame({required this.code, required this.message});
  final String code;
  final String message;

  @override
  String get t => 'error';

  @override
  JsonMap toJson() => {'t': t, 'code': code, 'message': message};
}

final class SelectFrame extends ConnectFrame {
  const SelectFrame(this.deviceId);
  final String? deviceId;

  @override
  String get t => 'select';

  @override
  JsonMap toJson() => {'t': t, 'deviceId': deviceId};
}

/// A command. A controller addresses it `to` a player; the hub delivers it
/// with `from` in its place.
final class CmdFrame extends ConnectFrame {
  const CmdFrame({required this.id, this.to, this.from, required this.cmd});

  final String id;
  final String? to;
  final String? from;
  final Command cmd;

  @override
  String get t => 'cmd';

  @override
  JsonMap toJson() => {
        't': t,
        'id': id,
        if (to != null) 'to': to,
        if (from != null) 'from': from,
        'cmd': cmd.toJson(),
      };
}

final class AckFrame extends ConnectFrame {
  const AckFrame({required this.id, required this.ok, this.error});

  const AckFrame.ok(this.id)
      : ok = true,
        error = null;

  const AckFrame.failed(this.id, AckError this.error) : ok = false;

  final String id;
  final bool ok;
  final AckError? error;

  @override
  String get t => 'ack';

  @override
  JsonMap toJson() => {
        't': t,
        'id': id,
        'ok': ok,
        if (error != null) 'error': error!.wire,
      };
}

final class PingFrame extends ConnectFrame {
  const PingFrame(this.id);
  final String id;

  @override
  String get t => 'ping';

  @override
  JsonMap toJson() => {'t': t, 'id': id};
}

final class PongFrame extends ConnectFrame {
  const PongFrame({required this.id, required this.serverTime});
  final String id;
  final int serverTime;

  @override
  String get t => 'pong';

  @override
  JsonMap toJson() => {'t': t, 'id': id, 'serverTime': serverTime};
}

/// A relayed request. [method] stays a string so a method this version does not
/// know can still be answered `unsupported` under its own id.
final class RpcFrame extends ConnectFrame {
  const RpcFrame({
    required this.id,
    this.to,
    this.from,
    required this.method,
    required this.params,
  });

  final String id;
  final String? to;
  final String? from;
  final String method;
  final JsonMap params;

  RpcMethod? get knownMethod => _enumOrNull(RpcMethod.values, method);

  @override
  String get t => 'rpc';

  @override
  JsonMap toJson() => {
        't': t,
        'id': id,
        if (to != null) 'to': to,
        if (from != null) 'from': from,
        'method': method,
        'params': params,
      };
}

final class RpcResultFrame extends ConnectFrame {
  const RpcResultFrame.ok({required this.id, required JsonMap this.result})
      : ok = true,
        error = null;

  const RpcResultFrame.error({required this.id, required RpcError this.error})
      : ok = false,
        result = null;

  final String id;
  final bool ok;
  final JsonMap? result;
  final RpcError? error;

  @override
  String get t => 'rpc_result';

  @override
  JsonMap toJson() => {
        't': t,
        'id': id,
        'ok': ok,
        if (ok) 'result': result else 'error': error!.wire,
      };
}

/// A frame type this version does not know, kept verbatim.
final class UnknownFrame extends ConnectFrame {
  const UnknownFrame(this.t, this.raw);
  @override
  final String t;
  final JsonMap raw;

  @override
  JsonMap toJson() => raw;
}

// ---------------------------------------------------------------------------
// REST bodies
// ---------------------------------------------------------------------------

class LinkTicket {
  const LinkTicket({
    required this.linkId,
    required this.code,
    required this.qr,
    required this.secret,
    required this.expiresAt,
  });

  final String linkId;
  final String code;
  final String qr;
  final String secret;
  final String expiresAt;

  factory LinkTicket.fromJson(Object? raw) {
    final json = _asMap(raw, 'link ticket');
    return LinkTicket(
      linkId: _str(json, 'linkId'),
      code: _str(json, 'code'),
      qr: _str(json, 'qr'),
      secret: _str(json, 'secret'),
      expiresAt: _str(json, 'expiresAt'),
    );
  }

  JsonMap toJson() => {
        'linkId': linkId,
        'code': code,
        'qr': qr,
        'secret': secret,
        'expiresAt': expiresAt,
      };
}

/// Who is asking to be linked — what the approver is shown before saying yes.
class LinkPreview {
  const LinkPreview({
    required this.kind,
    required this.name,
    required this.platform,
    required this.createdAt,
  });

  final DeviceKind kind;
  final String name;
  final String? platform;
  final String createdAt;

  factory LinkPreview.fromJson(Object? raw) {
    final json = _asMap(raw, 'link preview');
    return LinkPreview(
      kind: _enum(DeviceKind.values, _str(json, 'kind'), 'kind'),
      name: _str(json, 'name'),
      platform: _strOrNull(json, 'platform'),
      createdAt: _str(json, 'createdAt'),
    );
  }

  JsonMap toJson() => {
        'kind': kind.name,
        'name': name,
        'platform': platform,
        'createdAt': createdAt,
      };
}

enum LinkClaimStatus { pending, denied, expired, approved }

/// What polling a link returns. Only an approved claim carries tokens.
class LinkClaim {
  const LinkClaim._(
    this.status, {
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.deviceId,
    this.userId,
  });

  const LinkClaim.waiting(LinkClaimStatus status) : this._(status);

  const LinkClaim.approved({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
    required String deviceId,
    required String userId,
  }) : this._(
          LinkClaimStatus.approved,
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresIn: expiresIn,
          deviceId: deviceId,
          userId: userId,
        );

  final LinkClaimStatus status;
  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? deviceId;
  final String? userId;

  factory LinkClaim.fromJson(Object? raw) {
    final json = _asMap(raw, 'link claim');
    final status =
        _enum(LinkClaimStatus.values, _str(json, 'status'), 'status');
    if (status != LinkClaimStatus.approved) return LinkClaim.waiting(status);
    return LinkClaim.approved(
      accessToken: _str(json, 'accessToken'),
      refreshToken: _str(json, 'refreshToken'),
      expiresIn: _int(json, 'expiresIn'),
      deviceId: _str(json, 'deviceId'),
      userId: _str(json, 'userId'),
    );
  }

  JsonMap toJson() => {
        'status': status.name,
        if (status == LinkClaimStatus.approved) ...{
          'accessToken': accessToken,
          'refreshToken': refreshToken,
          'expiresIn': expiresIn,
          'deviceId': deviceId,
          'userId': userId,
        },
      };
}

/// `GET /connect/devices`.
class DevicesResponse {
  const DevicesResponse({required this.devices, required this.activeDeviceId});

  final List<DeviceInfo> devices;
  final String? activeDeviceId;

  factory DevicesResponse.fromJson(Object? raw) {
    final json = _asMap(raw, 'devices response');
    return DevicesResponse(
      devices: _list(json, 'devices', DeviceInfo.fromJson),
      activeDeviceId: _strOrNull(json, 'activeDeviceId'),
    );
  }

  JsonMap toJson() => {
        'devices': [for (final device in devices) device.toJson()],
        'activeDeviceId': activeDeviceId,
      };
}

/// Reads a link code out of what a QR holds: `hypemuzik://link?c=<code>`.
///
/// Also accepts the six digits on their own, so the same function serves the
/// "Enter a code" field — people paste, and people type spaces.
String? parseLinkCode(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme == 'hypemuzik') {
    if (uri.host != 'link') return null;
    final code = uri.queryParameters['c']?.trim() ?? '';
    return _sixDigits.hasMatch(code) ? code : null;
  }
  final digits = text.replaceAll(RegExp(r'[\s-]'), '');
  return _sixDigits.hasMatch(digits) ? digits : null;
}

final _sixDigits = RegExp(r'^\d{6}$');
