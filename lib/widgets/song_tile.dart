import 'package:flutter/services.dart';

import '/exports/exports.dart';
import '/Helpers/index.dart';
import '../controllers/AppController.dart';
import '../widgets/ArtworkWidget.dart';

// ---------------------------------------------------------------------------
// SongTile — list-mode row (scale 0)
// ---------------------------------------------------------------------------

class SongTile extends StatelessWidget {
  final SongModel song;
  final int index;
  final bool isCurrentTrack;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showTrackNumber;
  final bool showDuration;
  final bool showOptionsIcon;

  const SongTile({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrentTrack,
    required this.onTap,
    this.onLongPress,
    this.showTrackNumber = true,
    this.showDuration = true,
    this.showOptionsIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: isCurrentTrack
            ? accentColor.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                // Accent bar for active track
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCurrentTrack ? accentColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                // Track number
                if (showTrackNumber)
                  SizedBox(
                    width: 22,
                    child: isCurrentTrack
                        ? Icon(Icons.bar_chart_rounded,
                            color: accentColor, size: 18)
                        : Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: onSurface.withValues(alpha: 0.35),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                if (showTrackNumber) const SizedBox(width: 8),
                // Artwork
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: ArtworkWidget(
                        width: 48,
                        height: 48,
                        size: 200,
                        quality: 50,
                        songId: song.id,
                        type: ArtworkType.AUDIO,
                        path: song.data,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Title + Artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrentTrack
                              ? accentColor
                              : onSurface,
                          fontSize: 15,
                          fontWeight:
                              isCurrentTrack ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrentTrack
                              ? accentColor.withValues(alpha: 0.6)
                              : onSurface.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Duration
                if (showDuration)
                  Text(
                    formatTime(Duration(milliseconds: song.duration ?? 0)),
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.35),
                      fontSize: 12,
                    ),
                  ),
                // Options icon
                if (showOptionsIcon)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SongGridTile — grid-mode card (scale 1 & 2)
// ---------------------------------------------------------------------------

class _SongGridTile extends StatelessWidget {
  final SongModel song;
  final bool isCurrentTrack;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SongGridTile({
    required this.song,
    required this.isCurrentTrack,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Material(
      color: isCurrentTrack
          ? accentColor.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Artwork
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ArtworkWidget(
                        size: 400,
                        quality: 80,
                        songId: song.id,
                        type: ArtworkType.AUDIO,
                        path: song.data,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      if (isCurrentTrack)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bar_chart_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrentTrack ? accentColor : onSurface,
                  fontSize: 13,
                  fontWeight:
                      isCurrentTrack ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            // Artist
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                song.artist ?? 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrentTrack
                      ? accentColor.withValues(alpha: 0.6)
                      : onSurface.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SongListView — pinch-to-zoom between list / 2-col / 3-col
// ---------------------------------------------------------------------------

class SongListView extends StatelessWidget {
  final List<SongModel> songs;
  final AppController controller;
  final bool showTrackNumbers;
  final bool showDuration;
  final bool showOptionsIcon;
  final void Function(SongModel song, int index)? onTap;
  final void Function(SongModel song, int index)? onLongPress;

  const SongListView({
    super.key,
    required this.songs,
    required this.controller,
    this.showTrackNumbers = false,
    this.showDuration = true,
    this.showOptionsIcon = true,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Center(
        child: Text(
          "No songs found",
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    // Listen to scale changes via Consumer so we don't need StatefulWidget.
    return Consumer<AppController>(
      builder: (context, ctrl, _) {
        return _PinchZoomWrapper(
          scale: ctrl.songGridScale,
          onScaleChange: (s) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ctrl.songGridScale = s;
            });
          },
          child: _buildForScale(context, ctrl.songGridScale),
        );
      },
    );
  }

  Widget _buildForScale(BuildContext context, int scale) {
    final currentSongId = controller.songId >= 0 &&
            controller.songId < controller.songs.length
        ? controller.songs[controller.songId].id
        : -1;

    // Scale 0 → list view
    if (scale == 0) {
      return ListView.builder(
        itemCount: songs.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = song.id == currentSongId;
          return SongTile(
            song: song,
            index: index,
            isCurrentTrack: isCurrent,
            showTrackNumber: showTrackNumbers,
            showDuration: showDuration,
            showOptionsIcon: showOptionsIcon,
            onTap: () => onTap?.call(song, index),
            onLongPress: onLongPress != null
                ? () => onLongPress!.call(song, index)
                : null,
          );
        },
      );
    }

    // Scale 1 → 2-col grid, scale 2 → 3-col grid
    final columns = scale == 1 ? 2 : 3;
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isCurrent = song.id == currentSongId;
        return _SongGridTile(
          song: song,
          isCurrentTrack: isCurrent,
          onTap: () => onTap?.call(song, index),
          onLongPress: onLongPress != null
              ? () => onLongPress!.call(song, index)
              : null,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _PinchZoomWrapper — uses raw Listener to detect two-finger pinch without
// competing with ListView/GridView scroll gestures.
// ---------------------------------------------------------------------------

class _PinchZoomWrapper extends StatefulWidget {
  final int scale;
  final ValueChanged<int> onScaleChange;
  final Widget child;

  const _PinchZoomWrapper({
    required this.scale,
    required this.onScaleChange,
    required this.child,
  });

  @override
  State<_PinchZoomWrapper> createState() => _PinchZoomWrapperState();
}

class _PinchZoomWrapperState extends State<_PinchZoomWrapper> {
  final Map<int, Offset> _pointers = {};
  double? _initialDistance;
  bool _handled = false;

  static const _pinchInRatio = 0.70;
  static const _pinchOutRatio = 1.45;

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _initialDistance = _distance();
      _handled = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length != 2 || _initialDistance == null || _handled) return;

    final ratio = _distance() / _initialDistance!;
    if (ratio < _pinchInRatio && widget.scale < 2) {
      _handled = true;
      HapticFeedback.selectionClick();
      widget.onScaleChange(widget.scale + 1);
    } else if (ratio > _pinchOutRatio && widget.scale > 0) {
      _handled = true;
      HapticFeedback.selectionClick();
      widget.onScaleChange(widget.scale - 1);
    }
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _initialDistance = null;
      _handled = false;
    }
  }

  double _distance() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      child: widget.child,
    );
  }
}
