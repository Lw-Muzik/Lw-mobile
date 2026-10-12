/// One playlist or album, opened into its tracks.
///
/// Listing rather than playing is the point — see `yt_open.dart`. "Play"
/// starts at the top and therefore queues the whole list; tapping a track starts
/// from that track, because a queue that grows behind the music can only extend
/// forwards without interrupting it.
///
/// # The header
///
/// The cover is the page: drawn large, and again behind everything, blurred
/// into the ground — a still image, so `ImageFiltered` rather than a live
/// backdrop. Under it the title, who made it (each artist a link to their
/// page, the first with their portrait), what it is and how long, and the
/// three things to do with it: shuffle, play, download.
///
/// An album lists its tracks by number, the way its sleeve does; a playlist
/// shows each track's own art. Whichever track is playing is marked, so
/// arriving here from the player ("Go to album") shows where the song sits.
library;

import 'package:eq_app/Themes/app_fonts.dart';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../models/track_extras.dart';
import '../../Routes/routes.dart';
import '../../services/ytmusic/parse/yt_json.dart';
import '../../services/ytmusic/parse/yt_tracks.dart';
import '../../services/ytmusic/yt_models.dart';
import '../../services/ytmusic/yt_playback.dart';
import '../../services/ytmusic/yt_repository.dart';
import '../../themes/ember.dart';
import 'artist_page.dart';
import 'widgets/yt_hero.dart';
import 'widgets/yt_widgets.dart';
import 'yt_open.dart';

class YtOpenedListPage extends StatefulWidget {
  final ExploreItem item;

  /// A track to bring into view once the list arrives — the song the player
  /// was on when "Go to album" was chosen.
  final String? highlightVideoId;

  const YtOpenedListPage({
    super.key,
    required this.item,
    this.highlightVideoId,
  });

  @override
  State<YtOpenedListPage> createState() => _YtOpenedListPageState();
}

class _YtOpenedListPageState extends State<YtOpenedListPage> {
  YtTrackList? _list;
  bool _loading = true;
  String? _error;
  final _scroll = ScrollController();
  bool _collapsed = false;

