import '/exports/exports.dart';
import '/Helpers/index.dart';
import '../controllers/AppController.dart';
import '../widgets/ArtworkWidget.dart';

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
                const SizedBox(width: 8),
                // Track number
                if (showTrackNumber)
                  SizedBox(
                    width: 28,
                    child: isCurrentTrack
                        ? Icon(Icons.bar_chart_rounded,
                            color: accentColor, size: 20)
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
                if (showTrackNumber) const SizedBox(width: 12),
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
    this.showTrackNumbers = true,
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

    final currentSongId = controller.songId >= 0 &&
            controller.songId < controller.songs.length
        ? controller.songs[controller.songId].id
        : -1;

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
}
