/// The pages one step into the song actions sheet: choosing a playlist or an
/// artist, identifying the track, choosing its cover.
///
/// Each is a page of the same panel rather than a sheet of its own — going
/// in reshapes the panel, going back returns to the actions — so nothing ever
/// stacks two sheets deep.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../../apis/index.dart';
import '../../data/library_repository.dart';
import '../../models/recognition_result.dart';
import '../../services/artwork_service.dart';
import '../../services/track_identify.dart';
import '../../services/ytmusic/parse/yt_json.dart';
import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_repository.dart';
import '../../themes/ember.dart';
import 'motion.dart';
import 'sheet_parts.dart';

// ---------------------------------------------------------------------------
// Add to playlist
// ---------------------------------------------------------------------------

/// The app's playlists, the ones already holding the song ticked, and a new
/// one named in place.
///
/// The app's own playlists rather than the media library's: those can hold
/// only files on the phone, and are not there at all on iOS. These hold a
/// YouTube track or a drive file as well — and show on Home and in the
/// Library.
class PlaylistPickerPage extends StatefulWidget {
  const PlaylistPickerPage({
    super.key,
    required this.item,
    required this.onBack,
    required this.onAdded,
  });

  /// The song, as a playlist stores it.
  final PlaylistItem item;
  final VoidCallback onBack;

  /// Added (or found already there and chosen anyway): [playlist] holds it.
  final void Function(PlaylistSummary playlist, {required bool already})
  onAdded;

  @override
  State<PlaylistPickerPage> createState() => _PlaylistPickerPageState();
}

class _PlaylistPickerPageState extends State<PlaylistPickerPage> {
  List<PlaylistSummary>? _playlists;
  Set<int> _holding = const {};
  bool _naming = false;
  bool _busy = false;
  final _name = TextEditingController();

  LibraryRepository get _repo => context.read<LibraryRepository>();

  static int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final playlists = await _repo.playlists();
    final holding = await _repo.playlistsHolding(widget.item);
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _holding = holding;
      // Nothing to choose from: straight to naming the first one.
      if (playlists.isEmpty) _naming = true;
    });
  }

  Future<void> _add(PlaylistSummary playlist) async {
    if (_busy) return;
    if (_holding.contains(playlist.id)) {
      widget.onAdded(playlist, already: true);
      return;
    }
    setState(() => _busy = true);
    await _repo.addToPlaylist(playlist.id, [widget.item], _now);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _holding = {..._holding, playlist.id};
      // Its count goes up with it, in place.
      _playlists = [
        for (final p in _playlists ?? const <PlaylistSummary>[])
          p.id == playlist.id
              ? PlaylistSummary(
                  id: p.id,
                  name: p.name,
                  trackCount: p.trackCount + 1,
                  coverPath: p.coverPath,
                )
              : p,
      ];
    });
    // Long enough to see the tick land.
    await Future<void>.delayed(const Duration(milliseconds: 480));
    if (mounted) widget.onAdded(playlist, already: false);
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    final id = await _repo.createPlaylist(name, _now);
    await _repo.addToPlaylist(id, [widget.item], _now);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    final created = PlaylistSummary(id: id, name: name, trackCount: 1);
    setState(() {
      _playlists = [created, ...?_playlists];
      _holding = {..._holding, id};
      _naming = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 480));
    if (mounted) widget.onAdded(created, already: false);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlists;
    final maxList = math.min(340.0, MediaQuery.sizeOf(context).height * 0.42);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetPageHeader(title: 'Add to playlist', onBack: widget.onBack),
        Cascade(
          index: 0,
          child: ActionGroup(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 360),
                curve: const SpringCurve(dampingRatio: 0.7),
                child: _naming ? _nameField() : _newRow(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (playlists == null)
          const _RowsLoading(rows: 3)
        else if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 8),
            child: Text(
              'No playlists yet. Name one above and this song starts it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: glassWhite(0.5), fontSize: 13),
            ),
          )
        else
          Cascade(
            index: 1,
            child: _GlassList(
              maxHeight: maxList,
              itemCount: playlists.length,
              itemBuilder: (context, i) {
                final playlist = playlists[i];
                final holds = _holding.contains(playlist.id);
                return ActionRow(
                  icon: Icons.queue_music_rounded,
                  leading: _PlaylistCover(playlist: playlist),
                  title: playlist.name,
                  subtitle: _songCount(playlist.trackCount),
                  onTap: () => _add(playlist),
                  trailing: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: CurvedAnimation(
                        parent: animation,
                        curve: const SpringCurve(dampingRatio: 0.45),
                      ),
                      child: child,
                    ),
                    child: holds
                        ? const Icon(
                            Icons.check_circle_rounded,
                            key: ValueKey('in'),
                            color: Ember.accent,
                            size: 24,
                          )
                        : Icon(
                            Icons.add_circle_outline_rounded,
                            key: const ValueKey('out'),
                            color: glassWhite(0.45),
                            size: 24,
                          ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  static String _songCount(int n) => n == 1 ? '1 song' : '$n songs';

  Widget _newRow() => ActionRow(
    icon: Icons.add_rounded,
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Ember.accentWash,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.add_rounded, color: Ember.accent, size: 24),
    ),
    title: 'New playlist',
    subtitle: 'Starts with this song',
    chevron: false,
    onTap: () => setState(() => _naming = true),
  );

  Widget _nameField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Ember.accentWash,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              color: Ember.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              cursorColor: Ember.accent,
              style: const TextStyle(
                color: Ember.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Playlist name',
                hintStyle: TextStyle(color: glassWhite(0.35)),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _create(),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: _name.text.trim().isEmpty ? 0.4 : 1,
            child: _Pill(
              label: 'Create',
              busy: _busy,
              onTap: _name.text.trim().isEmpty ? null : _create,
            ),
          ),
        ],
      ),
    );
  }
}