  bool get _isAlbum => widget.item.kind == ExploreKind.album;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed =
        _scroll.offset > _heroHeight(context) - kToolbarHeight - 24;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await YtMusicRepository.instance.openList(widget.item);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
      // Resolve the top of the list while the user is still reading it, so the
      // tap that follows costs nothing.
      YtMusicRepository.instance.prefetchAudio([
        for (final track in list.tracks) track.videoId,
      ]);
      _revealHighlight(list.tracks);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is YtException ? e.message : 'Could not open that.';
      });
    }
  }

  /// Scrolls the highlighted track into view when it sits below the fold.
  void _revealHighlight(List<YtTrack> tracks) {
    final id = widget.highlightVideoId;
    if (id == null) return;
    final index = _indexOf(tracks, id);
    if (index < 6) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _heroHeight(context) + 64 + index * _rowHeight - 160;
      _scroll.animateTo(
        math.min(target, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// An album lists its own upload of a song, which can be another video
  /// than the one the player has — so the title stands in when the id
  /// doesn't match.
  int _indexOf(List<YtTrack> tracks, String videoId, {String? title}) {
    final byId = tracks.indexWhere((t) => t.videoId == videoId);
    if (byId >= 0 || title == null) return byId;
    final wanted = title.toLowerCase();
    return tracks.indexWhere((t) => t.title.toLowerCase() == wanted);
  }

  static const _rowHeight = 60.0;

  double _heroHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    return _wide(width) ? top + 360 : top + math.min(width * 0.62, 260) + 300;
  }

  static bool _wide(double width) => width >= 680;

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final tracks = list?.tracks ?? const <YtTrack>[];
    final title = list?.title ?? widget.item.title;
    // Only what is playing, so the page rebuilds when the song changes and
    // not on everything else the controller reports.
    final current = context
        .select<AppController, ({String? id, String? title})>((c) {
          final index = c.songId;
          if (index < 0 || index >= c.songs.length) {
            return (id: null, title: null);
          }
          final song = c.songs[index];
          return (id: song.ytVideoId, title: song.title);
        });
    final currentIndex = current.id == null
        ? -1
        : _indexOf(tracks, current.id!, title: _isAlbum ? current.title : null);
    final player = context.read<AppController>().handler.player;

    return Scaffold(
      backgroundColor: Ember.ground,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: _heroHeight(context),
            backgroundColor: Ember.ground,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Ember.textPrimary,
            leading: const _BackButton(),
            title: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _collapsed ? 1 : 0,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _Hero(
                item: widget.item,
                list: list,
                isAlbum: _isAlbum,
                wide: _wide(MediaQuery.sizeOf(context).width),
                onPlay: tracks.isEmpty
                    ? null
                    : () => YtPlayback.play(context, tracks, 0),
                onShuffle: tracks.isEmpty
                    ? null
                    : () => YtPlayback.play(context, [...tracks]..shuffle(), 0),
                onDownload: tracks.isEmpty
                    ? null
                    : () => startPlaylistDownload(context, tracks),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: YtTrackSkeleton(),
            )
          else if (_error case final String message)
            SliverFillRemaining(
              hasScrollBody: false,
              child: YtMessage(
                icon: Icons.error_outline_rounded,
                title: "That didn't open",
                body: message,
                onRetry: _load,
              ),
            )
          else if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: YtMessage(
                icon: Icons.inbox_rounded,
                title: 'No tracks here',
                body: 'YouTube lists nothing playable in this one.',
                onRetry: _load,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              sliver: SliverFixedExtentList(
                itemExtent: _rowHeight,
                delegate: SliverChildBuilderDelegate(
                  childCount: tracks.length,
                  (context, index) => _isAlbum
                      ? _AlbumTrackRow(
                          track: tracks[index],
                          number: index + 1,
                          albumArtist: list?.artist,
                          current: index == currentIndex,
                          playing: player.playingStream,
                          onTap: () => YtPlayback.play(context, tracks, index),
                          onMore: () =>
                              showTrackActions(context, tracks[index]),
                        )
                      : _Highlighted(
                          current: index == currentIndex,
                          child: YtTrackRow(
                            track: tracks[index],
                            position: index + 1,
                            onTap: () =>
                                YtPlayback.play(context, tracks, index),
                            onMore: () =>
                                showTrackActions(context, tracks[index]),
                          ),
                        ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 110),
                child: Text(
                  list?.stats ?? _countLabel(tracks.length),
                  style: TextStyle(color: Ember.textTertiary, fontSize: 12.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _countLabel(int n) => n == 1 ? '1 song' : '$n songs';
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.black.withValues(alpha: 0.28),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox.square(
            dimension: 40,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: Ember.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The page's header: the cover large and blurred behind, then the facts and
/// the three buttons.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.item,
    required this.list,
    required this.isAlbum,
    required this.wide,
    required this.onPlay,
    required this.onShuffle,
    required this.onDownload,
  });

  final ExploreItem item;
  final YtTrackList? list;
  final bool isAlbum;
  final bool wide;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final cover = list?.thumbnail ?? item.thumbnail;
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = wide ? 240.0 : math.min(width * 0.62, 260.0);

    final details = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isAlbum ? _kind(list?.subtitle) ?? 'ALBUM' : 'PLAYLIST',
          style: const TextStyle(
            color: Ember.accent,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          list?.title ?? item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: AppFonts.displayStyle(
            color: Ember.textPrimary,
            fontSize: 26,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        _Credits(list: list, fallback: item.artist ?? item.subtitle),
        if (_facts case final facts?) ...[
          const SizedBox(height: 6),
          Text(
            facts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Ember.textSecondary, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            YtRoundButton(
              icon: Icons.download_rounded,
              tooltip: 'Download all',
              onTap: onDownload,
            ),
            const SizedBox(width: 18),
            YtRoundButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Play',
              size: 64,
              primary: true,
              onTap: onPlay,
            ),
            const SizedBox(width: 18),
            YtRoundButton(
              icon: Icons.shuffle_rounded,
              tooltip: 'Shuffle',
              onTap: onShuffle,
            ),
          ],
        ),
      ],
    );

    final art = Container(
      width: coverSize,
      height: coverSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: YtArtwork(url: cover, size: coverSize),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
            child: Opacity(
              opacity: 0.6,
              child: CachedNetworkImage(
                imageUrl: thumbnailAt(cover, 200),
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Ember.ground.withValues(alpha: 0.25),
                Ember.ground.withValues(alpha: 0.55),
                Ember.ground,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, top + kToolbarHeight, 24, 20),
          child: wide
              ? Row(
                  children: [
                    art,
                    const SizedBox(width: 28),
                    Expanded(child: details),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [art, const SizedBox(height: 20), details],
                ),
        ),
      ],
    );
  }

  /// "Album • 2019" → "ALBUM"; an EP or single says so.
  static String? _kind(String? subtitle) {
    final first = subtitle?.split('•').first.trim();
    return first == null || first.isEmpty ? null : first.toUpperCase();
  }

  /// "2019 • 12 songs • 42 minutes": the year from the subtitle, the rest
  /// as YouTube counts it.
  String? get _facts {
    final parts = <String>[
      ...?list?.subtitle?.split('•').skip(1).map((p) => p.trim()),
      ?list?.stats,
    ].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' • ');
  }
}

/// Who made it: each credited artist a link to their page, the first with
/// their portrait.
class _Credits extends StatelessWidget {
  const _Credits({required this.list, required this.fallback});

  final YtTrackList? list;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final artists = list?.artists ?? const <YtArtistRef>[];
    if (artists.isEmpty) {
      final text = list?.artist ?? fallback;
      if (text == null) return const SizedBox.shrink();
      return Text(
        text,
        style: const TextStyle(
          color: Ember.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < artists.length; i++)
          _ArtistLink(
            artist: artists[i],
            portrait: i == 0 ? list?.artistThumbnail : null,
          ),
      ],
    );
  }
}

class _ArtistLink extends StatelessWidget {
  const _ArtistLink({required this.artist, this.portrait});

  final YtArtistRef artist;
  final String? portrait;

  @override
  Widget build(BuildContext context) {
    final item = artist.asItem(thumbnail: portrait);
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: item == null
            ? null
            : () => Routes.routeTo(YtArtistPage(item: item), context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(portrait == null ? 12 : 4, 4, 12, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (portrait != null) ...[
                YtArtwork(url: portrait, size: 24, circular: true),
                const SizedBox(width: 8),
              ],
              Text(
                artist.name,
                style: const TextStyle(
                  color: Ember.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item != null) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Ember.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A track on an album: its number — or, playing, the bars — then its title,
/// any guests, and its length.
class _AlbumTrackRow extends StatelessWidget {
  const _AlbumTrackRow({
    required this.track,
    required this.number,
    required this.albumArtist,
    required this.current,
    required this.playing,
    required this.onTap,
    required this.onMore,
  });

  final YtTrack track;
  final int number;
  final String? albumArtist;
  final bool current;

  /// Whether the player is playing — the bars stand still while paused.
  final Stream<bool> playing;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final dimmed = !track.isAvailable;
    // The album's own artist goes without saying; guests are worth reading.
    final byline = track.artist != null && track.artist != albumArtist
        ? track.artist
        : null;
    return _Highlighted(
      current: current,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: dimmed ? null : onTap,
        child: Opacity(
          opacity: dimmed ? 0.4 : 1,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Center(
                    child: current
                        ? StreamBuilder<bool>(
                            stream: playing,
                            builder: (context, snap) =>
                                NowPlayingBars(playing: snap.data ?? true),
                          )
                        : Text(
                            '$number',
                            style: TextStyle(
                              color: Ember.textTertiary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: current ? Ember.accent : Ember.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (byline != null)
                        Text(
                          byline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Ember.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (track.hasVideo)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.videocam_rounded,
                      size: 15,
                      color: Ember.textTertiary,
                    ),
                  ),
                if (_duration case final duration?)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      duration,
                      style: TextStyle(
                        color: Ember.textTertiary,
                        fontSize: 12.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 19),
                  color: Ember.textSecondary,
                  visualDensity: VisualDensity.compact,
                  onPressed: onMore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? get _duration {
    final seconds = track.durationSecs;
    if (seconds == null || seconds <= 0) return null;
    final total = seconds.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

/// A soft gold wash behind the row that is playing.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.current, required this.child});

  final bool current;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: current
            ? Ember.accent.withValues(alpha: 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