/// A playlist's cover: its own, or a tile in a colour that is its own.
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final path = playlist.coverPath;
    final tint = Ember.accentFor(playlist.name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: 44,
        child: path != null && File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(tint, Colors.white, 0.18)!,
                      Color.lerp(tint, Colors.black, 0.35)!,
                    ],
                  ),
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  color: glassWhite(0.85),
                  size: 22,
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Which artist
// ---------------------------------------------------------------------------

/// A collaboration's artists, each a page to go to.
class ArtistPickerPage extends StatelessWidget {
  const ArtistPickerPage({
    super.key,
    required this.artists,
    required this.onBack,
    required this.onPick,
    this.busy,
  });

  final List<YtArtistRef> artists;
  final VoidCallback onBack;
  final void Function(YtArtistRef artist) onPick;

  /// The artist being looked up by name, if one is.
  final String? busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetPageHeader(title: 'Artists on this song', onBack: onBack),
        Cascade(
          index: 0,
          child: ActionGroup(
            children: [
              for (final artist in artists)
                ActionRow(
                  icon: Icons.person_rounded,
                  leading: _Initial(name: artist.name),
                  title: artist.name,
                  subtitle: 'Artist',
                  busy: busy == artist.name,
                  onTap: () => onPick(artist),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tint = Ember.accentFor(name);
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(tint, Colors.white, 0.2)!, tint],
        ),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Identify
// ---------------------------------------------------------------------------

/// Naming the track from its sound: listening, then what it is, then
/// writing that into the file.
class IdentifyPage extends StatefulWidget {
  const IdentifyPage({
    super.key,
    required this.song,
    required this.onBack,
    required this.onApplied,
  });

  final SongModel song;
  final VoidCallback onBack;
  final VoidCallback onApplied;

  @override
  State<IdentifyPage> createState() => _IdentifyPageState();
}

class _IdentifyPageState extends State<IdentifyPage> {
  RecognitionResult? _result;
  String? _error;
  bool _listening = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _identify();
  }

  Future<void> _identify() async {
    setState(() {
      _listening = true;
      _error = null;
      _result = null;
    });
    final outcome = await identifyTrack(widget.song);
    if (!mounted) return;
    setState(() {
      _listening = false;
      _result = outcome.result;
      _error = outcome.error;
    });
  }

  Future<void> _apply() async {
    final result = _result;
    if (result == null || _applying) return;
    setState(() => _applying = true);
    final error = await applyIdentification(widget.song, result);
    if (!mounted) return;
    if (error == null) {
      HapticFeedback.lightImpact();
      widget.onApplied();
    } else {
      setState(() {
        _applying = false;
        _error = error;
        _result = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetPageHeader(title: 'Identify track', onBack: widget.onBack),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: _listening
              ? const _Listening()
              : result != null
              ? _resultCard(result)
              : _failure(),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _resultCard(RecognitionResult r) {
    final details = [
      ?r.album,
      ?r.year,
    ].where((s) => s.trim().isNotEmpty).join(' • ');
    return Padding(
      key: const ValueKey('result'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: glassWhite(0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: glassWhite(0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Ember.accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Found it',
                  style: TextStyle(
                    color: glassWhite(0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Ember.accentWash,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${(r.score * 100).round()}% match',
                    style: const TextStyle(
                      color: Ember.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              r.title ?? 'Unknown title',
              style: const TextStyle(
                color: Ember.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (r.artist != null) ...[
              const SizedBox(height: 3),
              Text(
                r.artist!,
                style: TextStyle(color: glassWhite(0.72), fontSize: 14),
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                details,
                style: TextStyle(color: glassWhite(0.45), fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Pill(
                    label: 'Apply to this song',
                    busy: _applying,
                    filled: true,
                    onTap: _apply,
                  ),
                ),
                const SizedBox(width: 10),
                _Pill(label: 'Not it', onTap: widget.onBack),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _failure() {
    return Padding(
      key: const ValueKey('failure'),
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      child: Column(
        children: [
          Icon(
            Icons.hearing_disabled_rounded,
            size: 40,
            color: glassWhite(0.4),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Could not identify this track',
            textAlign: TextAlign.center,
            style: TextStyle(color: glassWhite(0.8), fontSize: 14.5),
          ),
          const SizedBox(height: 14),
          _Pill(label: 'Try again', onTap: _identify),
        ],
      ),
    );
  }
}

/// Rings rising off a fingerprint while the recording is matched.
class _Listening extends StatefulWidget {
  const _Listening();

  @override
  State<_Listening> createState() => _ListeningState();
}

class _ListeningState extends State<_Listening>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_rings.isAnimating) _rings.repeat();
  }

  @override
  void dispose() {
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _RingsPainter(_rings),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Ember.accentWash,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: Ember.accent,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            'Listening…',
            style: TextStyle(
              color: Ember.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Matching the recording against MusicBrainz',
            style: TextStyle(color: glassWhite(0.5), fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final t = (progress.value + i / 3) % 1;
      final radius = 32 + t * 44;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Ember.accent.withValues(alpha: (1 - t) * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Find artwork
// ---------------------------------------------------------------------------

/// Covers found for the song, to choose one from.
///
/// YouTube Music first — its square album art is the release's own cover, at
/// any size asked for — then the app's artwork search.
class ArtworkPickerPage extends StatefulWidget {
  const ArtworkPickerPage({
    super.key,
    required this.song,
    required this.title,
    required this.artist,
    required this.onBack,
    required this.onChosen,
  });

  final SongModel song;
  final String title;
  final String? artist;
  final VoidCallback onBack;
  final VoidCallback onChosen;

  @override
  State<ArtworkPickerPage> createState() => _ArtworkPickerPageState();
}

class _ArtworkPickerPageState extends State<ArtworkPickerPage> {
  List<String>? _covers;
  String? _applying;
  String? _chosen;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _covers = null;
      _problem = null;
    });
    final query = [?widget.artist, widget.title].join(' ');
    final found = await Future.wait([
      _fromYouTube(query),
      _fromSearch(widget.title, widget.artist ?? ''),
    ]);
    if (!mounted) return;
    final seen = <String>{};
    setState(() {
      _covers = [
        for (final url in [...found[0], ...found[1]])
          if (seen.add(url)) url,
      ].take(12).toList();
    });
  }

  static Future<List<String>> _fromYouTube(String query) async {
    try {
      final shelves = await YtMusicRepository.instance
          .search(query, SearchFilter.songs)
          .timeout(const Duration(seconds: 12));
      return [
        for (final shelf in shelves)
          for (final item in shelf.items)
            if (item.thumbnail case final url?) thumbnailAt(url, 1200),
      ].take(8).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> _fromSearch(String title, String artist) async {
    try {
      final model = await Apis.fetchArtWork(title, artist);
      return [for (final result in model.results) result.url].take(6).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _choose(String url) async {
    if (_applying != null) return;
    setState(() {
      _applying = url;
      _problem = null;
    });
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw const HttpException('no image');
      }
      await ArtworkService.instance.setChosenArtwork(
        widget.song.id,
        response.bodyBytes,
      );
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(() {
        _applying = null;
        _chosen = url;
      });
      await Future<void>.delayed(const Duration(milliseconds: 520));
      if (mounted) widget.onChosen();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = null;
        _problem = "That cover wouldn't download. Try another.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final covers = _covers;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetPageHeader(title: 'Find artwork', onBack: widget.onBack),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              _problem!,
              style: TextStyle(color: glassWhite(0.7), fontSize: 13),
            ),
          ),
        if (covers != null && covers.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 4),
            child: Column(
              children: [
                Icon(
                  Icons.image_not_supported_rounded,
                  size: 38,
                  color: glassWhite(0.4),
                ),
                const SizedBox(height: 10),
                Text(
                  'No covers found for this song',
                  style: TextStyle(color: glassWhite(0.8), fontSize: 14.5),
                ),
                const SizedBox(height: 12),
                _Pill(label: 'Search again', onTap: _load),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                if (covers == null)
                  for (var i = 0; i < 6; i++) _CoverLoading(index: i)
                else
                  for (var i = 0; i < covers.length; i++)
                    Cascade(
                      index: i,
                      step: const Duration(milliseconds: 30),
                      delay: Duration.zero,
                      child: _CoverTile(
                        url: covers[i],
                        busy: _applying == covers[i],
                        chosen: _chosen == covers[i],
                        onTap: () => _choose(covers[i]),
                      ),
                    ),
              ],
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.url,
    required this.busy,
    required this.chosen,
    required this.onTap,
  });

  final String url;
  final bool busy;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pixels = (120 * MediaQuery.devicePixelRatioOf(context)).round();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: chosen ? 1.06 : 1,
        duration: const Duration(milliseconds: 420),
        curve: const SpringCurve(dampingRatio: 0.5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: url.contains('googleusercontent')
                    ? thumbnailAt(url, pixels)
                    : url,
                fit: BoxFit.cover,
                memCacheWidth: pixels,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, _) => ColoredBox(color: glassWhite(0.06)),
                errorWidget: (_, _, _) => ColoredBox(
                  color: glassWhite(0.06),
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: glassWhite(0.3),
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: busy || chosen ? 1 : 0,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: chosen
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Ember.accent,
                            size: 34,
                          )
                        : const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A cover still being searched for: a tile that breathes.
class _CoverLoading extends StatefulWidget {
  const _CoverLoading({required this.index});

  final int index;

  @override
  State<_CoverLoading> createState() => _CoverLoadingState();
}

class _CoverLoadingState extends State<_CoverLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context) || _pulse.isAnimating) return;
    Future<void>.delayed(Duration(milliseconds: widget.index * 90), () {
      if (mounted) _pulse.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: glassWhite(0.05 + _pulse.value * 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

/// A scrolling list in the sheet's glass group style.
class _GlassList extends StatelessWidget {
  const _GlassList({
    required this.maxHeight,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double maxHeight;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: glassWhite(0.045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: glassWhite(0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
            separatorBuilder: (_, _) => Padding(
              padding: const EdgeInsets.only(left: 72),
              child: Divider(height: 1, thickness: 1, color: glassWhite(0.06)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows still loading.
class _RowsLoading extends StatelessWidget {
  const _RowsLoading({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ActionGroup(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: glassWhite(0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 120.0 + i * 30,
                  height: 12,
                  decoration: BoxDecoration(
                    color: glassWhite(0.07),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A rounded text button; [filled] for the one that commits.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onTap,
    this.busy = false,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Ember.accentWash : glassWhite(0.08),
      shape: StadiumBorder(
        side: BorderSide(
          color: filled
              ? Ember.accent.withValues(alpha: 0.4)
              : glassWhite(0.08),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy || onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Center(
            widthFactor: 1,
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: filled ? Ember.accent : Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: filled ? Ember.accent : Ember.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
